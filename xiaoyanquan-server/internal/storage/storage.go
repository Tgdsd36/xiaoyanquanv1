package storage

import "io"

// Storage 文件存储抽象接口
type Storage interface {
	// Upload 上传文件到存储后端
	// key 格式：assets/2026/03/uuid.ext 或 user/2026/03/uuid.ext
	Upload(key string, reader io.Reader, size int64) error

	// Delete 删除存储后端的文件
	Delete(key string) error

	// PublicURL 返回文件的公网访问 URL
	PublicURL(key string) string

	// Enabled 是否为云存储模式（COS）
	Enabled() bool
}
