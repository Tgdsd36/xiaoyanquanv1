package handler

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/config"
	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/internal/storage"
	myjwt "github.com/xiaoyanquan/server/pkg/jwt"
	"github.com/xiaoyanquan/server/pkg/response"
)

type AdminHandler struct {
	DB      *gorm.DB
	Cfg     *config.Config
	Store   storage.Storage
}

var (
	liveImgEditedNameRe = regexp.MustCompile(`^img[_-]?e(\d+)$`)
	liveCopySuffixRe    = regexp.MustCompile(`\s*\(\d+\)$`)
	liveSpaceNumSuffix  = regexp.MustCompile(`\s+\d+$`)
)

// ==================== 认证 ====================

func (h *AdminHandler) Login(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	var admin model.Admin
	if err := h.DB.Where("username = ?", req.Username).First(&admin).Error; err != nil {
		response.Unauthorized(c, "用户名或密码错误")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(req.Password)); err != nil {
		response.Unauthorized(c, "用户名或密码错误")
		return
	}

	token, err := myjwt.GenerateAdminToken(
		h.Cfg.JWT.Secret, admin.ID, admin.Username, admin.Role,
		24*time.Hour,
	)
	if err != nil {
		response.ServerError(c, "生成 Token 失败")
		return
	}

	response.Success(c, gin.H{
		"token":    token,
		"admin_id": admin.ID,
		"username": admin.Username,
		"role":     admin.Role,
	})
}

