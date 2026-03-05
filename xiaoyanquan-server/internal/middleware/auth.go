package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/xiaoyanquan/server/internal/config"
	"github.com/xiaoyanquan/server/internal/model"
	myjwt "github.com/xiaoyanquan/server/pkg/jwt"
	"github.com/xiaoyanquan/server/pkg/response"
	"gorm.io/gorm"
)

const (
	ContextUserID    = "user_id"
	ContextPhone     = "phone"
	ContextAdminID   = "admin_id"
	ContextAdminRole = "admin_role"
)

// AuthRequired 强制登录
func AuthRequired(cfg *config.JWTConfig, db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, err := extractClaims(c, cfg)
		if err != nil {
			response.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}
		if err := validateDeviceBinding(c, db, claims); err != nil {
			handleDeviceValidationError(c, err)
			c.Abort()
			return
		}
		c.Set(ContextUserID, claims.UserID)
		c.Set(ContextPhone, claims.Phone)
		c.Next()
	}
}

// AuthOptional 可选登录（游客也能访问，但登录用户会注入 user_id）
func AuthOptional(cfg *config.JWTConfig, db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, err := extractClaims(c, cfg)
		if err == nil {
			if validateDeviceBinding(c, db, claims) == nil {
				c.Set(ContextUserID, claims.UserID)
				c.Set(ContextPhone, claims.Phone)
			}
		}
		c.Next()
	}
}

// MemberRequired 会员专属
func MemberRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		// user_id 已由 AuthRequired 注入
		// 具体会员校验在 handler/service 层做（需查数据库）
		_, exists := c.Get(ContextUserID)
		if !exists {
			response.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}
		c.Next()
	}
}

func extractClaims(c *gin.Context, cfg *config.JWTConfig) (*myjwt.Claims, error) {
	return extractClaimsWithType(c, cfg, "access")
}

func extractClaimsWithType(c *gin.Context, cfg *config.JWTConfig, expectedType string) (*myjwt.Claims, error) {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		return nil, myjwt.ErrTokenInvalid
	}

	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer" {
		return nil, myjwt.ErrTokenInvalid
	}

	claims, err := myjwt.ParseToken(cfg.Secret, parts[1])
	if err != nil {
		return nil, err
	}

	if claims.Type != expectedType {
		return nil, myjwt.ErrTokenInvalid
	}

	return claims, nil
}

func validateDeviceBinding(c *gin.Context, db *gorm.DB, claims *myjwt.Claims) error {
	requestDeviceID := strings.TrimSpace(c.GetHeader("X-Device-Id"))
	if requestDeviceID == "" {
		return gorm.ErrInvalidData
	}
	if claims.DeviceID == "" || claims.DeviceID != requestDeviceID {
		return gorm.ErrRecordNotFound
	}
	if db == nil {
		return nil
	}

	var binding model.UserDeviceBinding
	if err := db.Where("user_id = ?", claims.UserID).First(&binding).Error; err != nil {
		return gorm.ErrRecordNotFound
	}
	if binding.DeviceID != requestDeviceID {
		return gorm.ErrRecordNotFound
	}
	return nil
}

func handleDeviceValidationError(c *gin.Context, err error) {
	if err == gorm.ErrInvalidData {
		response.BadRequest(c, response.ErrCodeDeviceIDRequired, "缺少设备标识，请升级客户端后重试")
		return
	}
	response.Error(c, http.StatusUnauthorized, response.ErrCodeDeviceMismatch, "设备校验失败，请重新登录")
}

// AdminRequired 管理员认证
func AdminRequired(cfg *config.JWTConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, err := extractClaimsWithType(c, cfg, "admin_access")
		if err != nil {
			response.Unauthorized(c, "管理员认证失败")
			c.Abort()
			return
		}
		c.Set(ContextAdminID, claims.UserID)
		c.Set(ContextAdminRole, claims.Subject) // role stored in Subject
		c.Next()
	}
}

// GetUserID 从 context 获取 user_id，未登录返回 0
func GetUserID(c *gin.Context) uint {
	if id, ok := c.Get(ContextUserID); ok {
		return id.(uint)
	}
	return 0
}

// GetAdminID 从 context 获取 admin_id
func GetAdminID(c *gin.Context) uint {
	if id, ok := c.Get(ContextAdminID); ok {
		return id.(uint)
	}
	return 0
}
