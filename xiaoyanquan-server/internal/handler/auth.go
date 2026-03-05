package handler

import (
	"context"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/xiaoyanquan/server/internal/config"
	"github.com/xiaoyanquan/server/internal/model"
	myjwt "github.com/xiaoyanquan/server/pkg/jwt"
	"github.com/xiaoyanquan/server/pkg/response"
)

type AuthHandler struct {
	DB  *gorm.DB
	RDB *redis.Client
	Cfg *config.Config
}

// ==================== 请求结构 ====================

type SendSMSReq struct {
	Phone string `json:"phone" binding:"required,len=11"`
}

type SMSLoginReq struct {
	Phone string `json:"phone" binding:"required,len=11"`
	Code  string `json:"code" binding:"required,len=4"`
}

type PasswordLoginReq struct {
	Phone    string `json:"phone" binding:"required,len=11"`
	Password string `json:"password" binding:"required,min=6"`
}

type RegisterReq struct {
	Phone    string `json:"phone" binding:"required,len=11"`
	Code     string `json:"code" binding:"required,len=4"`
	Password string `json:"password" binding:"required,min=6"`
	Nickname string `json:"nickname"`
}

type RefreshReq struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// ==================== 响应结构 ====================

type LoginResponse struct {
	AccessToken  string       `json:"access_token"`
	RefreshToken string       `json:"refresh_token"`
	ExpiresIn    int64        `json:"expires_in"`
	User         UserResponse `json:"user"`
}

type UserResponse struct {
	ID             uint       `json:"id"`
	Phone          string     `json:"phone"`
	Nickname       string     `json:"nickname"`
	AvatarURL      string     `json:"avatar_url"`
	MemberType     string     `json:"member_type"`
	MemberExpireAt *time.Time `json:"member_expire_at"`
	IsNewUser      bool       `json:"is_new_user,omitempty"`
}

type DeviceBindingResponse struct {
	Bound      bool   `json:"bound"`
	DeviceID   string `json:"device_id,omitempty"`
	DeviceName string `json:"device_name,omitempty"`
	Platform   string `json:"platform,omitempty"`
	BoundAt    string `json:"bound_at,omitempty"`
}

type DeviceRequestInfo struct {
	DeviceID   string
	DeviceName string
	Platform   string
}

// ==================== 发送验证码 ====================

func (h *AuthHandler) SendSMS(c *gin.Context) {
	var req SendSMSReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "手机号格式错误")
		return
	}

	// 检查发送频率（1分钟内不能重复发送）
	ctx := context.Background()
	rateLimitKey := fmt.Sprintf("sms:rate:%s", req.Phone)
	if h.RDB.Exists(ctx, rateLimitKey).Val() > 0 {
		response.BadRequest(c, 400, "验证码发送过于频繁，请稍后再试")
		return
	}

	// 生成4位验证码
	code := fmt.Sprintf("%04d", rand.Intn(10000))

	// 存入 Redis，5分钟过期
	codeKey := fmt.Sprintf("sms:code:%s", req.Phone)
	h.RDB.Set(ctx, codeKey, code, 5*time.Minute)
	h.RDB.Set(ctx, rateLimitKey, "1", 1*time.Minute)

	// TODO: 调用短信服务发送验证码（开发阶段直接返回验证码）
	// sms.Send(req.Phone, code)

	response.Success(c, gin.H{
		"expire_seconds": 300,
		// 开发模式下返回验证码，生产环境删除此行
		"debug_code": code,
	})
}

// ==================== 短信验证码登录（自动注册）====================

func (h *AuthHandler) SMSLogin(c *gin.Context) {
	var req SMSLoginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	// 校验验证码
	if !h.verifyCode(req.Phone, req.Code) {
		response.BadRequest(c, response.ErrCodeSMSCodeInvalid, "验证码错误或已过期")
		return
	}

	device, ok := h.parseDeviceInfo(c)
	if !ok {
		return
	}

	// 查找或创建用户
	var user model.User
	isNewUser := false
	result := h.DB.Where("phone = ?", req.Phone).First(&user)
	if result.Error == gorm.ErrRecordNotFound {
		// 自动注册
		user = model.User{
			Phone:      req.Phone,
			Nickname:   "用户" + req.Phone[7:],
			MemberType: "free",
		}
		if err := h.DB.Create(&user).Error; err != nil {
			response.ServerError(c, "注册失败")
			return
		}
		isNewUser = true
	} else if result.Error != nil {
		response.ServerError(c, "系统错误")
		return
	}

	if !h.ensureDeviceBinding(c, user.ID, device) {
		return
	}

	h.respondWithToken(c, &user, isNewUser, device.DeviceID)
}

// ==================== 密码登录 ====================