// ChangePassword 管理员修改自身密码
func (h *AdminHandler) ChangePassword(c *gin.Context) {
	var req struct {
		OldPassword string `json:"old_password" binding:"required,min=6"`
		NewPassword string `json:"new_password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	if req.OldPassword == req.NewPassword {
		response.BadRequest(c, 400, "新密码不能与旧密码相同")
		return
	}

	adminID := middleware.GetAdminID(c)
	if adminID == 0 {
		response.Unauthorized(c, "管理员认证失败")
		return
	}

	var admin model.Admin
	if err := h.DB.First(&admin, adminID).Error; err != nil {
		response.NotFound(c, "管理员不存在")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(req.OldPassword)); err != nil {
		response.BadRequest(c, response.ErrCodePasswordWrong, "旧密码错误")
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.ServerError(c, "密码加密失败")
		return
	}

	if err := h.DB.Model(&admin).Update("password_hash", string(hash)).Error; err != nil {
		response.ServerError(c, "密码更新失败")
		return
	}

	response.SuccessMessage(c, "密码修改成功")
}

// InitAdmin 开发环境自动创建默认管理员（GET /api/admin/init）
func (h *AdminHandler) InitAdmin(c *gin.Context) {
	if h.Cfg == nil || h.Cfg.Server.Mode != "debug" {
		response.Forbidden(c, "生产环境已禁用初始化接口")
		return
	}

	var count int64
	h.DB.Model(&model.Admin{}).Count(&count)
	if count > 0 {
		response.SuccessMessage(c, "管理员已存在")
		return
	}

	hash, _ := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
	admin := model.Admin{
		Username:     "admin",
		PasswordHash: string(hash),
		Role:         "admin",
	}
	h.DB.Create(&admin)
	response.Success(c, gin.H{"username": "admin", "password": "admin123"})
}

// ==================== Dashboard ====================

func (h *AdminHandler) Dashboard(c *gin.Context) {
	var stats struct {
		UserCount      int64 `json:"user_count"`
		MaterialCount  int64 `json:"material_count"`
		OrderCount     int64 `json:"order_count"`
		MemberCount    int64 `json:"member_count"`
		QuestionCount  int64 `json:"question_count"`
		TodayNewUsers  int64 `json:"today_new_users"`
		TodayDownloads int64 `json:"today_downloads"`
	}

	today := time.Now().Truncate(24 * time.Hour)

	h.DB.Model(&model.User{}).Count(&stats.UserCount)
	h.DB.Model(&model.Material{}).Count(&stats.MaterialCount)
	h.DB.Model(&model.Order{}).Where("status = ?", "paid").Count(&stats.OrderCount)
	h.DB.Model(&model.User{}).Where("member_type != ? AND member_expire_at > ?", "free", time.Now()).Count(&stats.MemberCount)
	h.DB.Model(&model.Question{}).Where("status = ?", "pending").Count(&stats.QuestionCount)
	h.DB.Model(&model.User{}).Where("created_at >= ?", today).Count(&stats.TodayNewUsers)
	h.DB.Model(&model.Download{}).Where("downloaded_at >= ?", today).Count(&stats.TodayDownloads)

	response.Success(c, stats)
}

// ==================== 素材管理 ====================

func (h *AdminHandler) MaterialList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	status := c.Query("status")
	materialType := c.Query("type")
	categoryID := c.Query("category_id")
	keyword := c.Query("keyword")

	query := h.DB.Model(&model.Material{})
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if materialType != "" {
		query = query.Where("type = ?", materialType)
	}
	if categoryID != "" {
		query = query.Where("category_id = ?", categoryID)
	}
	if keyword != "" {
		query = query.Where("title ILIKE ?", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var materials []model.Material
	query.Preload("Category").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&materials)

	response.SuccessPage(c, materials, total, page, pageSize)
}

func (h *AdminHandler) MaterialCreate(c *gin.Context) {
	var req struct {
		Title           string   `json:"title" binding:"required"`
		Description     string   `json:"description"`
		Type            string   `json:"type" binding:"required"`
		CategoryID      uint     `json:"category_id"`
		Gender          string   `json:"gender"`
		Tags            []string `json:"tags"`
		Width           int      `json:"width"`
		Height          int      `json:"height"`
		Duration        float64  `json:"duration"`
		FileSize        int64    `json:"file_size"`
		OriginalURLs    []string `json:"original_urls"`
		ThumbnailURL    string   `json:"thumbnail_url"`
		WatermarkURL    string   `json:"watermark_url"`
		PreviewMovURL   string   `json:"preview_mov_url"`
		ShowInspiration bool     `json:"show_inspiration"`
		ShowMoments     bool     `json:"show_moments"`
		Status          string   `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	filteredOriginals := make([]string, 0, len(req.OriginalURLs))
	for _, u := range req.OriginalURLs {
		if strings.TrimSpace(u) != "" {
			filteredOriginals = append(filteredOriginals, u)
		}
	}
	req.OriginalURLs = filteredOriginals

	switch req.Type {
	case "image":
		if req.ThumbnailURL == "" && len(req.OriginalURLs) > 0 {
			req.ThumbnailURL = req.OriginalURLs[0]
		}
	case "video":
		if len(req.OriginalURLs) == 0 {
			response.BadRequest(c, 400, "视频素材必须上传视频文件")
			return
		}
		if req.ThumbnailURL == "" {
			req.ThumbnailURL = req.OriginalURLs[0]
		}
	case "live_photo":
		if len(req.OriginalURLs) == 0 {
			response.BadRequest(c, 400, "Live Photo 必须上传静态图")
			return
		}
		if strings.TrimSpace(req.PreviewMovURL) == "" {
			response.BadRequest(c, 400, "Live Photo 必须上传动态视频")
			return
		}
		if req.ThumbnailURL == "" {
			req.ThumbnailURL = req.OriginalURLs[0]
		}
	default:
		response.BadRequest(c, 400, "不支持的素材类型")
		return
	}

	material := model.Material{
		Title:           req.Title,
		Description:     req.Description,
		Type:            req.Type,
		Tags:            req.Tags,
		Width:           req.Width,
		Height:          req.Height,
		Duration:        req.Duration,
		FileSize:        req.FileSize,
		OriginalURLs:    func() model.JSON { b, _ := json.Marshal(req.OriginalURLs); return model.JSON(b) }(),
		ThumbnailURL:    req.ThumbnailURL,
		WatermarkURL:    req.WatermarkURL,
		PreviewMovURL:   req.PreviewMovURL,
		ShowInspiration: req.ShowInspiration,
		ShowMoments:     req.ShowMoments,
		Status:          req.Status,
	}
	if req.CategoryID > 0 {
		material.CategoryID = &req.CategoryID
	}
	material.Gender = req.Gender
	if material.Status == "" {
		material.Status = "draft"
	}

	if err := h.DB.Create(&material).Error; err != nil {
		response.ServerError(c, "创建失败")
		return
	}
	response.Success(c, material)
}

func (h *AdminHandler) MaterialUpdate(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var material model.Material
	if err := h.DB.First(&material, id).Error; err != nil {
		response.NotFound(c, "素材不存在")
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	// Handle tags specially (convert []interface{} to pq.StringArray)
	if tagsRaw, ok := req["tags"]; ok {
		if tagsArr, ok := tagsRaw.([]interface{}); ok {
			tags := make([]string, 0, len(tagsArr))
			for _, t := range tagsArr {
				if s, ok := t.(string); ok {
					tags = append(tags, s)
				}
			}
			// Use struct update for tags
			delete(req, "tags")
			if err := h.DB.Model(&material).Update("tags", tags).Error; err != nil {
				response.ServerError(c, "更新失败")
				return
			}
		}
	}

	// Normalize category_id: 0 -> NULL (avoid FK error), number -> uint
	if cidRaw, ok := req["category_id"]; ok {
		switch v := cidRaw.(type) {
		case float64:
			if v <= 0 {
				req["category_id"] = nil
			} else {
				req["category_id"] = uint(v)
			}
		case int:
			if v <= 0 {
				req["category_id"] = nil
			} else {
				req["category_id"] = uint(v)
			}
		case int64:
			if v <= 0 {
				req["category_id"] = nil
			} else {
				req["category_id"] = uint(v)
			}
		case uint:
			if v == 0 {
				req["category_id"] = nil
			}
		}
	}

	// gender: 直接使用字符串
	// 无需特殊处理，string 值会直接更新

	// Normalize original_urls into jsonb
	if ouRaw, ok := req["original_urls"]; ok {
		b, err := json.Marshal(ouRaw)
		if err != nil {
			response.BadRequest(c, 400, "参数错误")
			return
		}
		req["original_urls"] = model.JSON(b)
	}

	if len(req) > 0 {
		if err := h.DB.Model(&material).Updates(req).Error; err != nil {
			response.ServerError(c, "更新失败")
			return
		}
	}
	h.DB.Preload("Category").First(&material, id)
	response.Success(c, material)
}

func (h *AdminHandler) MaterialDelete(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.DB.Delete(&model.Material{}, id).Error; err != nil {
		response.ServerError(c, "删除失败")
		return
	}
	response.SuccessMessage(c, "删除成功")
}

func (h *AdminHandler) MaterialBatchStatus(c *gin.Context) {
	var req struct {
		IDs    []uint `json:"ids" binding:"required"`
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	h.DB.Model(&model.Material{}).Where("id IN ?", req.IDs).Update("status", req.Status)
	response.SuccessMessage(c, "批量更新成功")
}

func (h *AdminHandler) MaterialBatchChannel(c *gin.Context) {
	var req struct {
		IDs     []uint `json:"ids" binding:"required"`
		Channel string `json:"channel" binding:"required,oneof=inspiration moments"`
		Enabled bool   `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	field := "show_inspiration"
	channelName := "找灵感"
	if req.Channel == "moments" {
		field = "show_moments"
		channelName = "朋友圈"
	}

	if err := h.DB.Model(&model.Material{}).Where("id IN ?", req.IDs).Update(field, req.Enabled).Error; err != nil {
		response.ServerError(c, "批量更新失败")
		return
	}

	if req.Enabled {
		response.SuccessMessage(c, "批量投放到"+channelName+"成功")
		return
	}
	response.SuccessMessage(c, "批量从"+channelName+"移除成功")
}

func (h *AdminHandler) MaterialBatchDelete(c *gin.Context) {
	var req struct {
		IDs []uint `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	h.DB.Where("id IN ?", req.IDs).Delete(&model.Material{})
	response.SuccessMessage(c, "批量删除成功")
}

// ==================== 分类管理 ====================

func (h *AdminHandler) CategoryList(c *gin.Context) {
	var categories []model.Category
	h.DB.Order("sort_order ASC, id ASC").Find(&categories)
	// 组装树形结构
	tree := buildAdminCategoryTree(categories, nil)
	response.Success(c, tree)
}

// buildAdminCategoryTree 组装分类树（管理后台用，含所有字段）
func buildAdminCategoryTree(all []model.Category, parentID *uint) []model.Category {
	var result []model.Category
	for _, cat := range all {
		if (parentID == nil && cat.ParentID == nil) ||
			(parentID != nil && cat.ParentID != nil && *parentID == *cat.ParentID) {
			cat.Children = buildAdminCategoryTree(all, &cat.ID)
			result = append(result, cat)
		}
	}
	return result
}

func (h *AdminHandler) CategoryCreate(c *gin.Context) {
	var req struct {
		Name      string `json:"name" binding:"required"`
		Slug      string `json:"slug"`
		ParentID  *uint  `json:"parent_id"` // nil=一级分类，非 nil=二级
		SortOrder int    `json:"sort_order"`
		IsVisible bool   `json:"is_visible"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	// 自动生成 slug
	slug := req.Slug
	if slug == "" {
		slug = fmt.Sprintf("cat_%d", time.Now().UnixMilli())
	}

	// 如果指定了 parent_id，验证父分类存在且是一级
	if req.ParentID != nil && *req.ParentID > 0 {
		var parent model.Category
		if err := h.DB.First(&parent, *req.ParentID).Error; err != nil {
			response.BadRequest(c, 400, "父分类不存在")
			return
		}
		if parent.ParentID != nil {
			response.BadRequest(c, 400, "只支持两级分类")
			return
		}
	}

	cat := model.Category{
		Name:      req.Name,
		Slug:      slug,
		ParentID:  req.ParentID,
		SortOrder: req.SortOrder,
		IsVisible: req.IsVisible,
	}
	if err := h.DB.Create(&cat).Error; err != nil {
		response.ServerError(c, "创建失败")
		return
	}
	response.Success(c, cat)
}

func (h *AdminHandler) CategoryUpdate(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var cat model.Category
	if err := h.DB.First(&cat, id).Error; err != nil {
		response.NotFound(c, "分类不存在")
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	h.DB.Model(&cat).Updates(req)
	response.Success(c, cat)
}

func (h *AdminHandler) CategoryDelete(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var cat model.Category
	if err := h.DB.First(&cat, id).Error; err != nil {
		response.NotFound(c, "分类不存在")
		return
	}

	// 收集子分类 ID
	var childIDs []uint
	h.DB.Model(&model.Category{}).Where("parent_id = ?", cat.ID).Pluck("id", &childIDs)
	allIDs := append([]uint{cat.ID}, childIDs...)

	// 解除素材引用
	h.DB.Model(&model.Material{}).Where("category_id IN ?", allIDs).Update("category_id", nil)
	h.DB.Model(&model.Material{}).Where("gender_category_id IN ?", allIDs).Update("gender_category_id", nil)

	// 删除子分类 + 本身
	if len(childIDs) > 0 {
		h.DB.Where("id IN ?", childIDs).Delete(&model.Category{})
	}
	if err := h.DB.Delete(&cat).Error; err != nil {
		response.ServerError(c, "删除失败")
		return
	}
	response.SuccessMessage(c, "删除成功")
}

func (h *AdminHandler) CategoryBatchDelete(c *gin.Context) {
	var req struct {
		IDs []uint `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	// 收集所有要删除的 ID（包含子分类）
	var childIDs []uint
	h.DB.Model(&model.Category{}).Where("parent_id IN ?", req.IDs).Pluck("id", &childIDs)
	allIDs := append(req.IDs, childIDs...)

	// 解除素材对这些分类的引用（外键约束）
	h.DB.Model(&model.Material{}).Where("category_id IN ?", allIDs).Update("category_id", nil)
	h.DB.Model(&model.Material{}).Where("gender_category_id IN ?", allIDs).Update("gender_category_id", nil)

	// 先删子分类
	if len(childIDs) > 0 {
		h.DB.Where("id IN ?", childIDs).Delete(&model.Category{})
	}
	// 再删本身
	if err := h.DB.Where("id IN ?", req.IDs).Delete(&model.Category{}).Error; err != nil {
		response.ServerError(c, "删除失败: "+err.Error())
		return
	}
	response.SuccessMessage(c, "批量删除成功")
}

func (h *AdminHandler) CategorySort(c *gin.Context) {
	var req struct {
		IDs []uint `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	for i, id := range req.IDs {
		h.DB.Model(&model.Category{}).Where("id = ?", id).Update("sort_order", i)
	}
	response.SuccessMessage(c, "排序成功")
}

// ==================== 提问管理 ====================

func (h *AdminHandler) QuestionList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	status := c.Query("status")

	query := h.DB.Model(&model.Question{})
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var questions []model.Question
	query.Preload("User").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&questions)

	response.SuccessPage(c, questions, total, page, pageSize)
}

func (h *AdminHandler) QuestionReply(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var question model.Question
	if err := h.DB.First(&question, id).Error; err != nil {
		response.NotFound(c, "提问不存在")
		return
	}

	var req struct {
		ReplyText string `json:"reply_text" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	adminID := middleware.GetAdminID(c)
	now := time.Now()
	h.DB.Model(&question).Updates(map[string]interface{}{
		"reply_text": req.ReplyText,
		"replied_by": adminID,
		"replied_at": now,
		"status":     "replied",
	})

	response.SuccessMessage(c, "回复成功")
}

// ==================== 用户管理 ====================

func (h *AdminHandler) UserCreate(c *gin.Context) {
	var req struct {
		Phone    string `json:"phone" binding:"required"`
		Nickname string `json:"nickname"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	// 检查手机号是否已存在
	var count int64
	h.DB.Model(&model.User{}).Where("phone = ?", req.Phone).Count(&count)
	if count > 0 {
		response.BadRequest(c, 400, "该手机号已注册")
		return
	}

	hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	user := model.User{
		Phone:        req.Phone,
		Nickname:     req.Nickname,
		PasswordHash: string(hash),
		Status:       "active",
	}
	if err := h.DB.Create(&user).Error; err != nil {
		response.ServerError(c, "创建失败")
		return
	}
	response.Success(c, user)
}

func (h *AdminHandler) UserDelete(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.DB.Delete(&model.User{}, id).Error; err != nil {
		response.ServerError(c, "删除失败")
		return
	}
	response.SuccessMessage(c, "删除成功")
}

func (h *AdminHandler) UserBatchDelete(c *gin.Context) {
	var req struct {
		IDs []uint `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	h.DB.Where("id IN ?", req.IDs).Delete(&model.User{})
	response.SuccessMessage(c, "批量删除成功")
}

func (h *AdminHandler) UserBatchStatus(c *gin.Context) {
	var req struct {
		IDs    []uint `json:"ids" binding:"required"`
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	h.DB.Model(&model.User{}).Where("id IN ?", req.IDs).Update("status", req.Status)
	response.SuccessMessage(c, "批量更新成功")
}

func (h *AdminHandler) UserToggleStatus(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var user model.User
	if err := h.DB.First(&user, id).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	var req struct {
		Status string `json:"status" binding:"required"` // active, disabled
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	h.DB.Model(&user).Update("status", req.Status)
	response.Success(c, gin.H{"id": user.ID, "status": req.Status})
}

func (h *AdminHandler) UserSetMembership(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	if id <= 0 {
		response.BadRequest(c, 400, "用户ID无效")
		return
	}

	var user model.User
	if err := h.DB.First(&user, id).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	var req struct {
		MemberType string `json:"member_type" binding:"required,oneof=free pro"`
		ExpireDays int    `json:"expire_days"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	updates := map[string]interface{}{
		"member_type": req.MemberType,
	}

	expireAtText := ""
	if req.MemberType == "free" {
		updates["member_expire_at"] = nil
	} else {
		days := req.ExpireDays
		if days <= 0 {
			days = 30
		}
		if days > 3650 {
			response.BadRequest(c, 400, "会员天数不能超过3650天")
			return
		}

		base := time.Now()
		if user.MemberExpireAt != nil && user.MemberExpireAt.After(base) {
			base = *user.MemberExpireAt
		}
		expireAt := base.AddDate(0, 0, days)
		updates["member_expire_at"] = expireAt
		expireAtText = expireAt.Format("2006-01-02 15:04:05")
	}

	if err := h.DB.Model(&user).Updates(updates).Error; err != nil {
		response.ServerError(c, "设置会员失败")
		return
	}

	response.Success(c, gin.H{
		"id":               user.ID,
		"member_type":      req.MemberType,
		"member_expire_at": expireAtText,
	})
}

func (h *AdminHandler) UserDeviceUnbind(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	if id <= 0 {
		response.BadRequest(c, 400, "用户ID无效")
		return
	}

	if err := h.DB.Where("user_id = ?", id).Delete(&model.UserDeviceBinding{}).Error; err != nil {
		response.ServerError(c, "解绑失败")
		return
	}

	response.SuccessMessage(c, "设备解绑成功")
}

func (h *AdminHandler) UserList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	memberType := c.Query("member_type")
	deviceBound := c.Query("device_bound") // 1:已绑定 0:未绑定

	query := h.DB.Model(&model.User{})
	if keyword != "" {
		query = query.Where("phone LIKE ? OR nickname LIKE ?", "%"+keyword+"%", "%"+keyword+"%")
	}
	if memberType != "" {
		if memberType == "pro" {
			query = query.Where("member_type IN ?", []string{"pro", "flagship"})
		} else {
			query = query.Where("member_type = ?", memberType)
		}
	}
	if deviceBound == "1" {
		query = query.Where("EXISTS (SELECT 1 FROM user_device_bindings udb WHERE udb.user_id = users.id)")
	} else if deviceBound == "0" {
		query = query.Where("NOT EXISTS (SELECT 1 FROM user_device_bindings udb WHERE udb.user_id = users.id)")
	}

	var total int64
	query.Count(&total)

	var users []model.User
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&users)

	type userListItem struct {
		model.User
		DeviceBound    bool       `json:"device_bound"`
		DeviceID       string     `json:"device_id,omitempty"`
		DeviceName     string     `json:"device_name,omitempty"`
		DevicePlatform string     `json:"device_platform,omitempty"`
		DeviceBoundAt  *time.Time `json:"device_bound_at,omitempty"`
	}

	items := make([]userListItem, 0, len(users))
	if len(users) == 0 {
		response.SuccessPage(c, items, total, page, pageSize)
		return
	}

	userIDs := make([]uint, 0, len(users))
	for _, u := range users {
		userIDs = append(userIDs, u.ID)
	}

	var bindings []model.UserDeviceBinding
	h.DB.Where("user_id IN ?", userIDs).Find(&bindings)

	bindingMap := make(map[uint]model.UserDeviceBinding, len(bindings))
	for _, b := range bindings {
		bindingMap[b.UserID] = b
	}

	for _, u := range users {
		item := userListItem{User: u}
		if b, ok := bindingMap[u.ID]; ok {
			item.DeviceBound = true
			item.DeviceID = b.DeviceID
			item.DeviceName = b.DeviceName
			item.DevicePlatform = b.Platform
			item.DeviceBoundAt = &b.BoundAt
		}
		items = append(items, item)
	}

	response.SuccessPage(c, items, total, page, pageSize)
}

func (h *AdminHandler) UserDetail(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var user model.User
	if err := h.DB.First(&user, id).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 附加统计
	var downloadCount, favoriteCount, questionCount int64
	h.DB.Model(&model.Download{}).Where("user_id = ?", id).Count(&downloadCount)
	h.DB.Model(&model.Favorite{}).Where("user_id = ?", id).Count(&favoriteCount)
	h.DB.Model(&model.Question{}).Where("user_id = ?", id).Count(&questionCount)

	var binding model.UserDeviceBinding
	device := gin.H{"bound": false}
	if err := h.DB.Where("user_id = ?", id).First(&binding).Error; err == nil {
		device = gin.H{
			"bound":           true,
			"device_id":       binding.DeviceID,
			"device_name":     binding.DeviceName,
			"device_platform": binding.Platform,
			"bound_at":        binding.BoundAt,
		}
	}

	response.Success(c, gin.H{
		"user":           user,
		"device":         device,
		"download_count": downloadCount,
		"favorite_count": favoriteCount,
		"question_count": questionCount,
	})
}

// ==================== 订单管理 ====================

func (h *AdminHandler) OrderList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	status := c.Query("status")

	query := h.DB.Model(&model.Order{})
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var orders []model.Order
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&orders)

	response.SuccessPage(c, orders, total, page, pageSize)
}

// ==================== 系统配置 ====================

func (h *AdminHandler) ConfigList(c *gin.Context) {
	var configs []model.SystemConfig
	h.DB.Find(&configs)
	response.Success(c, configs)
}

// ==================== 素材库(文件管理) ====================

func (h *AdminHandler) AssetUpload(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, 400, "请选择文件")
		return
	}

	folder := strings.TrimSpace(c.PostForm("folder")) // 分类文件夹

	// 检查文件类型
	ext := strings.ToLower(filepath.Ext(file.Filename))
	fileType := "image"
	switch ext {
	case ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".heic", ".heif":
		fileType = "image"
	case ".mp4", ".mov", ".avi", ".mkv":
		fileType = "video"
	default:
		response.BadRequest(c, 400, "不支持的文件格式")
		return
	}

	newFilename := uuid.New().String() + ext
	dateDir := time.Now().Format("2006/01")
	key := fmt.Sprintf("assets/%s/%s", dateDir, newFilename)

	// 无论 COS 是否启用，都先存本地临时文件（后处理需要）
	tmpDir := filepath.Join(os.TempDir(), "xyq-upload", dateDir)
	os.MkdirAll(tmpDir, 0755)
	tmpPath := filepath.Join(tmpDir, newFilename)
	if err := c.SaveUploadedFile(file, tmpPath); err != nil {
		response.ServerError(c, "文件保存失败")
		return
	}

	var assetURL string
	var previewURL string

	if h.Store != nil && h.Store.Enabled() {
		// COS 模式：上传原文件到 COS
		tmpFile, err := os.Open(tmpPath)
		if err != nil {
			response.ServerError(c, "读取文件失败")
			return
		}
		defer tmpFile.Close()
		if err := h.Store.Upload(key, tmpFile, file.Size); err != nil {
			response.ServerError(c, "上传到对象存储失败")
			return
		}
		assetURL = key

		// HEIC 预览：本地转换后上传到 COS
		if isHEICExt(ext) {
			if pvURL, pvPath, err := generateHEICPreviewLocal(tmpPath, key); err == nil {
				previewURL = pvURL
				go h.uploadLocalFileToCOS(pvPath, pvURL)
			}
		}
		// 视频转码：本地转换后上传到 COS
		if fileType == "video" {
			go func(srcPath, srcKey string) {
				if mobileKey, mobilePath, err := generateMobileVideoLocal(srcPath, srcKey); err == nil {
					h.uploadLocalFileToCOS(mobilePath, mobileKey)
					os.Remove(mobilePath)
				}
				os.Remove(srcPath)
			}(tmpPath, key)
		} else {
			// 图片上传完成后清理临时文件
			go os.Remove(tmpPath)
		}
	} else {
		// 本地模式：将临时文件移动到正式目录
		uploadDir := filepath.Join("static", "uploads", dateDir)
		os.MkdirAll(uploadDir, 0755)
		dstPath := filepath.Join(uploadDir, newFilename)
		os.Rename(tmpPath, dstPath)

		assetURL = fmt.Sprintf("/static/uploads/%s/%s", dateDir, newFilename)
		if isHEICExt(ext) {
			if generated, err := ensureHEICPreview(assetURL); err == nil {
				previewURL = generated
			}
		}
		if fileType == "video" {
			go func(sourceURL string) {
				_, _ = ensureMobileVideoVariant(sourceURL)
			}(assetURL)
		}
	}

	asset := model.Asset{
		Filename:     newFilename,
		OriginalName: file.Filename,
		URL:          assetURL,
		PreviewURL:   previewURL,
		FileType:     fileType,
		Folder:       folder,
		FileSize:     file.Size,
	}
	if err := h.DB.Create(&asset).Error; err != nil {
		response.ServerError(c, "保存记录失败")
		return
	}
	if liveRole := resolveLiveRole(c.PostForm("live_role"), ext); liveRole != "" {
		_, _ = h.attachAssetToLivePack(asset, liveRole)
	}
	if folder != "" {
		_ = h.DB.FirstOrCreate(&model.AssetFolder{}, model.AssetFolder{Name: folder}).Error
	}
	response.Success(c, asset)
}

// uploadLocalFileToCOS 将本地文件上传到 COS（后处理产物用）
func (h *AdminHandler) uploadLocalFileToCOS(localPath, cosKey string) {
	f, err := os.Open(localPath)
	if err != nil {
		return
	}
	defer f.Close()
	fi, err := f.Stat()
	if err != nil {
		return
	}
	_ = h.Store.Upload(cosKey, f, fi.Size())
	os.Remove(localPath)
}

// generateHEICPreviewLocal 本地生成 HEIC 预览 JPG，返回 COS key 和本地路径
func generateHEICPreviewLocal(sourcePath, sourceKey string) (cosKey string, localPath string, err error) {
	baseNoExt := strings.TrimSuffix(filepath.Base(sourcePath), filepath.Ext(sourcePath))
	previewFilename := baseNoExt + "_preview.jpg"
	previewPath := filepath.Join(filepath.Dir(sourcePath), previewFilename)
	previewKey := path.Join(path.Dir(sourceKey), previewFilename)

	// 优先 sips，其次 ffmpeg
	if p, _ := exec.LookPath("sips"); p != "" {
		if exec.Command("sips", "-s", "format", "jpeg", sourcePath, "--out", previewPath).Run() == nil {
			return previewKey, previewPath, nil
		}
	}
	if p, _ := exec.LookPath("ffmpeg"); p != "" {
		if exec.Command("ffmpeg", "-y", "-i", sourcePath, "-frames:v", "1", previewPath).Run() == nil {
			return previewKey, previewPath, nil
		}
	}
	return "", "", fmt.Errorf("heic preview generation failed")
}

// generateMobileVideoLocal 本地生成移动端 MP4，返回 COS key 和本地路径
func generateMobileVideoLocal(sourcePath, sourceKey string) (cosKey string, localPath string, err error) {
	ext := strings.ToLower(filepath.Ext(sourcePath))
	if ext == ".mp4" {
		return sourceKey, sourcePath, nil
	}

	baseNoExt := strings.TrimSuffix(filepath.Base(sourcePath), ext)
	mobileFilename := baseNoExt + "_mobile.mp4"
	mobilePath := filepath.Join(filepath.Dir(sourcePath), mobileFilename)
	mobileKey := path.Join(path.Dir(sourceKey), mobileFilename)

	if _, lookErr := exec.LookPath("ffmpeg"); lookErr != nil {
		return "", "", lookErr
	}
	cmd := exec.Command(
		"ffmpeg", "-y", "-i", sourcePath,
		"-movflags", "+faststart",
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "24",
		"-pix_fmt", "yuv420p",
		"-c:a", "aac", "-b:a", "128k",
		mobilePath,
	)
	if err := cmd.Run(); err != nil {
		return "", "", err
	}
	return mobileKey, mobilePath, nil
}

// AssetInspect 上传诊断（不入库），用于定位移动端文件选择后的真实文件类型。
func (h *AdminHandler) AssetInspect(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, 400, "请选择文件")
		return
	}

	src, err := file.Open()
	if err != nil {
		response.ServerError(c, "读取文件失败")
		return
	}
	defer src.Close()

	header := make([]byte, 512)
	n, _ := io.ReadFull(src, header)
	if n <= 0 {
		n, _ = src.Read(header)
	}
	if n < 0 {
		n = 0
	}
	header = header[:n]

	ext := strings.ToLower(filepath.Ext(file.Filename))
	filenameNoExt := strings.TrimSuffix(file.Filename, filepath.Ext(file.Filename))
	baseName := normalizeLiveBaseName(filenameNoExt)
	clientContentType := strings.TrimSpace(file.Header.Get("Content-Type"))
	sniffContentType := http.DetectContentType(header)
	ftypBrand := detectISOBaseMediaBrand(header)
	liveRole := detectLiveRoleByHeader(ext, clientContentType, sniffContentType, ftypBrand)

	guessType := "unknown"
	switch {
	case liveRole == "image":
		guessType = "live_image_candidate"
	case liveRole == "video":
		guessType = "live_video_candidate"
	case isImageExt(ext):
		guessType = "image"
	case isVideoExt(ext):
		guessType = "video"
	}

	suggestion := "当前文件无法直接确认是 Live 套件成员"
	if liveRole == "image" {
		suggestion = "识别为 Live 静态图候选（还需要同名 MOV）"
	} else if liveRole == "video" {
		suggestion = "识别为 Live 动态视频候选（还需要同名图片文件）"
	}

	response.Success(c, gin.H{
		"filename":             file.Filename,
		"ext":                  ext,
		"size":                 file.Size,
		"base_name":            baseName,
		"client_content_type":  clientContentType,
		"sniff_content_type":   sniffContentType,
		"ftyp_brand":           ftypBrand,
		"guess_type":           guessType,
		"live_role_candidate":  liveRole,
		"can_split_to_live":    false,
		"split_hint":           "仅有静态图无法在服务端拆分出 MOV；必须上传原始 HEIC/HEIF + MOV 两个文件",
		"suggestion":           suggestion,
		"header_sample_hex":    bytesToHexPreview(header),
	})
}

func isImageExt(ext string) bool {
	switch strings.ToLower(strings.TrimSpace(ext)) {
	case ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".heic", ".heif":
		return true
	default:
		return false
	}
}

func isVideoExt(ext string) bool {
	switch strings.ToLower(strings.TrimSpace(ext)) {
	case ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm":
		return true
	default:
		return false
	}
}

func detectISOBaseMediaBrand(header []byte) string {
	if len(header) < 12 {
		return ""
	}
	if string(header[4:8]) != "ftyp" {
		return ""
	}
	brand := string(header[8:12])
	brand = strings.TrimSpace(brand)
	return strings.Trim(brand, "\x00")
}

func detectLiveRoleByHeader(ext, clientContentType, sniffContentType, ftypBrand string) string {
	if role := resolveLiveRole("", ext); role != "" {
		return role
	}

	lowerClient := strings.ToLower(strings.TrimSpace(clientContentType))
	lowerSniff := strings.ToLower(strings.TrimSpace(sniffContentType))
	lowerBrand := strings.ToLower(strings.TrimSpace(ftypBrand))

	if strings.Contains(lowerClient, "heic") || strings.Contains(lowerClient, "heif") ||
		strings.Contains(lowerSniff, "heic") || strings.Contains(lowerSniff, "heif") {
		return "image"
	}

	if strings.Contains(lowerClient, "quicktime") || strings.Contains(lowerSniff, "quicktime") {
		return "video"
	}

	switch lowerBrand {
	case "heic", "heix", "hevc", "mif1", "msf1":
		return "image"
	case "qt":
		return "video"
	default:
		return ""
	}
}

func bytesToHexPreview(header []byte) string {
	if len(header) == 0 {
		return ""
	}
	previewLen := len(header)
	if previewLen > 32 {
		previewLen = 32
	}
	return hex.EncodeToString(header[:previewLen])
}

func (h *AdminHandler) AssetList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "40"))
	fileType := c.Query("file_type")
	folder := c.Query("folder")
	keyword := c.Query("keyword")

	query := h.DB.Model(&model.Asset{})
	// 排除已关联到 Live 套件的散件，避免 Live 照片的 JPG/MOV 混入普通图片/视频分类
	if c.Query("exclude_live") == "true" {
		query = query.Where(`id NOT IN (
			SELECT image_asset_id FROM live_asset_packs WHERE image_asset_id IS NOT NULL
			UNION
			SELECT video_asset_id FROM live_asset_packs WHERE video_asset_id IS NOT NULL
		)`)
	}
	if fileType != "" {
		switch strings.ToLower(strings.TrimSpace(fileType)) {
		case "image":
			// 兼容历史数据：file_type 可能被存成 heic/jpg 等具体扩展名
			query = query.Where(`
				lower(coalesce(file_type, '')) IN ('image', 'heic', 'heif', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp')
				OR lower(coalesce(url, '')) LIKE '%.heic'
				OR lower(coalesce(url, '')) LIKE '%.heif'
				OR lower(coalesce(url, '')) LIKE '%.jpg'
				OR lower(coalesce(url, '')) LIKE '%.jpeg'
				OR lower(coalesce(url, '')) LIKE '%.png'
				OR lower(coalesce(url, '')) LIKE '%.gif'
				OR lower(coalesce(url, '')) LIKE '%.webp'
				OR lower(coalesce(url, '')) LIKE '%.bmp'
			`)
		case "video":
			// 兼容历史数据：file_type 可能被存成 mov/mp4 等具体扩展名
			query = query.Where(`
				lower(coalesce(file_type, '')) IN ('video', 'mov', 'mp4', 'm4v', 'avi', 'mkv', 'webm')
				OR lower(coalesce(url, '')) LIKE '%.mov'
				OR lower(coalesce(url, '')) LIKE '%.mp4'
				OR lower(coalesce(url, '')) LIKE '%.m4v'
				OR lower(coalesce(url, '')) LIKE '%.avi'
				OR lower(coalesce(url, '')) LIKE '%.mkv'
				OR lower(coalesce(url, '')) LIKE '%.webm'
			`)
		default:
			query = query.Where("lower(file_type) = ?", strings.ToLower(strings.TrimSpace(fileType)))
		}
	}
	if folder != "" {
		query = query.Where("folder = ?", folder)
	}
	if keyword != "" {
		query = query.Where("original_name ILIKE ?", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var assets []model.Asset
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&assets)
	baseURL := h.Cfg.Server.BaseURL
	for i := range assets {
		if assets[i].PreviewURL == "" && assets[i].FileType == "image" && isHEICURL(assets[i].URL) {
			if generated, err := ensureHEICPreview(assets[i].URL); err == nil && generated != "" {
				assets[i].PreviewURL = generated
				h.DB.Model(&model.Asset{}).
					Where("id = ?", assets[i].ID).
					Update("preview_url", generated)
			}
		}
		assets[i].URL = fullURL(baseURL, assets[i].URL)
		assets[i].PreviewURL = fullURL(baseURL, assets[i].PreviewURL)
	}

	response.SuccessPage(c, assets, total, page, pageSize)
}

// AssetLivePackList Live 套件列表（HEIC + MOV 组合）
func (h *AdminHandler) AssetLivePackList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	folder := strings.TrimSpace(c.Query("folder"))
	keyword := strings.TrimSpace(c.Query("keyword"))
	status := strings.TrimSpace(c.Query("status"))

	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 {
		pageSize = 20
	}

	_ = h.ensureLegacyLivePacks()

	query := h.DB.Model(&model.LiveAssetPack{})
	if folder != "" {
		query = query.Where("folder = ?", folder)
	}
	if keyword != "" {
		query = query.Where("base_name ILIKE ?", "%"+keyword+"%")
	}
	if status == "complete" || status == "incomplete" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var packs []model.LiveAssetPack
	query.Order("created_at DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&packs)

	type packItem struct {
		ID              uint     `json:"id"`
		Folder          string   `json:"folder"`
		BaseName        string   `json:"base_name"`
		Status          string   `json:"status"`
		Missing         []string `json:"missing"`
		ImageAssetID    uint     `json:"image_asset_id,omitempty"`
		ImageURL        string   `json:"image_url,omitempty"`
		ImagePreviewURL string   `json:"image_preview_url,omitempty"`
		ImageName       string   `json:"image_name,omitempty"`
		VideoAssetID    uint     `json:"video_asset_id,omitempty"`
		VideoURL        string   `json:"video_url,omitempty"`
		VideoName       string   `json:"video_name,omitempty"`
		CreatedAt       string   `json:"created_at"`
	}

	assetIDs := make([]uint, 0, len(packs)*2)
	for _, p := range packs {
		if p.ImageAssetID != nil {
			assetIDs = append(assetIDs, *p.ImageAssetID)
		}
		if p.VideoAssetID != nil {
			assetIDs = append(assetIDs, *p.VideoAssetID)
		}
	}

	assetMap := map[uint]model.Asset{}
	if len(assetIDs) > 0 {
		var assets []model.Asset
		h.DB.Where("id IN ?", assetIDs).Find(&assets)
		for _, a := range assets {
			assetMap[a.ID] = a
		}
	}

	baseURL := h.Cfg.Server.BaseURL
	list := make([]packItem, 0, len(packs))
	for _, p := range packs {
		item := packItem{
			ID:        p.ID,
			Folder:    p.Folder,
			BaseName:  p.BaseName,
			Status:    p.Status,
			CreatedAt: p.CreatedAt.Format("2006-01-02 15:04:05"),
		}
		if p.ImageAssetID != nil {
			item.ImageAssetID = *p.ImageAssetID
			if a, ok := assetMap[*p.ImageAssetID]; ok {
				item.ImageURL = fullURL(baseURL, a.URL)
				item.ImageName = a.OriginalName
				if a.PreviewURL != "" {
					item.ImagePreviewURL = fullURL(baseURL, a.PreviewURL)
				} else if isHEICURL(a.URL) {
					if generated, err := ensureHEICPreview(a.URL); err == nil && generated != "" {
						item.ImagePreviewURL = fullURL(baseURL, generated)
						h.DB.Model(&model.Asset{}).
							Where("id = ?", a.ID).
							Update("preview_url", generated)
					}
				}
			}
		}
		if p.VideoAssetID != nil {
			item.VideoAssetID = *p.VideoAssetID
			if a, ok := assetMap[*p.VideoAssetID]; ok {
				item.VideoURL = fullURL(baseURL, a.URL)
				item.VideoName = a.OriginalName
			}
		}

		missing := make([]string, 0, 2)
		if p.ImageAssetID == nil {
			missing = append(missing, "静态图")
		}
		if p.VideoAssetID == nil {
			missing = append(missing, "MOV视频")
		}
		item.Missing = missing
		if len(missing) > 0 {
			item.Status = "incomplete"
		} else {
			item.Status = "complete"
		}

		list = append(list, item)
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// AssetFolders 获取所有分类列表
// 计数逻辑：Live Photo 的图片+视频按套件计为 1，而非拆开计为 2
func (h *AdminHandler) AssetFolders(c *gin.Context) {
	// 1. 每个文件夹的资产总数
	type folderCount struct {
		Folder string `json:"folder"`
		Count  int64  `json:"count"`
	}
	var assetFolders []folderCount
	h.DB.Model(&model.Asset{}).
		Select("folder, count(*) as count").
		Group("folder").
		Scan(&assetFolders)

	// 2. 每个文件夹的 Live 套件数
	var livePackFolders []folderCount
	h.DB.Model(&model.LiveAssetPack{}).
		Select("folder, count(*) as count").
		Group("folder").
		Scan(&livePackFolders)

	// 3. 每个文件夹中被 Live 套件引用的资产数（图片+视频都算）
	var liveAssetFolders []folderCount
	h.DB.Raw(`
		SELECT a.folder, COUNT(DISTINCT a.id) as count
		FROM assets a
		WHERE a.id IN (
			SELECT image_asset_id FROM live_asset_packs WHERE image_asset_id IS NOT NULL
			UNION
			SELECT video_asset_id FROM live_asset_packs WHERE video_asset_id IS NOT NULL
		)
		GROUP BY a.folder
	`).Scan(&liveAssetFolders)

	// 汇总：实际数量 = 资产总数 - Live关联资产数 + Live套件数
	assetCountMap := map[string]int64{}
	for _, item := range assetFolders {
		assetCountMap[strings.TrimSpace(item.Folder)] += item.Count
	}
	livePackCountMap := map[string]int64{}
	for _, item := range livePackFolders {
		livePackCountMap[strings.TrimSpace(item.Folder)] += item.Count
	}
	liveAssetCountMap := map[string]int64{}
	for _, item := range liveAssetFolders {
		liveAssetCountMap[strings.TrimSpace(item.Folder)] += item.Count
	}

	folderCountMap := map[string]int64{}
	for name, cnt := range assetCountMap {
		folderCountMap[name] = cnt - liveAssetCountMap[name] + livePackCountMap[name]
	}
	// 确保只有 Live 套件而无独立资产的文件夹也出现
	for name, cnt := range livePackCountMap {
		if _, exists := folderCountMap[name]; !exists {
			folderCountMap[name] = cnt
		}
	}

	var folderDefs []model.AssetFolder
	h.DB.Order("name ASC").Find(&folderDefs)
	for _, folder := range folderDefs {
		name := strings.TrimSpace(folder.Name)
		if name == "" {
			continue
		}
		if _, exists := folderCountMap[name]; !exists {
			folderCountMap[name] = 0
		}
	}

	uncategorizedCount, hasUncategorized := folderCountMap[""]
	delete(folderCountMap, "")

	names := make([]string, 0, len(folderCountMap))
	for name := range folderCountMap {
		names = append(names, name)
	}
	sort.Strings(names)

	folders := make([]folderCount, 0, len(names)+1)
	if hasUncategorized {
		folders = append(folders, folderCount{Folder: "", Count: uncategorizedCount})
	}
	for _, name := range names {
		folders = append(folders, folderCount{Folder: name, Count: folderCountMap[name]})
	}

	// 总数（同样按逻辑项计算）
	var totalAssets int64
	h.DB.Model(&model.Asset{}).Count(&totalAssets)
	var totalLivePacks int64
	h.DB.Model(&model.LiveAssetPack{}).Count(&totalLivePacks)
	var totalLiveAssets int64
	h.DB.Raw(`
		SELECT COUNT(DISTINCT id) FROM assets
		WHERE id IN (
			SELECT image_asset_id FROM live_asset_packs WHERE image_asset_id IS NOT NULL
			UNION
			SELECT video_asset_id FROM live_asset_packs WHERE video_asset_id IS NOT NULL
		)
	`).Scan(&totalLiveAssets)
	total := totalAssets - totalLiveAssets + totalLivePacks

	response.Success(c, gin.H{
		"folders": folders,
		"total":   total,
	})
}

// AssetFolderCreate 新建分类（允许空分类，无需先上传文件）
func (h *AdminHandler) AssetFolderCreate(c *gin.Context) {
	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	name := strings.TrimSpace(req.Name)
	if name == "" {
		response.BadRequest(c, 400, "分类名称不能为空")
		return
	}

	if err := h.DB.FirstOrCreate(&model.AssetFolder{}, model.AssetFolder{Name: name}).Error; err != nil {
		response.ServerError(c, "创建分类失败")
		return
	}

	response.Success(c, gin.H{
		"folder": name,
		"count":  0,
	})
}

// AssetFolderRename 重命名分类
func (h *AdminHandler) AssetFolderRename(c *gin.Context) {
	var req struct {
		OldName string `json:"old_name" binding:"required"`
		NewName string `json:"new_name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	oldName := strings.TrimSpace(req.OldName)
	newName := strings.TrimSpace(req.NewName)
	if oldName == "" || newName == "" {
		response.BadRequest(c, 400, "分类名称不能为空")
		return
	}
	if oldName == newName {
		response.SuccessMessage(c, "重命名成功")
		return
	}

	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.Asset{}).Where("folder = ?", oldName).Update("folder", newName).Error; err != nil {
			return err
		}
		if err := tx.Model(&model.LiveAssetPack{}).Where("folder = ?", oldName).Update("folder", newName).Error; err != nil {
			return err
		}
		if err := tx.FirstOrCreate(&model.AssetFolder{}, model.AssetFolder{Name: newName}).Error; err != nil {
			return err
		}
		if err := tx.Where("name = ?", oldName).Delete(&model.AssetFolder{}).Error; err != nil {
			return err
		}
		return nil
	}); err != nil {
		response.ServerError(c, "重命名失败")
		return
	}

	response.SuccessMessage(c, "重命名成功")
}

// AssetFolderDelete 删除分类（文件移到未分类）
func (h *AdminHandler) AssetFolderDelete(c *gin.Context) {
	var req struct {
		Folder string `json:"folder" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	folder := strings.TrimSpace(req.Folder)
	if folder == "" {
		response.BadRequest(c, 400, "分类名称不能为空")
		return
	}

	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.Asset{}).Where("folder = ?", folder).Update("folder", "").Error; err != nil {
			return err
		}
		if err := tx.Model(&model.LiveAssetPack{}).Where("folder = ?", folder).Update("folder", "").Error; err != nil {
			return err
		}
		if err := tx.Where("name = ?", folder).Delete(&model.AssetFolder{}).Error; err != nil {
			return err
		}
		return nil
	}); err != nil {
		response.ServerError(c, "删除分类失败")
		return
	}

	response.SuccessMessage(c, "分类已删除")
}

// AssetFolderBatchUpdate 批量修改素材/Live套件分类
func (h *AdminHandler) AssetFolderBatchUpdate(c *gin.Context) {
	var req struct {
		AssetIDs    []uint `json:"asset_ids"`
		LivePackIDs []uint `json:"live_pack_ids"`
		Folder      string `json:"folder"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	assetIDSet := make(map[uint]struct{}, len(req.AssetIDs))
	assetIDs := make([]uint, 0, len(req.AssetIDs))
	for _, id := range req.AssetIDs {
		if id == 0 {
			continue
		}
		if _, exists := assetIDSet[id]; exists {
			continue
		}
		assetIDSet[id] = struct{}{}
		assetIDs = append(assetIDs, id)
	}

	livePackIDSet := make(map[uint]struct{}, len(req.LivePackIDs))
	livePackIDs := make([]uint, 0, len(req.LivePackIDs))
	for _, id := range req.LivePackIDs {
		if id == 0 {
			continue
		}
		if _, exists := livePackIDSet[id]; exists {
			continue
		}
		livePackIDSet[id] = struct{}{}
		livePackIDs = append(livePackIDs, id)
	}

	if len(assetIDs) == 0 && len(livePackIDs) == 0 {
		response.BadRequest(c, 400, "请至少选择一个素材或套件")
		return
	}

	folder := strings.TrimSpace(req.Folder)

	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		// 先处理素材
		if len(assetIDs) > 0 {
			if err := tx.Model(&model.Asset{}).Where("id IN ?", assetIDs).Update("folder", folder).Error; err != nil {
				return err
			}
			if err := tx.Model(&model.LiveAssetPack{}).
				Where("image_asset_id IN ? OR video_asset_id IN ?", assetIDs, assetIDs).
				Update("folder", folder).Error; err != nil {
				return err
			}
		}

		// 再处理 Live 套件
		if len(livePackIDs) > 0 {
			if err := tx.Model(&model.LiveAssetPack{}).Where("id IN ?", livePackIDs).Update("folder", folder).Error; err != nil {
				return err
			}

			var packs []model.LiveAssetPack
			if err := tx.Select("id, image_asset_id, video_asset_id").
				Where("id IN ?", livePackIDs).
				Find(&packs).Error; err != nil {
				return err
			}

			relatedAssetSet := map[uint]struct{}{}
			for _, p := range packs {
				if p.ImageAssetID != nil && *p.ImageAssetID > 0 {
					relatedAssetSet[*p.ImageAssetID] = struct{}{}
				}
				if p.VideoAssetID != nil && *p.VideoAssetID > 0 {
					relatedAssetSet[*p.VideoAssetID] = struct{}{}
				}
			}
			if len(relatedAssetSet) > 0 {
				relatedAssetIDs := make([]uint, 0, len(relatedAssetSet))
				for id := range relatedAssetSet {
					relatedAssetIDs = append(relatedAssetIDs, id)
				}
				if err := tx.Model(&model.Asset{}).Where("id IN ?", relatedAssetIDs).Update("folder", folder).Error; err != nil {
					return err
				}
			}
		}

		if folder != "" {
			if err := tx.FirstOrCreate(&model.AssetFolder{}, model.AssetFolder{Name: folder}).Error; err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		response.ServerError(c, "批量修改分类失败")
		return
	}

	response.Success(c, gin.H{
		"folder":          folder,
		"asset_count":     len(assetIDs),
		"live_pack_count": len(livePackIDs),
	})
}

// deleteAssetFile 删除素材文件（兼容本地和 COS）
func (h *AdminHandler) deleteAssetFile(fileURL string) {
	if fileURL == "" {
		return
	}
	if strings.HasPrefix(fileURL, "/static/") {
		os.Remove(filepath.Join(".", strings.TrimPrefix(fileURL, "/")))
	} else if h.Store != nil && h.Store.Enabled() {
		h.Store.Delete(fileURL)
	}
}

func (h *AdminHandler) AssetDelete(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var asset model.Asset
	if err := h.DB.First(&asset, id).Error; err != nil {
		response.NotFound(c, "文件不存在")
		return
	}

	// 删除存储文件
	h.deleteAssetFile(asset.URL)
	h.deleteAssetFile(asset.PreviewURL)

	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.LiveAssetPack{}).
			Where("image_asset_id = ?", asset.ID).
			Updates(map[string]interface{}{
				"image_asset_id": nil,
				"status":         "incomplete",
			}).Error; err != nil {
			return err
		}
		if err := tx.Model(&model.LiveAssetPack{}).
			Where("video_asset_id = ?", asset.ID).
			Updates(map[string]interface{}{
				"video_asset_id": nil,
				"status":         "incomplete",
			}).Error; err != nil {
			return err
		}
		if err := tx.Where("image_asset_id IS NULL AND video_asset_id IS NULL").
			Delete(&model.LiveAssetPack{}).Error; err != nil {
			return err
		}
		if err := tx.Delete(&asset).Error; err != nil {
			return err
		}
		return nil
	}); err != nil {
		response.ServerError(c, "删除失败")
		return
	}

	response.SuccessMessage(c, "删除成功")
}

// AssetBatchDelete 批量删除素材和 Live 套件
func (h *AdminHandler) AssetBatchDelete(c *gin.Context) {
	var req struct {
		AssetIDs    []uint `json:"asset_ids"`
		LivePackIDs []uint `json:"live_pack_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	// 去重
	assetIDSet := make(map[uint]struct{}, len(req.AssetIDs))
	assetIDs := make([]uint, 0, len(req.AssetIDs))
	for _, id := range req.AssetIDs {
		if id == 0 {
			continue
		}
		if _, exists := assetIDSet[id]; exists {
			continue
		}
		assetIDSet[id] = struct{}{}
		assetIDs = append(assetIDs, id)
	}

	livePackIDSet := make(map[uint]struct{}, len(req.LivePackIDs))
	livePackIDs := make([]uint, 0, len(req.LivePackIDs))
	for _, id := range req.LivePackIDs {
		if id == 0 {
			continue
		}
		if _, exists := livePackIDSet[id]; exists {
			continue
		}
		livePackIDSet[id] = struct{}{}
		livePackIDs = append(livePackIDs, id)
	}

	if len(assetIDs) == 0 && len(livePackIDs) == 0 {
		response.BadRequest(c, 400, "请至少选择一个素材或套件")
		return
	}

	// 收集所有需要删除的 asset（包括 live pack 关联的）
	allDeleteAssetIDs := make(map[uint]struct{})
	for _, id := range assetIDs {
		allDeleteAssetIDs[id] = struct{}{}
	}

	// 查找 live pack 关联的 asset
	if len(livePackIDs) > 0 {
		var packs []model.LiveAssetPack
		h.DB.Select("id, image_asset_id, video_asset_id").
			Where("id IN ?", livePackIDs).
			Find(&packs)
		for _, p := range packs {
			if p.ImageAssetID != nil && *p.ImageAssetID > 0 {
				allDeleteAssetIDs[*p.ImageAssetID] = struct{}{}
			}
			if p.VideoAssetID != nil && *p.VideoAssetID > 0 {
				allDeleteAssetIDs[*p.VideoAssetID] = struct{}{}
			}
		}
	}

	// 查出所有待删 asset 的文件路径
	finalAssetIDs := make([]uint, 0, len(allDeleteAssetIDs))
	for id := range allDeleteAssetIDs {
		finalAssetIDs = append(finalAssetIDs, id)
	}

	var assets []model.Asset
	if len(finalAssetIDs) > 0 {
		h.DB.Select("id, url, preview_url").Where("id IN ?", finalAssetIDs).Find(&assets)
	}

	// 删除存储文件
	for _, asset := range assets {
		h.deleteAssetFile(asset.URL)
		h.deleteAssetFile(asset.PreviewURL)
	}

	// 事务：清理 DB 记录
	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		if len(finalAssetIDs) > 0 {
			// 解除其他 live pack 对这些 asset 的引用
			if err := tx.Model(&model.LiveAssetPack{}).
				Where("image_asset_id IN ?", finalAssetIDs).
				Updates(map[string]interface{}{"image_asset_id": nil, "status": "incomplete"}).
				Error; err != nil {
				return err
			}
			if err := tx.Model(&model.LiveAssetPack{}).
				Where("video_asset_id IN ?", finalAssetIDs).
				Updates(map[string]interface{}{"video_asset_id": nil, "status": "incomplete"}).
				Error; err != nil {
				return err
			}
		}

		// 删除指定的 live pack
		if len(livePackIDs) > 0 {
			if err := tx.Where("id IN ?", livePackIDs).Delete(&model.LiveAssetPack{}).Error; err != nil {
				return err
			}
		}

		// 清理双端都为空的 live pack
		if err := tx.Where("image_asset_id IS NULL AND video_asset_id IS NULL").
			Delete(&model.LiveAssetPack{}).Error; err != nil {
			return err
		}

		// 删除 asset 记录
		if len(finalAssetIDs) > 0 {
			if err := tx.Where("id IN ?", finalAssetIDs).Delete(&model.Asset{}).Error; err != nil {
				return err
			}
		}

		return nil
	}); err != nil {
		response.ServerError(c, "批量删除失败")
		return
	}

	response.Success(c, gin.H{
		"asset_count":     len(finalAssetIDs),
		"live_pack_count": len(livePackIDs),
	})
}

func resolveLiveRole(rawRole, ext string) string {
	role := strings.ToLower(strings.TrimSpace(rawRole))
	normalizedExt := strings.ToLower(strings.TrimSpace(ext))
	if role != "" {
		switch role {
		case "image", "static", "photo":
			// 有明确 live_role 时，接受任何图片格式（JPG/PNG/HEIC 等）
			if isImageExt(normalizedExt) {
				return "image"
			}
			return ""
		case "video", "mov", "motion":
			if normalizedExt == ".mov" {
				return "video"
			}
			return ""
		default:
			return ""
		}
	}
	// 无 hint 时仅自动识别 HEIC/MOV，避免普通 JPG 被误判
	if isHEICExt(normalizedExt) {
		return "image"
	}
	if normalizedExt == ".mov" {
		return "video"
	}
	return ""
}

func liveRoleFromAssetURL(url string) string {
	cleanURL := url
	if idx := strings.Index(cleanURL, "?"); idx >= 0 {
		cleanURL = cleanURL[:idx]
	}
	ext := strings.ToLower(filepath.Ext(cleanURL))
	// HEIC/HEIF → image, JPG/JPEG → image, MOV → video
	if isHEICExt(ext) || ext == ".jpg" || ext == ".jpeg" {
		return "image"
	}
	if ext == ".mov" {
		return "video"
	}
	return ""
}

func isJPGURL(url string) bool {
	clean := url
	if idx := strings.Index(clean, "?"); idx >= 0 {
		clean = clean[:idx]
	}
	ext := strings.ToLower(filepath.Ext(clean))
	return ext == ".jpg" || ext == ".jpeg"
}

func livePackStatus(imageAssetID, videoAssetID *uint) string {
	if imageAssetID != nil && videoAssetID != nil {
		return "complete"
	}
	return "incomplete"
}

func liveBaseNameFromAsset(asset model.Asset) string {
	name := strings.TrimSpace(asset.OriginalName)
	if name == "" {
		name = strings.TrimSpace(asset.Filename)
	}
	if name == "" {
		cleanURL := asset.URL
		if idx := strings.Index(cleanURL, "?"); idx >= 0 {
			cleanURL = cleanURL[:idx]
		}
		name = path.Base(cleanURL)
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return ""
	}
	ext := filepath.Ext(name)
	if ext != "" {
		name = strings.TrimSuffix(name, ext)
	}
	return normalizeLiveBaseName(name)
}

func normalizeLiveBaseName(raw string) string {
	name := strings.TrimSpace(strings.ToLower(raw))
	if name == "" {
		return ""
	}

	name = strings.ReplaceAll(name, "（", "(")
	name = strings.ReplaceAll(name, "）", ")")

	if matched := liveImgEditedNameRe.FindStringSubmatch(name); len(matched) == 2 {
		name = "img_" + matched[1]
	}

	name = liveCopySuffixRe.ReplaceAllString(name, "")
	name = strings.TrimSpace(name)
	name = strings.TrimSuffix(name, " copy")
	name = strings.TrimSuffix(name, " 副本")
	name = strings.TrimSpace(name)
	name = liveSpaceNumSuffix.ReplaceAllString(name, "")
	name = strings.TrimSpace(name)

	return name
}

func trimLiveRoleSuffix(name, liveRole string) string {
	if name == "" {
		return ""
	}
	suffixes := []string{}
	switch liveRole {
	case "image":
		suffixes = []string{
			"_image", "-image", " image",
			"_photo", "-photo", " photo",
			"_static", "-static", " static",
			"_heic", "-heic", " heic",
			"_heif", "-heif", " heif",
		}
	case "video":
		suffixes = []string{
			"_video", "-video", " video",
			"_mov", "-mov", " mov",
			"_motion", "-motion", " motion",
		}
	default:
		return name
	}

	result := name
	for _, suffix := range suffixes {
		if strings.HasSuffix(result, suffix) {
			candidate := strings.TrimSuffix(result, suffix)
			candidate = strings.TrimSpace(strings.TrimRight(candidate, "_- "))
			if candidate != "" {
				result = candidate
			}
			break
		}
	}
	return result
}

func canonicalLiveBaseName(raw string) string {
	name := normalizeLiveBaseName(raw)
	name = trimLiveRoleSuffix(name, "image")
	name = trimLiveRoleSuffix(name, "video")
	return strings.TrimSpace(name)
}

func (h *AdminHandler) attachAssetToLivePack(asset model.Asset, liveRole string) (*model.LiveAssetPack, error) {
	baseName := liveBaseNameFromAsset(asset)
	baseName = trimLiveRoleSuffix(baseName, liveRole)
	if baseName == "" {
		return nil, fmt.Errorf("empty live base name")
	}
	folder := strings.TrimSpace(asset.Folder)
	var pack model.LiveAssetPack

	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		var exists model.LiveAssetPack
		if err := tx.Where("image_asset_id = ? OR video_asset_id = ?", asset.ID, asset.ID).First(&exists).Error; err == nil {
			pack = exists
			return nil
		}

		query := tx.Where("folder = ? AND base_name = ? AND status = ?", folder, baseName, "incomplete")
		if liveRole == "image" {
			query = query.Where("image_asset_id IS NULL")
		} else {
			query = query.Where("video_asset_id IS NULL")
		}

		if err := query.Order("created_at ASC, id ASC").First(&pack).Error; err != nil {
			if err != gorm.ErrRecordNotFound {
				return err
			}
			newPack := model.LiveAssetPack{
				Folder:   folder,
				BaseName: baseName,
				Status:   "incomplete",
			}
			if liveRole == "image" {
				id := asset.ID
				newPack.ImageAssetID = &id
			} else {
				id := asset.ID
				newPack.VideoAssetID = &id
			}
			newPack.Status = livePackStatus(newPack.ImageAssetID, newPack.VideoAssetID)
			if err := tx.Create(&newPack).Error; err != nil {
				return err
			}
			pack = newPack
			return nil
		}

		updates := map[string]interface{}{}
		imageAssetID := pack.ImageAssetID
		videoAssetID := pack.VideoAssetID

		if liveRole == "image" {
			updates["image_asset_id"] = asset.ID
			id := asset.ID
			imageAssetID = &id
		} else {
			updates["video_asset_id"] = asset.ID
			id := asset.ID
			videoAssetID = &id
		}
		updates["status"] = livePackStatus(imageAssetID, videoAssetID)

		if err := tx.Model(&model.LiveAssetPack{}).Where("id = ?", pack.ID).Updates(updates).Error; err != nil {
			return err
		}

		pack.ImageAssetID = imageAssetID
		pack.VideoAssetID = videoAssetID
		pack.Status = updates["status"].(string)
		return nil
	}); err != nil {
		return nil, err
	}

	return &pack, nil
}

func (h *AdminHandler) ensureLegacyLivePacks() error {
	var packs []model.LiveAssetPack
	if err := h.DB.Select("id, folder, base_name, image_asset_id, video_asset_id, created_at").
		Order("created_at ASC, id ASC").
		Find(&packs).Error; err != nil {
		return err
	}

	// 修复历史数据：统一 base_name（例如 live_image/live_video -> live）
	for i := range packs {
		canonical := canonicalLiveBaseName(packs[i].BaseName)
		if canonical == "" || canonical == packs[i].BaseName {
			continue
		}
		if err := h.DB.Model(&model.LiveAssetPack{}).
			Where("id = ?", packs[i].ID).
			Update("base_name", canonical).Error; err != nil {
			return err
		}
		packs[i].BaseName = canonical
	}

	// 合并同 folder + base_name 的重复半成品套件。
	// 注意：如果 keeper 和 duplicate 都已 complete，说明是不同 Live（只是碰巧同名），
	// 不应合并，否则会丢失数据。
	type key struct {
		folder   string
		baseName string
	}
	keeperByKey := map[key]model.LiveAssetPack{}
	deleteIDs := make([]uint, 0)
	for _, p := range packs {
		k := key{folder: strings.TrimSpace(p.Folder), baseName: strings.TrimSpace(p.BaseName)}
		if k.baseName == "" {
			continue
		}
		keeper, exists := keeperByKey[k]
		if !exists {
			keeperByKey[k] = p
			continue
		}

		keeperComplete := keeper.ImageAssetID != nil && keeper.VideoAssetID != nil
		duplicateComplete := p.ImageAssetID != nil && p.VideoAssetID != nil
		if keeperComplete && duplicateComplete {
			// 两个都完整，是不同 Live Photo，不合并
			continue
		}

		updates := map[string]interface{}{}
		imageAssetID := keeper.ImageAssetID
		videoAssetID := keeper.VideoAssetID
		if imageAssetID == nil && p.ImageAssetID != nil {
			updates["image_asset_id"] = *p.ImageAssetID
			id := *p.ImageAssetID
			imageAssetID = &id
		}
		if videoAssetID == nil && p.VideoAssetID != nil {
			updates["video_asset_id"] = *p.VideoAssetID
			id := *p.VideoAssetID
			videoAssetID = &id
		}
		if len(updates) > 0 {
			updates["status"] = livePackStatus(imageAssetID, videoAssetID)
			if err := h.DB.Model(&model.LiveAssetPack{}).Where("id = ?", keeper.ID).Updates(updates).Error; err != nil {
				return err
			}
			keeper.ImageAssetID = imageAssetID
			keeper.VideoAssetID = videoAssetID
			keeper.Status = updates["status"].(string)
			keeperByKey[k] = keeper
		}
		deleteIDs = append(deleteIDs, p.ID)
	}
	if len(deleteIDs) > 0 {
		if err := h.DB.Where("id IN ?", deleteIDs).Delete(&model.LiveAssetPack{}).Error; err != nil {
			return err
		}
	}

	// 重新读取，确保后续 linked 集合基于最新套件。
	packs = nil
	if err := h.DB.Select("id, image_asset_id, video_asset_id").Find(&packs).Error; err != nil {
		return err
	}

	linked := make(map[uint]struct{}, len(packs)*2)
	for _, p := range packs {
		if p.ImageAssetID != nil {
			linked[*p.ImageAssetID] = struct{}{}
		}
		if p.VideoAssetID != nil {
			linked[*p.VideoAssetID] = struct{}{}
		}
	}

	// 清理：删除因 JPG 被误判而创建的半成品 LiveAssetPack（仅有 image，无 video，且 image 是 JPG）
	var jpgOnlyPacks []model.LiveAssetPack
	if err := h.DB.Where("status = ? AND video_asset_id IS NULL AND image_asset_id IS NOT NULL", "incomplete").
		Find(&jpgOnlyPacks).Error; err != nil {
		return err
	}
	jpgCleanIDs := make([]uint, 0)
	for _, p := range jpgOnlyPacks {
		if p.ImageAssetID == nil {
			continue
		}
		var imgAsset model.Asset
		if err := h.DB.Select("id, url").First(&imgAsset, *p.ImageAssetID).Error; err != nil {
			continue
		}
		cleanURL := imgAsset.URL
		if idx := strings.Index(cleanURL, "?"); idx >= 0 {
			cleanURL = cleanURL[:idx]
		}
		ext := strings.ToLower(filepath.Ext(cleanURL))
		if ext == ".jpg" || ext == ".jpeg" {
			jpgCleanIDs = append(jpgCleanIDs, p.ID)
		}
	}
	if len(jpgCleanIDs) > 0 {
		if err := h.DB.Where("id IN ?", jpgCleanIDs).Delete(&model.LiveAssetPack{}).Error; err != nil {
			return err
		}
		// 重新构建 linked 集合
		packs = nil
		if err := h.DB.Select("id, image_asset_id, video_asset_id").Find(&packs).Error; err != nil {
			return err
		}
		linked = make(map[uint]struct{}, len(packs)*2)
		for _, p := range packs {
			if p.ImageAssetID != nil {
				linked[*p.ImageAssetID] = struct{}{}
			}
			if p.VideoAssetID != nil {
				linked[*p.VideoAssetID] = struct{}{}
			}
		}
	}

	// 自动扫描：HEIC/HEIF + JPG/JPEG + MOV
	var assets []model.Asset
	if err := h.DB.Where(`
		lower(coalesce(url, '')) LIKE '%.heic' OR
		lower(coalesce(url, '')) LIKE '%.heif' OR
		lower(coalesce(url, '')) LIKE '%.jpg' OR
		lower(coalesce(url, '')) LIKE '%.jpeg' OR
		lower(coalesce(url, '')) LIKE '%.mov'
	`).Order("created_at ASC, id ASC").Find(&assets).Error; err != nil {
		return err
	}

	// 第一阶段：处理 HEIC/HEIF + MOV（可自由创建/补全 LiveAssetPack）
	for _, asset := range assets {
		if _, exists := linked[asset.ID]; exists {
			continue
		}
		if isJPGURL(asset.URL) {
			continue // JPG 留到第二阶段
		}
		liveRole := liveRoleFromAssetURL(asset.URL)
		if liveRole == "" {
			continue
		}
		if _, err := h.attachAssetToLivePack(asset, liveRole); err == nil {
			linked[asset.ID] = struct{}{}
		}
	}

	// 第二阶段：处理 JPG/JPEG（只补全已有 incomplete pack，不创建新 pack）
	// 这样独立 JPG 不会被误划入 Live，而 JPG+MOV 的 Live Photo 能正确配对
	for _, asset := range assets {
		if _, exists := linked[asset.ID]; exists {
			continue
		}
		if !isJPGURL(asset.URL) {
			continue
		}
		baseName := liveBaseNameFromAsset(asset)
		baseName = trimLiveRoleSuffix(baseName, "image")
		if baseName == "" {
			continue
		}
		folder := strings.TrimSpace(asset.Folder)
		// 查找是否存在待配对的 incomplete pack（有 video 缺 image）
		var existingPack model.LiveAssetPack
		if err := h.DB.Where("folder = ? AND base_name = ? AND status = ? AND image_asset_id IS NULL AND video_asset_id IS NOT NULL",
			folder, baseName, "incomplete").First(&existingPack).Error; err != nil {
			continue // 没有对应的 MOV pack，这是独立 JPG，跳过
		}
		// 找到了待配对的 pack，补全它
		if _, err := h.attachAssetToLivePack(asset, "image"); err == nil {
			linked[asset.ID] = struct{}{}
		}
	}
	return nil
}

func isHEICExt(ext string) bool {
	ext = strings.ToLower(strings.TrimSpace(ext))
	return ext == ".heic" || ext == ".heif"
}

func isHEICURL(url string) bool {
	cleanURL := url
	if idx := strings.Index(cleanURL, "?"); idx >= 0 {
		cleanURL = cleanURL[:idx]
	}
	ext := strings.ToLower(filepath.Ext(cleanURL))
	return isHEICExt(ext)
}

// ensureHEICPreview 为 HEIC 文件生成 JPG 预览图，返回预览 URL。
func ensureHEICPreview(sourceURL string) (string, error) {
	if !isHEICURL(sourceURL) {
		return "", fmt.Errorf("not heic")
	}

	sourcePath := filepath.Join(".", strings.TrimPrefix(sourceURL, "/"))
	if _, err := os.Stat(sourcePath); err != nil {
		return "", err
	}

	sourceExt := filepath.Ext(sourcePath)
	baseName := strings.TrimSuffix(filepath.Base(sourcePath), sourceExt)
	previewFilename := baseName + "_preview.jpg"
	previewPath := filepath.Join(filepath.Dir(sourcePath), previewFilename)
	previewURL := path.Join(path.Dir(sourceURL), previewFilename)

	if _, err := os.Stat(previewPath); err == nil {
		return previewURL, nil
	}

	// 优先使用 macOS 原生 sips
	if _, err := exec.LookPath("sips"); err == nil {
		cmd := exec.Command("sips", "-s", "format", "jpeg", sourcePath, "--out", previewPath)
		if err := cmd.Run(); err == nil {
			return previewURL, nil
		}
	}

	// 兜底：尝试 ffmpeg
	if _, err := exec.LookPath("ffmpeg"); err == nil {
		cmd := exec.Command("ffmpeg", "-y", "-i", sourcePath, "-frames:v", "1", previewPath)
		if err := cmd.Run(); err == nil {
			return previewURL, nil
		}
	}

	return "", fmt.Errorf("generate heic preview failed")
}

// ensureMobileVideoVariant 为视频生成移动端 MP4（_mobile.mp4），用于客户端下载优先加速。
func ensureMobileVideoVariant(sourceURL string) (string, error) {
	sourcePath := filepath.Join(".", strings.TrimPrefix(sourceURL, "/"))
	if _, err := os.Stat(sourcePath); err != nil {
		return "", err
	}

	ext := strings.ToLower(filepath.Ext(sourcePath))
	if ext == ".mp4" {
		return sourceURL, nil
	}
	switch ext {
	case ".mov", ".m4v", ".avi", ".mkv", ".webm":
	default:
		return "", fmt.Errorf("not supported video ext")
	}

	baseName := strings.TrimSuffix(filepath.Base(sourcePath), ext)
	mobileFilename := baseName + "_mobile.mp4"
	mobilePath := filepath.Join(filepath.Dir(sourcePath), mobileFilename)
	mobileURL := path.Join(path.Dir(sourceURL), mobileFilename)

	if _, err := os.Stat(mobilePath); err == nil {
		return mobileURL, nil
	}

	if _, err := exec.LookPath("ffmpeg"); err != nil {
		return "", err
	}

	cmd := exec.Command(
		"ffmpeg", "-y", "-i", sourcePath,
		"-movflags", "+faststart",
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "24",
		"-pix_fmt", "yuv420p",
		"-c:a", "aac", "-b:a", "128k",
		mobilePath,
	)
	if err := cmd.Run(); err != nil {
		return "", err
	}
	if _, err := os.Stat(mobilePath); err != nil {
		return "", err
	}
	return mobileURL, nil
}

func (h *AdminHandler) ConfigUpdate(c *gin.Context) {
	var req struct {
		Key   string `json:"key" binding:"required"`
		Value string `json:"value" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	h.DB.Where("key = ?", req.Key).Assign(model.SystemConfig{
		Key:   req.Key,
		Value: req.Value,
	}).FirstOrCreate(&model.SystemConfig{})

	response.SuccessMessage(c, "更新成功")
}
