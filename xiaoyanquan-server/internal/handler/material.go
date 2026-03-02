package handler

import (
	"encoding/json"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

type MaterialHandler struct {
	DB *gorm.DB
}

// ==================== 响应结构 ====================

type MaterialListItem struct {
	ID            uint     `json:"id"`
	Title         string   `json:"title"`
	Type          string   `json:"type"`
	ThumbnailURL  string   `json:"thumbnail_url"`
	Width         int      `json:"width"`
	Height        int      `json:"height"`
	Duration      float64  `json:"duration,omitempty"`
	HotScore      float64  `json:"hot_score"`
	DownloadCount int      `json:"download_count"`
	FavoriteCount int      `json:"favorite_count"`
	Tags          []string `json:"tags"`
	IsFavorited   bool     `json:"is_favorited"`
}

type MaterialDetailResp struct {
	ID            uint     `json:"id"`
	Title         string   `json:"title"`
	Description   string   `json:"description"`
	Type          string   `json:"type"`
	CategoryID    *uint    `json:"category_id"`
	CategoryName  string   `json:"category_name"`
	Tags          []string `json:"tags"`
	Width         int      `json:"width"`
	Height        int      `json:"height"`
	Duration      float64  `json:"duration,omitempty"`
	FileSize      int64    `json:"file_size"`
	FileSizeText  string   `json:"file_size_text"`
	ThumbnailURL  string   `json:"thumbnail_url"`
	WatermarkURL  string   `json:"watermark_url"`
	PreviewMovURL string   `json:"preview_mov_url,omitempty"`
	HotScore      float64  `json:"hot_score"`
	DownloadCount int      `json:"download_count"`
	FavoriteCount int      `json:"favorite_count"`
	ViewCount     int      `json:"view_count"`
	IsFavorited   bool     `json:"is_favorited"`
	CreatedAt     string   `json:"created_at"`
}

// ==================== 列表 ====================

func (h *MaterialHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	categoryID, _ := strconv.Atoi(c.DefaultQuery("category_id", "0"))
	genderCategoryID, _ := strconv.Atoi(c.DefaultQuery("gender_category_id", "0"))
	materialType := c.DefaultQuery("type", "")
	sort := c.DefaultQuery("sort", "hot") // hot, latest, downloads

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 50 {
		pageSize = 20
	}

	query := h.DB.Model(&model.Material{}).Where("status = ?", "published")

	if categoryID > 0 {
		// 检查是否为一级分类（有子分类），若是则展开查询
		var childIDs []uint
		h.DB.Model(&model.Category{}).Where("parent_id = ?", categoryID).Pluck("id", &childIDs)
		if len(childIDs) > 0 {
			// 一级分类：查子分类下的所有素材
			query = query.Where("category_id IN ?", childIDs)
		} else {
			// 二级分类：直接筛选
			query = query.Where("category_id = ?", categoryID)
		}
	}
	if genderCategoryID > 0 {
		var genderChildIDs []uint
		h.DB.Model(&model.Category{}).Where("parent_id = ?", genderCategoryID).Pluck("id", &genderChildIDs)
		if len(genderChildIDs) > 0 {
			query = query.Where("gender_category_id IN ?", genderChildIDs)
		} else {
			query = query.Where("gender_category_id = ?", genderCategoryID)
		}
	}
	if materialType != "" {
		query = query.Where("type = ?", materialType)
	}

	var total int64
	query.Count(&total)

	switch sort {
	case "latest":
		query = query.Order("created_at DESC")
	case "downloads":
		query = query.Order("download_count DESC")
	default:
		query = query.Order("hot_score DESC")
	}

	var materials []model.Material
	query.Offset((page - 1) * pageSize).Limit(pageSize).Find(&materials)

	// 检查当前用户收藏状态
	userID := middleware.GetUserID(c)
	favoriteMap := h.getUserFavorites(userID, materials)

	list := make([]MaterialListItem, len(materials))
	for i, m := range materials {
		tags := make([]string, 0)
		if m.Tags != nil {
			tags = m.Tags
		}
		list[i] = MaterialListItem{
			ID:            m.ID,
			Title:         m.Title,
			Type:          m.Type,
			ThumbnailURL:  m.ThumbnailURL,
			Width:         m.Width,
			Height:        m.Height,
			Duration:      m.Duration,
			HotScore:      m.HotScore,
			DownloadCount: m.DownloadCount,
			FavoriteCount: m.FavoriteCount,
			Tags:          tags,
			IsFavorited:   favoriteMap[m.ID],
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// ==================== 详情 ====================

func (h *MaterialHandler) Detail(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	var material model.Material
	if err := h.DB.Preload("Category").First(&material, id).Error; err != nil {
		response.NotFound(c, "素材不存在")
		return
	}

	if material.Status != "published" {
		response.NotFound(c, "素材不存在")
		return
	}

	// 异步增加浏览量
	go h.DB.Model(&material).UpdateColumn("view_count", gorm.Expr("view_count + 1"))

	// 记录浏览行为
	userID := middleware.GetUserID(c)
	if userID > 0 {
		go h.DB.Create(&model.UserBehavior{
			UserID:     userID,
			MaterialID: uint(id),
			Action:     "view",
			CreatedAt:  time.Now(),
		})
	}

	isFavorited := false
	if userID > 0 {
		var count int64
		h.DB.Model(&model.Favorite{}).
			Where("user_id = ? AND target_type = ? AND target_id = ?", userID, "material", id).
			Count(&count)
		isFavorited = count > 0
	}

	categoryName := ""
	if material.Category != nil {
		categoryName = material.Category.Name
	}

	tags := make([]string, 0)
	if material.Tags != nil {
		tags = material.Tags
	}

	resp := MaterialDetailResp{
		ID:            material.ID,
		Title:         material.Title,
		Description:   material.Description,
		Type:          material.Type,
		CategoryID:    material.CategoryID,
		CategoryName:  categoryName,
		Tags:          tags,
		Width:         material.Width,
		Height:        material.Height,
		Duration:      material.Duration,
		FileSize:      material.FileSize,
		FileSizeText:  material.FileSizeText(),
		ThumbnailURL:  material.ThumbnailURL,
		WatermarkURL:  material.WatermarkURL,
		PreviewMovURL: material.PreviewMovURL,
		HotScore:      material.HotScore,
		DownloadCount: material.DownloadCount,
		FavoriteCount: material.FavoriteCount,
		ViewCount:     material.ViewCount,
		IsFavorited:   isFavorited,
		CreatedAt:     material.CreatedAt.Format("2006-01-02 15:04"),
	}

	response.Success(c, resp)
}

// ==================== 搜索 ====================

func (h *MaterialHandler) Search(c *gin.Context) {
	keyword := c.Query("keyword")
	if keyword == "" {
		response.BadRequest(c, 400, "请输入搜索关键词")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 50 {
		pageSize = 20
	}

	query := h.DB.Model(&model.Material{}).
		Where("status = ?", "published").
		Where("title ILIKE ? OR ? = ANY(tags)", "%"+keyword+"%", keyword)

	var total int64
	query.Count(&total)

	var materials []model.Material
	query.Order("hot_score DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&materials)

	userID := middleware.GetUserID(c)
	favoriteMap := h.getUserFavorites(userID, materials)

	list := make([]MaterialListItem, len(materials))
	for i, m := range materials {
		tags := make([]string, 0)
		if m.Tags != nil {
			tags = m.Tags
		}
		list[i] = MaterialListItem{
			ID:            m.ID,
			Title:         m.Title,
			Type:          m.Type,
			ThumbnailURL:  m.ThumbnailURL,
			Width:         m.Width,
			Height:        m.Height,
			Duration:      m.Duration,
			HotScore:      m.HotScore,
			DownloadCount: m.DownloadCount,
			FavoriteCount: m.FavoriteCount,
			Tags:          tags,
			IsFavorited:   favoriteMap[m.ID],
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// ==================== 下载 ====================

func (h *MaterialHandler) Download(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)

	// 查询用户信息
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	// 检查是否会员
	if !user.IsMember() {
		response.Forbidden(c, "请先开通会员")
		return
	}

	// 检查月下载额度
	monthlyLimit := 5000
	if user.MemberType == "flagship" {
		monthlyLimit = 10000
	}

	// 重置月计数器
	now := time.Now()
	if user.DownloadCountResetAt == nil || user.DownloadCountResetAt.Month() != now.Month() {
		h.DB.Model(&user).Updates(map[string]interface{}{
			"monthly_download_count": 0,
			"download_count_reset_at": now,
		})
		user.MonthlyDownloadCount = 0
	}

	if user.MonthlyDownloadCount >= monthlyLimit {
		response.Error(c, 403, response.ErrCodeDownloadLimit, "本月下载次数已用完")
		return
	}

	// 查询素材
	var material model.Material
	if err := h.DB.First(&material, id).Error; err != nil {
		response.NotFound(c, "素材不存在")
		return
	}

	// 记录下载
	h.DB.Create(&model.Download{
		UserID:       userID,
		MaterialID:   uint(id),
		DownloadedAt: now,
	})

	// 更新计数
	h.DB.Model(&user).UpdateColumn("monthly_download_count", gorm.Expr("monthly_download_count + 1"))
	h.DB.Model(&material).UpdateColumn("download_count", gorm.Expr("download_count + 1"))

	// 记录行为
	h.DB.Create(&model.UserBehavior{
		UserID:     userID,
		MaterialID: uint(id),
		Action:     "download",
		CreatedAt:  now,
	})

	// 更新热度
	go h.updateHotScore(&material)

	// 解析原图 URLs
	var urls []string
	if len(material.OriginalURLs) > 0 {
		json.Unmarshal(material.OriginalURLs, &urls)
	}
	downloadURL := ""
	if len(urls) > 0 {
		downloadURL = urls[0]
	}

	response.Success(c, gin.H{
		"download_url":     downloadURL,
		"download_urls":    urls,
		"remaining_count":  monthlyLimit - user.MonthlyDownloadCount - 1,
		"monthly_limit":    monthlyLimit,
	})
}

// ==================== 内部方法 ====================

func (h *MaterialHandler) getUserFavorites(userID uint, materials []model.Material) map[uint]bool {
	result := make(map[uint]bool)
	if userID == 0 || len(materials) == 0 {
		return result
	}

	ids := make([]uint, len(materials))
	for i, m := range materials {
		ids[i] = m.ID
	}

	var favorites []model.Favorite
	h.DB.Where("user_id = ? AND target_type = ? AND target_id IN ?", userID, "material", ids).
		Find(&favorites)

	for _, f := range favorites {
		result[f.TargetID] = true
	}
	return result
}

func (h *MaterialHandler) updateHotScore(m *model.Material) {
	hours := time.Since(m.CreatedAt).Hours()
	rawScore := float64(m.DownloadCount)*5 + float64(m.FavoriteCount)*3 + float64(m.ViewCount)*1
	denom := 1.0
	base := hours + 2
	// (hours+2)^1.5
	denom = base * base * base
	if denom > 0 {
		denom = sqrt(denom)
	}
	hotScore := rawScore / denom
	h.DB.Model(m).UpdateColumn("hot_score", hotScore)
}

// 简单 sqrt 近似，避免引入 math 包的 Pow
func sqrt(x float64) float64 {
	if x <= 0 {
		return 0
	}
	z := x / 2
	for i := 0; i < 20; i++ {
		z = z - (z*z-x)/(2*z)
	}
	return z
}
