package storage

import (
	"io"
	"os"
	"path/filepath"
)

// LocalStorage 本地文件系统存储
type LocalStorage struct {
	// BaseDir 本地文件根目录，如 "./static/uploads"
	BaseDir string
}

func NewLocalStorage(baseDir string) *LocalStorage {
	return &LocalStorage{BaseDir: baseDir}
}

func (s *LocalStorage) Upload(key string, reader io.Reader, size int64) error {
	dstPath := filepath.Join(s.BaseDir, key)
	if err := os.MkdirAll(filepath.Dir(dstPath), 0755); err != nil {
		return err
	}
	f, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, reader)
	return err
}

func (s *LocalStorage) Delete(key string) error {
	return os.Remove(filepath.Join(s.BaseDir, key))
}

// PublicURL 返回相对路径，由 fullURL 拼接 BaseURL
func (s *LocalStorage) PublicURL(key string) string {
	return "/static/uploads/" + key
}

func (s *LocalStorage) Enabled() bool {
	return false
}