func (h *AuthHandler) Login(c *gin.Context) {
	var req PasswordLoginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	var user model.User
	if err := h.DB.Where("phone = ?", req.Phone).First(&user).Error; err != nil {
		response.BadRequest(c, response.ErrCodePhoneNotFound, "账号不存在")
		return
	}

	if user.PasswordHash == "" {
		response.BadRequest(c, response.ErrCodePasswordWrong, "该账号未设置密码，请使用验证码登录")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		response.BadRequest(c, response.ErrCodePasswordWrong, "密码错误")
		return
	}

	device, ok := h.parseDeviceInfo(c)
	if !ok {
		return
	}
	if !h.ensureDeviceBinding(c, user.ID, device) {
		return
	}

	h.respondWithToken(c, &user, false, device.DeviceID)
}

// ==================== 注册 ====================

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	device, ok := h.parseDeviceInfo(c)
	if !ok {
		return
	}

	// 校验验证码
	if !h.verifyCode(req.Phone, req.Code) {
		response.BadRequest(c, response.ErrCodeSMSCodeInvalid, "验证码错误或已过期")
		return
	}

	// 检查手机号是否已注册
	var count int64
	h.DB.Model(&model.User{}).Where("phone = ?", req.Phone).Count(&count)
	if count > 0 {
		response.BadRequest(c, response.ErrCodePhoneRegistered, "手机号已注册")
		return
	}

	// 加密密码
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	nickname := req.Nickname
	if nickname == "" {
		nickname = "用户" + req.Phone[7:]
	}

	user := model.User{
		Phone:        req.Phone,
		PasswordHash: string(hash),
		Nickname:     nickname,
		MemberType:   "free",
	}
	if err := h.DB.Create(&user).Error; err != nil {
		response.ServerError(c, "注册失败")
		return
	}

	if !h.ensureDeviceBinding(c, user.ID, device) {
		return
	}

	h.respondWithToken(c, &user, true, device.DeviceID)
}

// ==================== 刷新 Token ====================

func (h *AuthHandler) Refresh(c *gin.Context) {
	var req RefreshReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	claims, err := myjwt.ParseToken(h.Cfg.JWT.Secret, req.RefreshToken)
	if err != nil {
		response.Unauthorized(c, "Token 已失效，请重新登录")
		return
	}
	if claims.Type != "refresh" {
		response.Unauthorized(c, "无效的 Token")
		return
	}
	if claims.DeviceID == "" {
		response.Error(c, http.StatusUnauthorized, response.ErrCodeDeviceMismatch, "设备校验失败，请重新登录")
		return
	}

	device, ok := h.parseDeviceInfo(c)
	if !ok {
		return
	}
	if device.DeviceID != claims.DeviceID {
		response.Error(c, http.StatusUnauthorized, response.ErrCodeDeviceMismatch, "设备校验失败，请重新登录")
		return
	}

	var binding model.UserDeviceBinding
	if err := h.DB.Where("user_id = ?", claims.UserID).First(&binding).Error; err != nil {
		response.Error(c, http.StatusUnauthorized, response.ErrCodeDeviceMismatch, "设备校验失败，请重新登录")
		return
	}
	if binding.DeviceID != device.DeviceID {
		response.Error(c, http.StatusUnauthorized, response.ErrCodeDeviceMismatch, "账号已在其他设备绑定，请重新登录")
		return
	}

	// 生成新的 token pair
	tokenPair, err := myjwt.GenerateTokenPair(
		h.Cfg.JWT.Secret, claims.UserID, claims.Phone, device.DeviceID, claims.SessionID,
		h.Cfg.JWT.AccessTokenTTL, h.Cfg.JWT.RefreshTokenTTL,
	)
	if err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	response.Success(c, tokenPair)
}

// ==================== 注销账号 ====================

func (h *AuthHandler) DeleteAccount(c *gin.Context) {
	userID, _ := c.Get("user_id")

	if err := h.DB.Delete(&model.User{}, userID).Error; err != nil {
		response.ServerError(c, "注销失败")
		return
	}

	response.SuccessMessage(c, "账号已注销")
}

// ==================== 设备绑定 ====================

// DeviceInfo 查询当前账号的设备绑定信息
func (h *AuthHandler) DeviceInfo(c *gin.Context) {
	userID, ok := getCurrentUserID(c)
	if !ok {
		response.Unauthorized(c, "请先登录")
		return
	}

	var binding model.UserDeviceBinding
	if err := h.DB.Where("user_id = ?", userID).First(&binding).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			response.Success(c, DeviceBindingResponse{Bound: false})
			return
		}
		response.ServerError(c, "系统错误")
		return
	}

	response.Success(c, DeviceBindingResponse{
		Bound:      true,
		DeviceID:   binding.DeviceID,
		DeviceName: binding.DeviceName,
		Platform:   binding.Platform,
		BoundAt:    binding.BoundAt.Format("2006-01-02 15:04:05"),
	})
}

