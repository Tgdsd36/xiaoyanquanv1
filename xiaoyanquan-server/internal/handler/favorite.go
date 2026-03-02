package handler

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

type FavoriteHandler struct {
	DB *gorm.DB
}

type CreateFavoriteReq struct {
	TargetType string `json:"target_type" binding:"required,oneof=material moment"`
	TargetID   uint   `json:"target_id" binding:"required"`
}

type FavoriteListItem struct {
	ID         uint   `json:"id"`
	TargetType string `json:"target_type"`
	TargetID   uint   `json:"target_id"`
	Title      string `json:"title"`
	Thumbnail  string `json:"thumbnail"`
	CreatedAt  string `json:"created_at"`
}

// Create 添加收藏
func (h *FavoriteHandler) Create(c *gin.Context) {
	var req CreateFavoriteReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)

	// 检查会员
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		response.ServerError(c, "系统错误")
		return
	}
	if !user.IsMember() {
		response.Forbidden(c, "请先开通会员")
		return
	}

	// 检查是否已收藏
	var count int64
	h.DB.Model(&model.Favorite{}).
		Where("user_id = ? AND target_type = ? AND target_id = ?", userID, req.TargetType, req.TargetID).
		Count(&count)
	if count > 0 {
		response.BadRequest(c, 400, "已收藏")
		return
	}

	fav := model.Favorite{
		UserID:     userID,
		TargetType: req.TargetType,
		TargetID:   req.TargetID,
		CreatedAt:  time.Now(),
	}
	if err := h.DB.Create(&fav).Error; err != nil {
		response.ServerError(c, "收藏失败")
		return
	}

	// 更新素材收藏数
	if req.TargetType == "material" {
		h.DB.Model(&model.Material{}).Where("id = ?", req.TargetID).
			UpdateColumn("favorite_count", gorm.Expr("favorite_count + 1"))
	}

	response.Success(c, gin.H{"id": fav.ID})
}

// Delete 取消收藏
func (h *FavoriteHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)

	var fav model.Favorite
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&fav).Error; err != nil {
		response.NotFound(c, "收藏不存在")
		return
	}

	h.DB.Delete(&fav)

	if fav.TargetType == "material" {
		h.DB.Model(&model.Material{}).Where("id = ?", fav.TargetID).
			UpdateColumn("favorite_count", gorm.Expr("GREATEST(favorite_count - 1, 0)"))
	}

	response.SuccessMessage(c, "已取消收藏")
}

// List 我的收藏列表
func (h *FavoriteHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	targetType := c.DefaultQuery("type", "material")
	if page < 1 {
		page = 1
	}

	var total int64
	h.DB.Model(&model.Favorite{}).
		Where("user_id = ? AND target_type = ?", userID, targetType).
		Count(&total)

	var favorites []model.Favorite
	h.DB.Where("user_id = ? AND target_type = ?", userID, targetType).
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&favorites)

	list := make([]FavoriteListItem, len(favorites))
	for i, f := range favorites {
		item := FavoriteListItem{
			ID:         f.ID,
			TargetType: f.TargetType,
			TargetID:   f.TargetID,
			CreatedAt:  f.CreatedAt.Format("2006-01-02 15:04"),
		}
		// 补充标题和缩略图
		if f.TargetType == "material" {
			var m model.Material
			if h.DB.Select("title, thumbnail_url").First(&m, f.TargetID).Error == nil {
				item.Title = m.Title
				item.Thumbnail = m.ThumbnailURL
			}
		}
		list[i] = item
	}

	response.SuccessPage(c, list, total, page, pageSize)
}
