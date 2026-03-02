package handler

import (
	"strconv"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

type UserHandler struct {
	DB *gorm.DB
}

type ProfileResponse struct {
	ID                   uint   `json:"id"`
	Phone                string `json:"phone"`
	Nickname             string `json:"nickname"`
	AvatarURL            string `json:"avatar_url"`
	MemberType           string `json:"member_type"`
	MemberExpireAt       string `json:"member_expire_at"`
	MonthlyDownloadCount int    `json:"monthly_download_count"`
	MonthlyDownloadLimit int    `json:"monthly_download_limit"`
}

type UpdateProfileReq struct {
	Nickname  string `json:"nickname" binding:"omitempty,min=1,max=50"`
	AvatarURL string `json:"avatar_url" binding:"omitempty"`
}

type ChangePasswordReq struct {
	OldPassword string `json:"old_password" binding:"required,min=6"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

type DownloadRecord struct {
	ID           uint   `json:"id"`
	MaterialID   uint   `json:"material_id"`
	Title        string `json:"title"`
	ThumbnailURL string `json:"thumbnail_url"`
	DownloadedAt string `json:"downloaded_at"`
}

// Profile 获取个人信息
func (h *UserHandler) Profile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	expireAt := ""
	if user.MemberExpireAt != nil {
		expireAt = user.MemberExpireAt.Format("2006-01-02")
	}

	limit := 0
	switch user.MemberType {
	case "pro":
		limit = 5000
	case "flagship":
		limit = 10000
	}

	resp := ProfileResponse{
		ID:                   user.ID,
		Phone:                user.MaskedPhone(),
		Nickname:             user.Nickname,
		AvatarURL:            user.AvatarURL,
		MemberType:           user.MemberType,
		MemberExpireAt:       expireAt,
		MonthlyDownloadCount: user.MonthlyDownloadCount,
		MonthlyDownloadLimit: limit,
	}
	response.Success(c, resp)
}

// UpdateProfile 更新个人信息
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	var req UpdateProfileReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)
	updates := map[string]interface{}{}
	if req.Nickname != "" {
		updates["nickname"] = req.Nickname
	}
	if req.AvatarURL != "" {
		updates["avatar_url"] = req.AvatarURL
	}

	if len(updates) == 0 {
		response.BadRequest(c, 400, "没有需要更新的内容")
		return
	}

	h.DB.Model(&model.User{}).Where("id = ?", userID).Updates(updates)
	response.SuccessMessage(c, "更新成功")
}

// Downloads 我的下载记录
func (h *UserHandler) Downloads(c *gin.Context) {
	userID := middleware.GetUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}

	var total int64
	h.DB.Model(&model.Download{}).Where("user_id = ?", userID).Count(&total)

	var downloads []model.Download
	h.DB.Where("user_id = ?", userID).
		Order("downloaded_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&downloads)

	list := make([]DownloadRecord, len(downloads))
	for i, d := range downloads {
		item := DownloadRecord{
			ID:           d.ID,
			MaterialID:   d.MaterialID,
			DownloadedAt: d.DownloadedAt.Format("2006-01-02 15:04"),
		}
		var m model.Material
		if h.DB.Select("title, thumbnail_url").First(&m, d.MaterialID).Error == nil {
			item.Title = m.Title
			item.ThumbnailURL = m.ThumbnailURL
		}
		list[i] = item
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// ChangePassword 修改密码
func (h *UserHandler) ChangePassword(c *gin.Context) {
	var req ChangePasswordReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	if user.PasswordHash != "" {
		if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.OldPassword)); err != nil {
			response.BadRequest(c, response.ErrCodePasswordWrong, "原密码错误")
			return
		}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	h.DB.Model(&user).Update("password_hash", string(hash))
	response.SuccessMessage(c, "密码修改成功")
}
