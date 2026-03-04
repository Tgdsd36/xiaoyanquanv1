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

type InspirationHandler struct {
	DB      *gorm.DB
	BaseURL string
}

// Feed 随机推荐素材（排除用户已 dislike 的）
func (h *InspirationHandler) Feed(c *gin.Context) {
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if pageSize < 1 || pageSize > 50 {
		pageSize = 20
	}

	userID := middleware.GetUserID(c)

	// 类型筛选
	materialType := c.Query("type")

	query := h.DB.Model(&model.Material{}).Where("status = ?", "published")

	if materialType != "" {
		query = query.Where("type = ?", materialType)
	}

	// 排除已 dislike 的素材
	if userID > 0 {
		query = query.Where("id NOT IN (?)",
			h.DB.Model(&model.UserBehavior{}).
				Select("material_id").
				Where("user_id = ? AND action = ?", userID, "dislike"),
		)
	}

	var materials []model.Material
	query.Order("RANDOM()").Limit(pageSize).Find(&materials)

	// 收藏状态
	favoriteMap := make(map[uint]bool)
	if userID > 0 && len(materials) > 0 {
		ids := make([]uint, len(materials))
		for i, m := range materials {
			ids[i] = m.ID
		}
		var favorites []model.Favorite
		h.DB.Where("user_id = ? AND target_type = ? AND target_id IN ?", userID, "material", ids).
			Find(&favorites)
		for _, f := range favorites {
			favoriteMap[f.TargetID] = true
		}
	}

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
			ThumbnailURL:  fullURL(h.BaseURL, m.ThumbnailURL),
			WatermarkURL:  fullURL(h.BaseURL, m.WatermarkURL),
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

	response.Success(c, list)
}

// Dislike 标记不感兴趣
func (h *InspirationHandler) Dislike(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		response.Unauthorized(c, "请先登录")
		return
	}

	var req struct {
		MaterialID uint `json:"material_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	h.DB.Create(&model.UserBehavior{
		UserID:     userID,
		MaterialID: req.MaterialID,
		Action:     "dislike",
		CreatedAt:  time.Now(),
	})

	response.SuccessMessage(c, "ok")
}