// UnbindDevice 解绑当前账号的设备绑定
func (h *AuthHandler) UnbindDevice(c *gin.Context) {
	userID, ok := getCurrentUserID(c)
	if !ok {
		response.Unauthorized(c, "请先登录")
		return
	}

	if err := h.DB.Where("user_id = ?", userID).Delete(&model.UserDeviceBinding{}).Error; err != nil {
		response.ServerError(c, "解绑失败，请稍后重试")
		return
	}

	response.SuccessMessage(c, "设备解绑成功")
}

// ==================== 内部方法 ====================

func (h *AuthHandler) parseDeviceInfo(c *gin.Context) (DeviceRequestInfo, bool) {
	deviceID := strings.TrimSpace(c.GetHeader("X-Device-Id"))
	if deviceID == "" {
		response.BadRequest(c, response.ErrCodeDeviceIDRequired, "缺少设备标识，请升级客户端后重试")
		return DeviceRequestInfo{}, false
	}

	info := DeviceRequestInfo{
		DeviceID:   deviceID,
		DeviceName: strings.TrimSpace(c.GetHeader("X-Device-Name")),
		Platform:   strings.TrimSpace(c.GetHeader("X-Platform")),
	}
	if info.DeviceName == "" {
		info.DeviceName = "当前设备"
	}
	if info.Platform == "" {
		info.Platform = "unknown"
	}
	return info, true
}

func (h *AuthHandler) ensureDeviceBinding(c *gin.Context, userID uint, info DeviceRequestInfo) bool {
	newBinding := model.UserDeviceBinding{
		UserID:     userID,
		DeviceID:   info.DeviceID,
		DeviceName: info.DeviceName,
		Platform:   info.Platform,
		BoundAt:    time.Now(),
		UpdatedAt:  time.Now(),
	}
	if err := h.DB.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}},
		DoNothing: true,
	}).Create(&newBinding).Error; err != nil {
		response.ServerError(c, "系统错误")
		return false
	}

	var binding model.UserDeviceBinding
	if err := h.DB.Where("user_id = ?", userID).First(&binding).Error; err != nil {
		response.ServerError(c, "系统错误")
		return false
	}

	if binding.DeviceID != info.DeviceID {
		msg := "该账号已绑定其他设备，请先在原设备解绑"
		if binding.DeviceName != "" {
			msg = fmt.Sprintf("该账号已绑定设备「%s」，请先在原设备解绑", binding.DeviceName)
		}
		response.Error(c, http.StatusConflict, response.ErrCodeDeviceBoundOther, msg)
		return false
	}

	updates := map[string]interface{}{}
	if binding.DeviceName != info.DeviceName {
		updates["device_name"] = info.DeviceName
	}
	if binding.Platform != info.Platform {
		updates["platform"] = info.Platform
	}
	if len(updates) > 0 {
		updates["updated_at"] = time.Now()
		_ = h.DB.Model(&model.UserDeviceBinding{}).Where("id = ?", binding.ID).Updates(updates).Error
	}
	return true
}

func (h *AuthHandler) verifyCode(phone, code string) bool {
	ctx := context.Background()
	key := fmt.Sprintf("sms:code:%s", phone)
	stored, err := h.RDB.Get(ctx, key).Result()
	if err != nil {
		// Redis 中无验证码（未接入短信服务），开发模式放行
		// TODO: 接入短信服务后删除此 bypass
		return true
	}
	if stored != code {
		return false
	}
	// 验证成功后删除
	h.RDB.Del(ctx, key)
	return true
}

func getCurrentUserID(c *gin.Context) (uint, bool) {
	raw, exists := c.Get("user_id")
	if !exists {
		return 0, false
	}
	switch v := raw.(type) {
	case uint:
		return v, true
	case int:
		if v > 0 {
			return uint(v), true
		}
	case int64:
		if v > 0 {
			return uint(v), true
		}
	}
	return 0, false
}

func (h *AuthHandler) respondWithToken(c *gin.Context, user *model.User, isNewUser bool, deviceID string) {
	tokenPair, err := myjwt.GenerateTokenPair(
		h.Cfg.JWT.Secret, user.ID, user.Phone, deviceID, "",
		h.Cfg.JWT.AccessTokenTTL, h.Cfg.JWT.RefreshTokenTTL,
	)
	if err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	resp := LoginResponse{
		AccessToken:  tokenPair.AccessToken,
		RefreshToken: tokenPair.RefreshToken,
		ExpiresIn:    tokenPair.ExpiresIn,
		User: UserResponse{
			ID:             user.ID,
			Phone:          user.MaskedPhone(),
			Nickname:       user.Nickname,
			AvatarURL:      user.AvatarURL,
			MemberType:     user.MemberType,
			MemberExpireAt: user.MemberExpireAt,
			IsNewUser:      isNewUser,
		},
	}
	response.Success(c, resp)
}
