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

type QuestionHandler struct {
	DB *gorm.DB
}

type QuestionItem struct {
	ID           uint   `json:"id"`
	UserNickname string `json:"user_nickname"`
	UserAvatar   string `json:"user_avatar"`
	QuestionText string `json:"question_text"`
	ReplyText    string `json:"reply_text"`
	Status       string `json:"status"`
	CreatedAt    string `json:"created_at"`
	RepliedAt    string `json:"replied_at,omitempty"`
}

type CreateQuestionReq struct {
	TargetType   string `json:"target_type" binding:"required,oneof=material moment"`
	TargetID     uint   `json:"target_id" binding:"required"`
	QuestionText string `json:"question_text" binding:"required,min=2,max=500"`
}

// Create 提交提问
func (h *QuestionHandler) Create(c *gin.Context) {
	var req CreateQuestionReq
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

	q := model.Question{
		UserID:       userID,
		TargetType:   req.TargetType,
		TargetID:     req.TargetID,
		QuestionText: req.QuestionText,
		Status:       "pending",
		CreatedAt:    time.Now(),
	}
	if err := h.DB.Create(&q).Error; err != nil {
		response.ServerError(c, "提问失败")
		return
	}

	// 更新朋友圈提问数
	if req.TargetType == "moment" {
		h.DB.Model(&model.Moment{}).Where("id = ?", req.TargetID).
			UpdateColumn("question_count", gorm.Expr("question_count + 1"))
	}

	response.Success(c, gin.H{"id": q.ID})
}

// MyList 我的提问列表
func (h *QuestionHandler) MyList(c *gin.Context) {
	userID := middleware.GetUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}

	var total int64
	h.DB.Model(&model.Question{}).Where("user_id = ?", userID).Count(&total)

	var questions []model.Question
	h.DB.Where("user_id = ?", userID).
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&questions)

	list := make([]QuestionItem, len(questions))
	for i, q := range questions {
		repliedAt := ""
		if q.RepliedAt != nil {
			repliedAt = q.RepliedAt.Format("2006-01-02 15:04")
		}
		list[i] = QuestionItem{
			ID:           q.ID,
			QuestionText: q.QuestionText,
			ReplyText:    q.ReplyText,
			Status:       q.Status,
			CreatedAt:    q.CreatedAt.Format("2006-01-02 15:04"),
			RepliedAt:    repliedAt,
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// PublicList 素材/动态下的公开提问
func (h *QuestionHandler) PublicList(c *gin.Context) {
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
		Where("target_type = ? AND target_id = ?", "material", id).
		Count(&total)

	var questions []model.Question
	h.DB.Preload("User").
		Where("target_type = ? AND target_id = ?", "material", id).
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
