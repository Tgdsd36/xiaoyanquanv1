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

type FavoriteGroupHandler struct {
	DB      *gorm.DB
	BaseURL string
}

type FavoriteGroupResp struct {
	ID        uint   `json:"id"`
	Name      string `json:"name"`
	IsDefault bool   `json:"is_default"`
	ItemCount int64  `json:"item_count"`
	CoverURL  string `json:"cover_url"`
}

// List 我的收藏分组列表
func (h *FavoriteGroupHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)

	// 确保用户有默认分组
	h.ensureDefaultGroup(userID)

	var groups []model.FavoriteGroup
	h.DB.Where("user_id = ?", userID).
		Order("is_default DESC, sort_order ASC, created_at ASC").
		Find(&groups)

	list := make([]FavoriteGroupResp, len(groups))
	for i, g := range groups {
		// 统计组内收藏数
		var count int64
		h.DB.Model(&model.Favorite{}).
			Where("group_id = ?", g.ID).
			Count(&count)

		// 取组内最新素材缩略图作为封面
		coverURL := ""
		var latestFav model.Favorite
		if h.DB.Where("group_id = ? AND target_type = ?", g.ID, "material").
			Order("created_at DESC").First(&latestFav).Error == nil {
			var m model.Material
			if h.DB.Select("thumbnail_url").First(&m, latestFav.TargetID).Error == nil {
				coverURL = fullURL(h.BaseURL, m.ThumbnailURL)
			}
		}

		list[i] = FavoriteGroupResp{
			ID:        g.ID,
			Name:      g.Name,
			IsDefault: g.IsDefault,
			ItemCount: count,
			CoverURL:  coverURL,
		}
	}

	response.Success(c, list)
}

// Create 创建分组
func (h *FavoriteGroupHandler) Create(c *gin.Context) {
	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "请输入分组名称")
		return
	}

	userID := middleware.GetUserID(c)

	// 检查重名
	var count int64
	h.DB.Model(&model.FavoriteGroup{}).
		Where("user_id = ? AND name = ?", userID, req.Name).
		Count(&count)
	if count > 0 {
		response.BadRequest(c, 400, "分组名称已存在")
		return
	}

	group := model.FavoriteGroup{
		UserID:    userID,
		Name:      req.Name,
		IsDefault: false,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	if err := h.DB.Create(&group).Error; err != nil {
		response.ServerError(c, "创建失败")
		return
	}

	response.Success(c, FavoriteGroupResp{
		ID:        group.ID,
		Name:      group.Name,
		IsDefault: false,
		ItemCount: 0,
		CoverURL:  "",
	})
}

// Update 修改分组名称
func (h *FavoriteGroupHandler) Update(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "请输入分组名称")
		return
	}

	userID := middleware.GetUserID(c)

	var group model.FavoriteGroup
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&group).Error; err != nil {
		response.NotFound(c, "分组不存在")
		return
	}

	// 检查重名（排除自身）
	var count int64
	h.DB.Model(&model.FavoriteGroup{}).
		Where("user_id = ? AND name = ? AND id != ?", userID, req.Name, id).
		Count(&count)
	if count > 0 {
		response.BadRequest(c, 400, "分组名称已存在")
		return
	}

	h.DB.Model(&group).Updates(map[string]interface{}{
		"name":       req.Name,
		"updated_at": time.Now(),
	})

	response.SuccessMessage(c, "修改成功")
}

// Delete 删除分组（默认分组不可删除）
func (h *FavoriteGroupHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)

	var group model.FavoriteGroup
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&group).Error; err != nil {
		response.NotFound(c, "分组不存在")
		return
	}

	if group.IsDefault {
		response.BadRequest(c, 400, "默认分组不能删除")
		return
	}

	// 找出该分组中的素材，检查哪些素材在其他分组中不再存在（需要减 favorite_count）
	var favorites []model.Favorite
	h.DB.Where("group_id = ? AND target_type = ?", id, "material").Find(&favorites)

	for _, fav := range favorites {
		// 检查该用户在其他分组中是否还收藏了这个素材
		var otherCount int64
		h.DB.Model(&model.Favorite{}).
			Where("user_id = ? AND target_type = ? AND target_id = ? AND group_id != ?",
				userID, fav.TargetType, fav.TargetID, id).
			Count(&otherCount)
		if otherCount == 0 {
			// 该素材在此用户的所有分组中都没了，减 favorite_count
			h.DB.Model(&model.Material{}).Where("id = ?", fav.TargetID).
				UpdateColumn("favorite_count", gorm.Expr("GREATEST(favorite_count - 1, 0)"))
		}
	}

	// 删除组内所有收藏记录
	h.DB.Where("group_id = ?", id).Delete(&model.Favorite{})
	// 删除分组
	h.DB.Delete(&group)

	response.SuccessMessage(c, "删除成功")
}

// ensureDefaultGroup 确保用户有默认分组（懒创建）
func (h *FavoriteGroupHandler) ensureDefaultGroup(userID uint) model.FavoriteGroup {
	var group model.FavoriteGroup
	err := h.DB.Where("user_id = ? AND is_default = true", userID).First(&group).Error
	if err == nil {
		return group
	}
	group = model.FavoriteGroup{
		UserID:    userID,
		Name:      "默认收藏",
		IsDefault: true,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	h.DB.Create(&group)
	return group
}
