package storage

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/tencentyun/cos-go-sdk-v5"
)

// COSStorage 腾讯云 COS 对象存储
type COSStorage struct {
	client    *cos.Client
	cdnDomain string // 可选 CDN 域名，为空时用 COS 默认域名
	cosURL    string // COS 默认域名，如 https://bucket.cos.region.myqcloud.com
}

// COSConfig COS 初始化配置
type COSConfig struct {
	SecretID  string
	SecretKey string
	Bucket    string
	Region    string
	CDNDomain string // 可选
}

func NewCOSStorage(cfg COSConfig) (*COSStorage, error) {
	cosURL := fmt.Sprintf("https://%s.cos.%s.myqcloud.com", cfg.Bucket, cfg.Region)
	u, err := url.Parse(cosURL)
	if err != nil {
		return nil, fmt.Errorf("解析 COS URL 失败: %w", err)
	}

	client := cos.NewClient(&cos.BaseURL{BucketURL: u}, &http.Client{
		Transport: &cos.AuthorizationTransport{
			SecretID:  cfg.SecretID,
			SecretKey: cfg.SecretKey,
		},
	})

	cdnDomain := strings.TrimRight(cfg.CDNDomain, "/")

	return &COSStorage{
		client:    client,
		cdnDomain: cdnDomain,
		cosURL:    cosURL,
	}, nil
}

func (s *COSStorage) Upload(key string, reader io.Reader, size int64) error {
	opt := &cos.ObjectPutOptions{
		ObjectPutHeaderOptions: &cos.ObjectPutHeaderOptions{
			ContentLength: size,
		},
	}
	_, err := s.client.Object.Put(context.Background(), key, reader, opt)
	return err
}

func (s *COSStorage) Delete(key string) error {
	_, err := s.client.Object.Delete(context.Background(), key)
	return err
}

// PublicURL 返回公网访问 URL
// 优先使用 CDN 域名，否则使用 COS 默认域名
func (s *COSStorage) PublicURL(key string) string {
	base := s.cosURL
	if s.cdnDomain != "" {
		base = s.cdnDomain
	}
	return base + "/" + key
}

func (s *COSStorage) Enabled() bool {
	return true
}
