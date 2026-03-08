package handler

import (
	"fmt"
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
	GroupID    uint   `json:"group_id"` // 可选，0 表示用默认分组
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

// Toggle 切换收藏状态
// 收藏：带 group_id → 添加到指定分组（首次收藏该素材时 favorite_count+1）
// 取消：不带 group_id（或 group_id=0）且已收藏 → 从所有分组移除，favorite_count-1
func (h *FavoriteHandler) Toggle(c *gin.Context) {
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

	// 检查该用户是否已在任何分组中收藏了该素材
	var existingCount int64
	h.DB.Model(&model.Favorite{}).
		Where("user_id = ? AND target_type = ? AND target_id = ?", userID, req.TargetType, req.TargetID).
		Count(&existingCount)

	if req.GroupID > 0 {
		// ========== 收藏到指定分组 ==========
		// 验证分组归属
		var group model.FavoriteGroup
		if err := h.DB.Where("id = ? AND user_id = ?", req.GroupID, userID).First(&group).Error; err != nil {
			response.BadRequest(c, 400, "分组不存在")
			return
		}

		// 检查是否已在该分组中
		var dupCount int64
		h.DB.Model(&model.Favorite{}).
			Where("user_id = ? AND target_type = ? AND target_id = ? AND group_id = ?",
				userID, req.TargetType, req.TargetID, req.GroupID).
			Count(&dupCount)
		if dupCount > 0 {
			// 已在该分组，直接返回成功
			response.Success(c, gin.H{"is_favorited": true, "favorite_count": h.getMaterialFavCount(req.TargetType, req.TargetID)})
			return
		}

		// 添加收藏记录
		fav := model.Favorite{
			UserID:     userID,
			GroupID:    req.GroupID,
			TargetType: req.TargetType,
			TargetID:   req.TargetID,
			CreatedAt:  time.Now(),
		}
		if err := h.DB.Create(&fav).Error; err != nil {
			response.ServerError(c, "收藏失败")
			return
		}

		// 首次收藏该素材（之前任何分组都没有）→ favorite_count+1
		if existingCount == 0 && req.TargetType == "material" {
			h.DB.Model(&model.Material{}).Where("id = ?", req.TargetID).
				UpdateColumn("favorite_count", gorm.Expr("favorite_count + 1"))
		}

		response.Success(c, gin.H{"is_favorited": true, "favorite_count": h.getMaterialFavCount(req.TargetType, req.TargetID)})
		return
	}

	// ========== 取消收藏（group_id=0） ==========
	if existingCount == 0 {
		// 未收藏，直接返回
		response.Success(c, gin.H{"is_favorited": false, "favorite_count": h.getMaterialFavCount(req.TargetType, req.TargetID)})
		return
	}

	// 从所有分组中移除
	h.DB.Where("user_id = ? AND target_type = ? AND target_id = ?", userID, req.TargetType, req.TargetID).
		Delete(&model.Favorite{})

	if req.TargetType == "material" {
		h.DB.Model(&model.Material{}).Where("id = ?", req.TargetID).
			UpdateColumn("favorite_count", gorm.Expr("GREATEST(favorite_count - 1, 0)"))
	}

	response.Success(c, gin.H{"is_favorited": false, "favorite_count": h.getMaterialFavCount(req.TargetType, req.TargetID)})
}

// getMaterialFavCount 获取素材的当前收藏数
func (h *FavoriteHandler) getMaterialFavCount(targetType string, targetID uint) int {
	if targetType != "material" {
		return 0
	}
	var m model.Material
	if h.DB.Select("favorite_count").First(&m, targetID).Error == nil {
		return m.FavoriteCount
	}
	return 0
}

// BatchDelete 批量取消收藏
func (h *FavoriteHandler) BatchDelete(c *gin.Context) {
	var req struct {
		IDs []uint `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || len(req.IDs) == 0 {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)

	// 查出这些收藏记录（仅当前用户的）
	var favorites []model.Favorite
	h.DB.Where("id IN ? AND user_id = ?", req.IDs, userID).Find(&favorites)
	if len(favorites) == 0 {
		response.SuccessMessage(c, "无可删除的收藏")
		return
	}

	// 收集受影响的素材 target_id
	materialTargetIDs := map[uint]bool{}
	deleteIDs := make([]uint, 0, len(favorites))
	for _, f := range favorites {
		deleteIDs = append(deleteIDs, f.ID)
		if f.TargetType == "material" {
			materialTargetIDs[f.TargetID] = true
		}
	}

	// 批量删除
	h.DB.Where("id IN ? AND user_id = ?", deleteIDs, userID).Delete(&model.Favorite{})

	// 对受影响的素材检查是否还有剩余收藏，没有则 favorite_count-1
	for targetID := range materialTargetIDs {
		var remaining int64
		h.DB.Model(&model.Favorite{}).
			Where("user_id = ? AND target_type = 'material' AND target_id = ?", userID, targetID).
			Count(&remaining)
		if remaining == 0 {
			h.DB.Model(&model.Material{}).Where("id = ?", targetID).
				UpdateColumn("favorite_count", gorm.Expr("GREATEST(favorite_count - 1, 0)"))
		}
	}

	response.SuccessMessage(c, fmt.Sprintf("已取消 %d 条收藏", len(deleteIDs)))
}

// List 我的收藏列表（支持按分组筛选）
func (h *FavoriteHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	targetType := c.DefaultQuery("type", "material")
	groupID, _ := strconv.Atoi(c.DefaultQuery("group_id", "0"))
	if page < 1 {
		page = 1
	}

	query := h.DB.Model(&model.Favorite{}).
		Where("user_id = ? AND target_type = ?", userID, targetType)
	if groupID > 0 {
		query = query.Where("group_id = ?", groupID)
	}

	var total int64
	query.Count(&total)

	var favorites []model.Favorite
	query.Order("created_at DESC").
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
