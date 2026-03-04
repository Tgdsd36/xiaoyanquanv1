package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
	JWT      JWTConfig
	SMS      SMSConfig
	OSS      OSSConfig
}

type ServerConfig struct {
	Port    string
	Mode    string // debug, release
	BaseURL string // 对外访问地址，用于拼接完整 URL
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
	Secret           string
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
}

type SMSConfig struct {
	Provider    string // aliyun, tencent
	AccessKeyID string
	AccessSecret string
	SignName     string
	TemplateCode string
}

type OSSConfig struct {
	Provider        string // aliyun, aws
	Endpoint        string
	AccessKeyID     string
	AccessKeySecret string
	BucketName      string
	CDNDomain       string
}

func Load() *Config {
	return &Config{
		Server: ServerConfig{
			Port:    getEnv("SERVER_PORT", "8080"),
			Mode:    getEnv("SERVER_MODE", "debug"),
			BaseURL: getEnv("SERVER_BASE_URL", "http://localhost:8080"),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", "qwe10086"),
			DBName:   getEnv("DB_NAME", "xiaoyanquan"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		Redis: RedisConfig{
			Addr:     getEnv("REDIS_ADDR", "localhost:6379"),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getEnvInt("REDIS_DB", 0),
		},
		JWT: JWTConfig{
			Secret:          getEnv("JWT_SECRET", "xiaoyanquan-jwt-secret-change-me"),
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
		OSS: OSSConfig{
			Provider:        getEnv("OSS_PROVIDER", "aliyun"),
			Endpoint:        getEnv("OSS_ENDPOINT", ""),
			AccessKeyID:     getEnv("OSS_ACCESS_KEY_ID", ""),
			AccessKeySecret: getEnv("OSS_ACCESS_KEY_SECRET", ""),
			BucketName:      getEnv("OSS_BUCKET_NAME", "xiaoyanquan"),
			CDNDomain:       getEnv("OSS_CDN_DOMAIN", ""),
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
