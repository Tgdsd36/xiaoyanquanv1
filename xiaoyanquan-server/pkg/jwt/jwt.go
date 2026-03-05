package jwt

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	jwtgo "github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	UserID    uint   `json:"user_id"`
	Phone     string `json:"phone"`
	Type      string `json:"type"` // "access" or "refresh"
	DeviceID  string `json:"device_id,omitempty"`
	SessionID string `json:"sid,omitempty"`
	jwtgo.RegisteredClaims
}

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

var (
	ErrTokenExpired = errors.New("token expired")
	ErrTokenInvalid = errors.New("token invalid")
)

// GenerateTokenPair 生成 access + refresh token 对
func GenerateTokenPair(secret string, userID uint, phone, deviceID, sessionID string, accessTTL, refreshTTL time.Duration) (*TokenPair, error) {
	now := time.Now()
	if sessionID == "" {
		var err error
		sessionID, err = newSessionID()
		if err != nil {
			return nil, err
		}
	}

	// Access Token
	accessClaims := Claims{
		UserID:    userID,
		Phone:     phone,
		Type:      "access",
		DeviceID:  deviceID,
		SessionID: sessionID,
		RegisteredClaims: jwtgo.RegisteredClaims{
			ExpiresAt: jwtgo.NewNumericDate(now.Add(accessTTL)),
			IssuedAt:  jwtgo.NewNumericDate(now),
			Issuer:    "xiaoyanquan",
		},
	}
	accessToken, err := jwtgo.NewWithClaims(jwtgo.SigningMethodHS256, accessClaims).
		SignedString([]byte(secret))
	if err != nil {
		return nil, err
	}

	// Refresh Token
	refreshClaims := Claims{
		UserID:    userID,
		Phone:     phone,
		Type:      "refresh",
		DeviceID:  deviceID,
		SessionID: sessionID,
		RegisteredClaims: jwtgo.RegisteredClaims{
			ExpiresAt: jwtgo.NewNumericDate(now.Add(refreshTTL)),
			IssuedAt:  jwtgo.NewNumericDate(now),
			Issuer:    "xiaoyanquan",
		},
	}
	refreshToken, err := jwtgo.NewWithClaims(jwtgo.SigningMethodHS256, refreshClaims).
		SignedString([]byte(secret))
	if err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int64(accessTTL.Seconds()),
	}, nil
}

// GenerateAdminToken 生成管理员 access token
func GenerateAdminToken(secret string, adminID uint, username, role string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID: adminID,
		Phone:  username, // 复用 Phone 字段存 username
		Type:   "admin_access",
		RegisteredClaims: jwtgo.RegisteredClaims{
			ExpiresAt: jwtgo.NewNumericDate(now.Add(ttl)),
			IssuedAt:  jwtgo.NewNumericDate(now),
			Issuer:    "xiaoyanquan-admin",
			Subject:   role,
		},
	}
	return jwtgo.NewWithClaims(jwtgo.SigningMethodHS256, claims).SignedString([]byte(secret))
}

// ParseToken 解析并验证 token
func ParseToken(secret, tokenStr string) (*Claims, error) {
	token, err := jwtgo.ParseWithClaims(tokenStr, &Claims{}, func(t *jwtgo.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil {
		if errors.Is(err, jwtgo.ErrTokenExpired) {
			return nil, ErrTokenExpired
		}
		return nil, ErrTokenInvalid
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrTokenInvalid
	}
	return claims, nil
}

func newSessionID() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
