package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Server   ServerConfig
	CORS     CORSConfig
	Database DatabaseConfig
	Redis    RedisConfig
	JWT      JWTConfig
	SMS      SMSConfig
	Storage  StorageConfig
}

type ServerConfig struct {
	Port         string
	Mode         string // debug, release
	BaseURL      string // 对外访问地址，用于拼接完整 URL
	AdminBaseURL string // 后台访问地址
}

type CORSConfig struct {
	AllowOrigins []string
}

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

type RedisConfig struct {
	Addr     string
	Password string
	DB       int
}

type JWTConfig struct {
	Secret          string
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
}

type SMSConfig struct {
	Provider     string // aliyun, tencent
	AccessKeyID  string
	AccessSecret string
	SignName     string
	TemplateCode string
}

type StorageConfig struct {
	COSEnabled  bool
	COSSecretID string
	COSSecretKey string
	COSBucket   string
	COSRegion   string
	COSCDNDomain string
}

func Load() *Config {
	return &Config{
		Server: ServerConfig{
			Port:         getEnv("SERVER_PORT", "8080"),
			Mode:         getEnv("SERVER_MODE", "debug"),
			BaseURL:      getEnv("SERVER_BASE_URL", "http://localhost:8080"),
			AdminBaseURL: getEnv("ADMIN_BASE_URL", "https://xyqad.cfqfwl.cn"),
		},
		CORS: CORSConfig{
			AllowOrigins: parseCSV(
				getEnv("CORS_ALLOW_ORIGINS", "http://localhost:5173,http://localhost:3000,https://xyqad.cfqfwl.cn"),
			),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", ""),
			DBName:   getEnv("DB_NAME", "xiaoyanquan"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		Redis: RedisConfig{
			Addr:     getEnv("REDIS_ADDR", "localhost:6379"),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getEnvInt("REDIS_DB", 0),
		},
		JWT: JWTConfig{
			Secret:          getEnv("JWT_SECRET", "please-set-jwt-secret"),
			AccessTokenTTL:  time.Duration(getEnvInt("JWT_ACCESS_TTL_HOURS", 2)) * time.Hour,
			RefreshTokenTTL: time.Duration(getEnvInt("JWT_REFRESH_TTL_DAYS", 30)) * 24 * time.Hour,
		},
		SMS: SMSConfig{
			Provider:     getEnv("SMS_PROVIDER", "aliyun"),
			AccessKeyID:  getEnv("SMS_ACCESS_KEY_ID", ""),
			AccessSecret: getEnv("SMS_ACCESS_SECRET", ""),
			SignName:     getEnv("SMS_SIGN_NAME", "小颜圈"),
			TemplateCode: getEnv("SMS_TEMPLATE_CODE", ""),
		},
		Storage: StorageConfig{
			COSEnabled:   getEnv("COS_ENABLED", "false") == "true",
			COSSecretID:  getEnv("COS_SECRET_ID", ""),
			COSSecretKey: getEnv("COS_SECRET_KEY", ""),
			COSBucket:    getEnv("COS_BUCKET", ""),
			COSRegion:    getEnv("COS_REGION", "ap-guangzhou"),
			COSCDNDomain: getEnv("COS_CDN_DOMAIN", ""),
		},
	}
}

func (c *DatabaseConfig) DSN() string {
	return "host=" + c.Host +
		" port=" + c.Port +
		" user=" + c.User +
		" password=" + c.Password +
		" dbname=" + c.DBName +
		" sslmode=" + c.SSLMode
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return defaultVal
}

func parseCSV(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		v := strings.TrimSpace(p)
		if v != "" {
			out = append(out, v)
		}
	}
	return out
}
