package handler

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
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
	myjwt "github.com/xiaoyanquan/server/pkg/jwt"
	"github.com/xiaoyanquan/server/pkg/response"
)

type AdminHandler struct {
	DB  *gorm.DB
	Cfg *config.Config
}

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

// InitAdmin 开发环境自动创建默认管理员（GET /api/admin/init）
func (h *AdminHandler) InitAdmin(c *gin.Context) {
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
		UserCount     int64 `json:"user_count"`
		MaterialCount int64 `json:"material_count"`
		MomentCount   int64 `json:"moment_count"`
		OrderCount    int64 `json:"order_count"`
		MemberCount   int64 `json:"member_count"`
		QuestionCount int64 `json:"question_count"`
		TodayNewUsers int64 `json:"today_new_users"`
		TodayDownloads int64 `json:"today_downloads"`
	}

	today := time.Now().Truncate(24 * time.Hour)

	h.DB.Model(&model.User{}).Count(&stats.UserCount)
	h.DB.Model(&model.Material{}).Count(&stats.MaterialCount)
	h.DB.Model(&model.Moment{}).Count(&stats.MomentCount)
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
	query.Preload("Category").Preload("GenderCategory").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&materials)

	response.SuccessPage(c, materials, total, page, pageSize)
}

func (h *AdminHandler) MaterialCreate(c *gin.Context) {
	var req struct {
		Title         string   `json:"title" binding:"required"`
		Description   string   `json:"description"`
		Type             string   `json:"type" binding:"required"`
		CategoryID        uint     `json:"category_id"`
		GenderCategoryID  uint     `json:"gender_category_id"`
		Tags             []string `json:"tags"`
		Width         int      `json:"width"`
		Height        int      `json:"height"`
		Duration      float64  `json:"duration"`
		FileSize      int64    `json:"file_size"`
		OriginalURLs  []string `json:"original_urls"`
		ThumbnailURL  string   `json:"thumbnail_url"`
		WatermarkURL  string   `json:"watermark_url"`
		PreviewMovURL string   `json:"preview_mov_url"`
		Status        string   `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	material := model.Material{
		Title:         req.Title,
		Description:   req.Description,
		Type:          req.Type,
		Tags:          req.Tags,
		Width:         req.Width,
		Height:        req.Height,
		Duration:      req.Duration,
		FileSize:      req.FileSize,
		OriginalURLs:  func() model.JSON { b, _ := json.Marshal(req.OriginalURLs); return model.JSON(b) }(),
		ThumbnailURL:  req.ThumbnailURL,
		WatermarkURL:  req.WatermarkURL,
		PreviewMovURL: req.PreviewMovURL,
		Status:        req.Status,
	}
	if req.CategoryID > 0 {
		material.CategoryID = &req.CategoryID
	}
	if req.GenderCategoryID > 0 {
		material.GenderCategoryID = &req.GenderCategoryID
	}
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

	// Normalize gender_category_id: 0 -> NULL, number -> uint
	if gidRaw, ok := req["gender_category_id"]; ok {
		switch v := gidRaw.(type) {
		case float64:
			if v <= 0 {
				req["gender_category_id"] = nil
			} else {
				req["gender_category_id"] = uint(v)
			}
		case int:
			if v <= 0 {
				req["gender_category_id"] = nil
			} else {
				req["gender_category_id"] = uint(v)
			}
		case int64:
			if v <= 0 {
				req["gender_category_id"] = nil
			} else {
				req["gender_category_id"] = uint(v)
			}
		case uint:
			if v == 0 {
				req["gender_category_id"] = nil
			}
		}
	}

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
	h.DB.Preload("Category").Preload("GenderCategory").First(&material, id)
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

// ==================== 动态管理 ====================

func (h *AdminHandler) MomentList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	status := c.Query("status")

	query := h.DB.Model(&model.Moment{})
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	query.Count(&total)

	var moments []model.Moment
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&moments)

	response.SuccessPage(c, moments, total, page, pageSize)
}

func (h *AdminHandler) MomentCreate(c *gin.Context) {
	var req struct {
		ContentText string          `json:"content_text"`
		MediaType   string          `json:"media_type"`
		MediaURLs   json.RawMessage `json:"media_urls"`
		Status      string          `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	adminID := middleware.GetAdminID(c)
	moment := model.Moment{
		AdminID:     adminID,
		ContentText: req.ContentText,
		MediaType:   req.MediaType,
		MediaURLs:   model.JSON(req.MediaURLs),
		Status:      req.Status,
	}
	if moment.Status == "" {
		moment.Status = "draft"
	}

	if err := h.DB.Create(&moment).Error; err != nil {
		response.ServerError(c, "创建失败")
		return
	}
	response.Success(c, moment)
}

func (h *AdminHandler) MomentUpdate(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var moment model.Moment
	if err := h.DB.First(&moment, id).Error; err != nil {
		response.NotFound(c, "动态不存在")
		return
	}

	var req struct {
		ContentText *string          `json:"content_text"`
		MediaType   *string          `json:"media_type"`
		MediaURLs   *json.RawMessage `json:"media_urls"`
		Status      *string          `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	if req.ContentText != nil {
		moment.ContentText = *req.ContentText
	}
	if req.MediaType != nil {
		moment.MediaType = *req.MediaType
	}
	if req.MediaURLs != nil {
		moment.MediaURLs = model.JSON(*req.MediaURLs)
	}
	if req.Status != nil {
		moment.Status = *req.Status
	}

	h.DB.Save(&moment)
	response.Success(c, moment)
}

func (h *AdminHandler) MomentDelete(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.DB.Delete(&model.Moment{}, id).Error; err != nil {
		response.ServerError(c, "删除失败")
		return
	}
	response.SuccessMessage(c, "删除成功")
}

func (h *AdminHandler) MomentBatchDelete(c *gin.Context) {
	var req struct {
		IDs []uint `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	h.DB.Where("id IN ?", req.IDs).Delete(&model.Moment{})
	response.SuccessMessage(c, "批量删除成功")
}

func (h *AdminHandler) MomentBatchStatus(c *gin.Context) {
	var req struct {
		IDs    []uint `json:"ids" binding:"required"`
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	h.DB.Model(&model.Moment{}).Where("id IN ?", req.IDs).Update("status", req.Status)
	response.SuccessMessage(c, "批量更新成功")
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

func (h *AdminHandler) UserList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	memberType := c.Query("member_type")

	query := h.DB.Model(&model.User{})
	if keyword != "" {
		query = query.Where("phone LIKE ? OR nickname LIKE ?", "%"+keyword+"%", "%"+keyword+"%")
	}
	if memberType != "" {
		query = query.Where("member_type = ?", memberType)
	}

	var total int64
	query.Count(&total)

	var users []model.User
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&users)

	response.SuccessPage(c, users, total, page, pageSize)
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

	response.Success(c, gin.H{
		"user":           user,
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

	folder := c.PostForm("folder") // 分类文件夹

	// 检查文件类型
	ext := strings.ToLower(filepath.Ext(file.Filename))
	fileType := "image"
	switch ext {
	case ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp":
		fileType = "image"
	case ".mp4", ".mov", ".avi", ".mkv":
		fileType = "video"
	default:
		response.BadRequest(c, 400, "不支持的文件格式")
		return
	}

	// 生成唯一文件名
	newFilename := uuid.New().String() + ext
	dateDir := time.Now().Format("2006/01")
	uploadDir := filepath.Join("static", "uploads", dateDir)
	os.MkdirAll(uploadDir, 0755)

	dstPath := filepath.Join(uploadDir, newFilename)
	if err := c.SaveUploadedFile(file, dstPath); err != nil {
		response.ServerError(c, "文件保存失败")
		return
	}

	// 构建 URL
	url := fmt.Sprintf("/static/uploads/%s/%s", dateDir, newFilename)

	asset := model.Asset{
		Filename:     newFilename,
		OriginalName: file.Filename,
		URL:          url,
		FileType:     fileType,
		Folder:       folder,
		FileSize:     file.Size,
	}
	if err := h.DB.Create(&asset).Error; err != nil {
		response.ServerError(c, "保存记录失败")
		return
	}
	response.Success(c, asset)
}

func (h *AdminHandler) AssetList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "40"))
	fileType := c.Query("file_type")
	folder := c.Query("folder")
	keyword := c.Query("keyword")

	query := h.DB.Model(&model.Asset{})
	if fileType != "" {
		query = query.Where("file_type = ?", fileType)
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

	response.SuccessPage(c, assets, total, page, pageSize)
}

// AssetFolders 获取所有分类列表
func (h *AdminHandler) AssetFolders(c *gin.Context) {
	var folders []struct {
		Folder string `json:"folder"`
		Count  int64  `json:"count"`
	}
	h.DB.Model(&model.Asset{}).
		Select("folder, count(*) as count").
		Group("folder").
		Order("folder ASC").
		Scan(&folders)

	// 总数
	var total int64
	h.DB.Model(&model.Asset{}).Count(&total)

	response.Success(c, gin.H{
		"folders": folders,
		"total":   total,
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
	h.DB.Model(&model.Asset{}).Where("folder = ?", req.OldName).Update("folder", req.NewName)
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
	h.DB.Model(&model.Asset{}).Where("folder = ?", req.Folder).Update("folder", "")
	response.SuccessMessage(c, "分类已删除")
}

func (h *AdminHandler) AssetDelete(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var asset model.Asset
	if err := h.DB.First(&asset, id).Error; err != nil {
		response.NotFound(c, "文件不存在")
		return
	}

	// 删除本地文件
	os.Remove(filepath.Join(".", asset.URL))

	h.DB.Delete(&asset)
	response.SuccessMessage(c, "删除成功")
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
