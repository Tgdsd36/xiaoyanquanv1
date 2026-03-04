package handler

import (
	"encoding/json"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

type MomentHandler struct {
	DB      *gorm.DB
	BaseURL string
}

type MomentListItem struct {
	ID          uint     `json:"id"`
	Nickname    string   `json:"nickname"`
	AvatarURL   string   `json:"avatar_url"`
	Gender      string   `json:"gender"`
	ContentText string   `json:"content_text"`
	MediaType   string   `json:"media_type"`
	MediaURLs   []string `json:"media_urls"`
	IsFavorited bool     `json:"is_favorited"`
	CreatedAt   string   `json:"created_at"`
}

// List 朋友圈列表（数据源：素材表）
func (h *MomentHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 50 {
		pageSize = 20
	}

	query := h.DB.Model(&model.Material{}).Where("status = ?", "published")

	// 类型过滤
	if mediaType := c.Query("type"); mediaType != "" {
		query = query.Where("type = ?", mediaType)
	}
	// 性别过滤
	if gender := c.Query("gender"); gender != "" {
		query = query.Where("gender = ?", gender)
	}

	var total int64
	query.Count(&total)

	var materials []model.Material
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&materials)

	userID := middleware.GetUserID(c)
	favoriteMap := h.getFavorites(userID, materials)

	list := make([]MomentListItem, len(materials))
	for i, m := range materials {
		// 优先使用 original_urls（多图九宫格），回退到水印图/缩略图
		var mediaURLs []string
		var rawURLs []string
		if len(m.OriginalURLs) > 0 {
			_ = json.Unmarshal(m.OriginalURLs, &rawURLs)
		}
		if len(rawURLs) > 0 {
			for _, u := range rawURLs {
				if fu := fullURL(h.BaseURL, u); fu != "" {
					mediaURLs = append(mediaURLs, fu)
				}
			}
		}
		if len(mediaURLs) == 0 {
			if img := fullURL(h.BaseURL, m.WatermarkURL); img != "" {
				mediaURLs = []string{img}
			} else if img := fullURL(h.BaseURL, m.ThumbnailURL); img != "" {
				mediaURLs = []string{img}
			}
		}

		list[i] = MomentListItem{
			ID:          m.ID,
			Nickname:    "小颜圈",
			AvatarURL:   "",
			Gender:      m.Gender,
			ContentText: m.Title,
			MediaType:   m.Type,
			MediaURLs:   mediaURLs,
			IsFavorited: favoriteMap[m.ID],
			CreatedAt:   m.CreatedAt.Format("2006-01-02 15:04"),
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

func (h *MomentHandler) getFavorites(userID uint, materials []model.Material) map[uint]bool {
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
