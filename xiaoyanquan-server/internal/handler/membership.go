package handler

import (
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

type MembershipHandler struct {
	DB *gorm.DB
}

type MembershipStatusResp struct {
	MemberType           string `json:"member_type"`
	MemberExpireAt       string `json:"member_expire_at"`
	IsActive             bool   `json:"is_active"`
	MonthlyDownloadCount int    `json:"monthly_download_count"`
	MonthlyDownloadLimit int    `json:"monthly_download_limit"`
	DaysRemaining        int    `json:"days_remaining"`
}

type PurchaseReq struct {
	PlanType       string `json:"plan_type" binding:"required,oneof=pro_monthly flagship_monthly"`
	PaymentChannel string `json:"payment_channel" binding:"required,oneof=apple_iap wechat alipay"`
}

// Status 会员状态
func (h *MembershipHandler) Status(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	expireAt := ""
	daysRemaining := 0
	isActive := user.IsMember()
	if user.MemberExpireAt != nil {
		expireAt = user.MemberExpireAt.Format("2006-01-02")
		if isActive {
			daysRemaining = int(time.Until(*user.MemberExpireAt).Hours() / 24)
		}
	}

	limit := 0
	switch user.MemberType {
	case "pro":
		limit = 5000
	case "flagship":
		limit = 10000
	}

	resp := MembershipStatusResp{
		MemberType:           user.MemberType,
		MemberExpireAt:       expireAt,
		IsActive:             isActive,
		MonthlyDownloadCount: user.MonthlyDownloadCount,
		MonthlyDownloadLimit: limit,
		DaysRemaining:        daysRemaining,
	}
	response.Success(c, resp)
}

// Purchase 创建订单（实际支付需对接第三方，这里创建待支付订单）
func (h *MembershipHandler) Purchase(c *gin.Context) {
	var req PurchaseReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)

	var amount float64
	switch req.PlanType {
	case "pro_monthly":
		amount = 299
	case "flagship_monthly":
		amount = 499
	}

	order := model.Order{
		UserID:         userID,
		PlanType:       req.PlanType,
		Amount:         amount,
		PaymentChannel: req.PaymentChannel,
		Status:         "pending",
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}
	if err := h.DB.Create(&order).Error; err != nil {
		response.ServerError(c, "创建订单失败")
		return
	}

	// TODO: 对接真实支付渠道，返回支付参数
	// 开发阶段直接模拟支付成功
	h.activateMembership(userID, req.PlanType)
	h.DB.Model(&order).Updates(map[string]interface{}{
		"status":         "paid",
		"transaction_id": "dev_" + time.Now().Format("20060102150405"),
	})

	response.Success(c, gin.H{
		"order_id": order.ID,
		"status":   "paid",
		"message":  "开通成功",
	})
}

func (h *MembershipHandler) activateMembership(userID uint, planType string) {
	memberType := "pro"
	if planType == "flagship_monthly" {
		memberType = "flagship"
	}

	var user model.User
	h.DB.First(&user, userID)

	expireAt := time.Now().AddDate(0, 1, 0)
	if user.IsMember() && user.MemberExpireAt != nil && user.MemberExpireAt.After(time.Now()) {
		expireAt = user.MemberExpireAt.AddDate(0, 1, 0)
	}

	h.DB.Model(&user).Updates(map[string]interface{}{
		"member_type":      memberType,
		"member_expire_at": expireAt,
	})
}
