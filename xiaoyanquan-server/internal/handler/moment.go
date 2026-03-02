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
	DB *gorm.DB
}

type MomentListItem struct {
	ID            uint     `json:"id"`
	ContentText   string   `json:"content_text"`
	MediaType     string   `json:"media_type"`
	MediaURLs     []string `json:"media_urls"`
	QuestionCount int      `json:"question_count"`
	IsFavorited   bool     `json:"is_favorited"`
	CreatedAt     string   `json:"created_at"`
}

type MomentDetailResp struct {
	ID            uint     `json:"id"`
	ContentText   string   `json:"content_text"`
	MediaType     string   `json:"media_type"`
	MediaURLs     []string `json:"media_urls"`
	QuestionCount int      `json:"question_count"`
	IsFavorited   bool     `json:"is_favorited"`
	CreatedAt     string   `json:"created_at"`
}

// List 朋友圈列表
func (h *MomentHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 50 {
		pageSize = 20
	}

	var total int64
	h.DB.Model(&model.Moment{}).Where("status = ?", "published").Count(&total)

	var moments []model.Moment
	h.DB.Where("status = ?", "published").
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&moments)

	userID := middleware.GetUserID(c)
	favoriteMap := h.getMomentFavorites(userID, moments)

	list := make([]MomentListItem, len(moments))
	for i, m := range moments {
		list[i] = MomentListItem{
			ID:            m.ID,
			ContentText:   m.ContentText,
			MediaType:     m.MediaType,
			MediaURLs:     parseMediaURLs(m.MediaURLs),
			QuestionCount: m.QuestionCount,
			IsFavorited:   favoriteMap[m.ID],
			CreatedAt:     m.CreatedAt.Format("2006-01-02 15:04"),
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// Detail 动态详情
func (h *MomentHandler) Detail(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	var moment model.Moment
	if err := h.DB.First(&moment, id).Error; err != nil {
		response.NotFound(c, "动态不存在")
		return
	}

	userID := middleware.GetUserID(c)
	isFavorited := false
	if userID > 0 {
		var count int64
		h.DB.Model(&model.Favorite{}).
			Where("user_id = ? AND target_type = ? AND target_id = ?", userID, "moment", id).
			Count(&count)
		isFavorited = count > 0
	}

	resp := MomentDetailResp{
		ID:            moment.ID,
		ContentText:   moment.ContentText,
		MediaType:     moment.MediaType,
		MediaURLs:     parseMediaURLs(moment.MediaURLs),
		QuestionCount: moment.QuestionCount,
		IsFavorited:   isFavorited,
		CreatedAt:     moment.CreatedAt.Format("2006-01-02 15:04"),
	}

	response.Success(c, resp)
}

// Questions 动态下的公开提问
func (h *MomentHandler) Questions(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}

	var total int64
	h.DB.Model(&model.Question{}).
		Where("target_type = ? AND target_id = ?", "moment", id).
		Count(&total)

	var questions []model.Question
	h.DB.Preload("User").
		Where("target_type = ? AND target_id = ?", "moment", id).
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&questions)

	list := make([]QuestionItem, len(questions))
	for i, q := range questions {
		nickname := ""
		avatar := ""
		if q.User != nil {
			nickname = q.User.Nickname
			avatar = q.User.AvatarURL
		}
		repliedAt := ""
		if q.RepliedAt != nil {
			repliedAt = q.RepliedAt.Format("2006-01-02 15:04")
		}
		list[i] = QuestionItem{
			ID:           q.ID,
			UserNickname: nickname,
			UserAvatar:   avatar,
			QuestionText: q.QuestionText,
			ReplyText:    q.ReplyText,
			Status:       q.Status,
			CreatedAt:    q.CreatedAt.Format("2006-01-02 15:04"),
			RepliedAt:    repliedAt,
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

func (h *MomentHandler) getMomentFavorites(userID uint, moments []model.Moment) map[uint]bool {
	result := make(map[uint]bool)
	if userID == 0 || len(moments) == 0 {
		return result
	}
	ids := make([]uint, len(moments))
	for i, m := range moments {
		ids[i] = m.ID
	}
	var favorites []model.Favorite
	h.DB.Where("user_id = ? AND target_type = ? AND target_id IN ?", userID, "moment", ids).
		Find(&favorites)
	for _, f := range favorites {
		result[f.TargetID] = true
	}
	return result
}

func parseMediaURLs(raw model.JSON) []string {
	var urls []string
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &urls)
	}
	if urls == nil {
		return []string{}
	}
	return urls
}
