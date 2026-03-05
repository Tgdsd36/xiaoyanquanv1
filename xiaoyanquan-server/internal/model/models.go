package model

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"time"

	"github.com/lib/pq"
	"gorm.io/gorm"
)

// ==================== 用户 ====================

type User struct {
	ID                   uint           `gorm:"primaryKey" json:"id"`
	Phone                string         `gorm:"uniqueIndex;size:20;not null" json:"phone"`
	PasswordHash         string         `gorm:"size:255" json:"-"`
	Nickname             string         `gorm:"size:50" json:"nickname"`
	AvatarURL            string         `gorm:"size:500" json:"avatar_url"`
	CoverURL             string         `gorm:"size:500" json:"cover_url"`
	Status               string         `gorm:"size:20;default:active" json:"status"`    // active, disabled
	MemberType           string         `gorm:"size:20;default:free" json:"member_type"` // free, pro, flagship
	MemberExpireAt       *time.Time     `json:"member_expire_at"`
	MonthlyDownloadCount int            `gorm:"default:0" json:"monthly_download_count"`
	DownloadCountResetAt *time.Time     `json:"download_count_reset_at"`
	CreatedAt            time.Time      `json:"created_at"`
	UpdatedAt            time.Time      `json:"updated_at"`
	DeletedAt            gorm.DeletedAt `gorm:"index" json:"-"`
}

// ==================== 用户设备绑定 ====================

type UserDeviceBinding struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"uniqueIndex;not null" json:"user_id"`
	DeviceID   string    `gorm:"size:128;not null;index" json:"device_id"`
	DeviceName string    `gorm:"size:120" json:"device_name"`
	Platform   string    `gorm:"size:40" json:"platform"`
	BoundAt    time.Time `json:"bound_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

func (UserDeviceBinding) TableName() string { return "user_device_bindings" }

func (u *User) IsMember() bool {
	if u.MemberType == "free" || u.MemberType == "" {
		return false
	}
	if u.MemberExpireAt != nil && u.MemberExpireAt.Before(time.Now()) {
		return false
	}
	return true
}

func (u *User) MaskedPhone() string {
	if len(u.Phone) >= 11 {
		return u.Phone[:3] + "****" + u.Phone[7:]
	}
	return u.Phone
}

// ==================== 素材 ====================

type Material struct {
	ID              uint           `gorm:"primaryKey" json:"id"`
	Title           string         `gorm:"size:200;not null" json:"title"`
	Description     string         `gorm:"type:text" json:"description"`
	Type            string         `gorm:"size:20;not null;index" json:"type"` // image, video, live_photo
	CategoryID      *uint          `gorm:"index" json:"category_id"`
	Category        *Category      `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
	Gender          string         `gorm:"size:10;default:''" json:"gender"` // male, female, ""(不限)
	Tags            pq.StringArray `gorm:"type:text[]" json:"tags"`
	Width           int            `json:"width"`
	Height          int            `json:"height"`
	Duration        float64        `json:"duration"` // 秒，仅视频
	FileSize        int64          `json:"file_size"`
	OriginalURLs    JSON           `gorm:"type:jsonb" json:"original_urls"`
	ThumbnailURL    string         `gorm:"size:500" json:"thumbnail_url"`
	WatermarkURL    string         `gorm:"size:500" json:"watermark_url"`
	PreviewMovURL   string         `gorm:"size:500" json:"preview_mov_url"`             // Live Photo
	ShowInspiration bool           `gorm:"default:false;index" json:"show_inspiration"` // 是否投放到找灵感
	ShowMoments     bool           `gorm:"default:false;index" json:"show_moments"`     // 是否投放到朋友圈
	HotScore        float64        `gorm:"index;default:0" json:"hot_score"`
	DownloadCount   int            `gorm:"default:0" json:"download_count"`
	FavoriteCount   int            `gorm:"default:0" json:"favorite_count"`
	ViewCount       int            `gorm:"default:0" json:"view_count"`
	Status          string         `gorm:"size:20;default:draft;index" json:"status"` // draft, published, offline
	CreatedAt       time.Time      `gorm:"index" json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
}

func (m *Material) FileSizeText() string {
	size := float64(m.FileSize)
	switch {
	case size >= 1<<30:
		return fmt.Sprintf("%.1fGB", size/(1<<30))
	case size >= 1<<20:
		return fmt.Sprintf("%.1fMB", size/(1<<20))
	case size >= 1<<10:
		return fmt.Sprintf("%.1fKB", size/(1<<10))
	default:
		return fmt.Sprintf("%dB", m.FileSize)
	}
}

// ==================== 分类 ====================

type Category struct {
	ID        uint       `gorm:"primaryKey" json:"id"`
	ParentID  *uint      `gorm:"index" json:"parent_id"`
	Parent    *Category  `gorm:"foreignKey:ParentID" json:"-"`
	Children  []Category `gorm:"foreignKey:ParentID" json:"children,omitempty"`
	Name      string     `gorm:"size:50;not null" json:"name"`
	Slug      string     `gorm:"size:50;uniqueIndex" json:"slug"`
	SortOrder int        `gorm:"default:0" json:"sort_order"`
	IsVisible bool       `gorm:"default:true" json:"is_visible"`
	CreatedAt time.Time  `json:"created_at"`
}

// ==================== 收藏分组 ====================

type FavoriteGroup struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"index;not null" json:"user_id"`
	Name      string    `gorm:"size:100;not null" json:"name"`
	IsDefault bool      `gorm:"default:false" json:"is_default"`
	SortOrder int       `gorm:"default:0" json:"sort_order"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (FavoriteGroup) TableName() string { return "favorite_groups" }

// ==================== 收藏 ====================

type Favorite struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"index;not null" json:"user_id"`
	GroupID    uint      `gorm:"index;not null;default:0" json:"group_id"`
	TargetType string    `gorm:"size:20;not null" json:"target_type"` // material
	TargetID   uint      `gorm:"not null" json:"target_id"`
	CreatedAt  time.Time `json:"created_at"`
}

func (Favorite) TableName() string { return "favorites" }

// ==================== 下载记录 ====================

type Download struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	UserID       uint      `gorm:"index;not null" json:"user_id"`
	MaterialID   uint      `gorm:"index;not null" json:"material_id"`
	DownloadedAt time.Time `json:"downloaded_at"`
}

// ==================== 提问 ====================

type Question struct {
	ID           uint       `gorm:"primaryKey" json:"id"`
	UserID       uint       `gorm:"index;not null" json:"user_id"`
	User         *User      `gorm:"foreignKey:UserID" json:"user,omitempty"`
	TargetType   string     `gorm:"size:20;not null" json:"target_type"` // material, moment
	TargetID     uint       `gorm:"index;not null" json:"target_id"`
	QuestionText string     `gorm:"type:text;not null" json:"question_text"`
	ReplyText    string     `gorm:"type:text" json:"reply_text"`
	RepliedBy    *uint      `json:"replied_by"`
	RepliedAt    *time.Time `json:"replied_at"`
	Status       string     `gorm:"size:20;default:pending" json:"status"` // pending, replied
	CreatedAt    time.Time  `gorm:"index" json:"created_at"`
}

// ==================== 订单 ====================

type Order struct {
	ID             uint      `gorm:"primaryKey" json:"id"`
	UserID         uint      `gorm:"index;not null" json:"user_id"`
	PlanType       string    `gorm:"size:30;not null" json:"plan_type"` // pro_monthly, flagship_monthly
	Amount         float64   `gorm:"type:decimal(10,2)" json:"amount"`
	PaymentChannel string    `gorm:"size:20" json:"payment_channel"` // apple_iap, wechat, alipay
	TransactionID  string    `gorm:"size:200" json:"transaction_id"`
	Status         string    `gorm:"size:20;default:pending" json:"status"` // pending, paid, failed, refunded
	CreatedAt      time.Time `gorm:"index" json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// ==================== 用户行为 ====================

type UserBehavior struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"index;not null" json:"user_id"`
	MaterialID uint      `gorm:"index;not null" json:"material_id"`
	Action     string    `gorm:"size:20;not null" json:"action"` // view, like, dislike, download
	CreatedAt  time.Time `gorm:"index" json:"created_at"`
}

// ==================== 系统配置 ====================

type SystemConfig struct {
	Key         string `gorm:"primaryKey;size:100" json:"key"`
	Value       string `gorm:"type:text" json:"value"`
	Description string `gorm:"size:200" json:"description"`
}

// ==================== 管理员 ====================

type Admin struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Username     string    `gorm:"uniqueIndex;size:50;not null" json:"username"`
	PasswordHash string    `gorm:"size:255;not null" json:"-"`
	Role         string    `gorm:"size:20;default:editor" json:"role"` // admin, editor
	CreatedAt    time.Time `json:"created_at"`
}

// ==================== 素材库(文件管理) ====================

type Asset struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Filename     string    `gorm:"size:255;not null" json:"filename"`
	OriginalName string    `gorm:"size:255" json:"original_name"`
	URL          string    `gorm:"size:500;not null" json:"url"`
	PreviewURL   string    `gorm:"size:500" json:"preview_url"`             // 预览图（如 HEIC 转 JPG）
	FileType     string    `gorm:"size:20;not null;index" json:"file_type"` // image, video
	Folder       string    `gorm:"size:100;index;default:''" json:"folder"` // 分类文件夹
	FileSize     int64     `json:"file_size"`
	Width        int       `json:"width"`
	Height       int       `json:"height"`
	CreatedAt    time.Time `gorm:"index" json:"created_at"`
}

type LiveAssetPack struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Folder       string    `gorm:"size:100;index;default:''" json:"folder"`
	BaseName     string    `gorm:"size:255;index;not null" json:"base_name"`
	ImageAssetID *uint     `gorm:"index" json:"image_asset_id"`
	VideoAssetID *uint     `gorm:"index" json:"video_asset_id"`
	Status       string    `gorm:"size:20;index;default:incomplete" json:"status"` // complete, incomplete
	CreatedAt    time.Time `gorm:"index" json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

func (LiveAssetPack) TableName() string { return "live_asset_packs" }

type AssetFolder struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Name      string    `gorm:"size:100;uniqueIndex;not null" json:"name"`
	CreatedAt time.Time `gorm:"index" json:"created_at"`
}

func (AssetFolder) TableName() string { return "asset_folders" }

// ==================== JSONB 类型支持 ====================

type JSON json.RawMessage

func (j JSON) Value() (driver.Value, error) {
	if len(j) == 0 {
		return nil, nil
	}
	return string(j), nil
}

func (j *JSON) Scan(value interface{}) error {
	if value == nil {
		*j = JSON("null")
		return nil
	}
	switch v := value.(type) {
	case []byte:
		*j = append((*j)[0:0], v...)
	case string:
		*j = JSON(v)
	default:
		return fmt.Errorf("unsupported type: %T", value)
	}
	return nil
}

func (j JSON) MarshalJSON() ([]byte, error) {
	if len(j) == 0 {
		return []byte("null"), nil
	}
	return j, nil
}

func (j *JSON) UnmarshalJSON(data []byte) error {
	if j == nil {
		return fmt.Errorf("JSON: UnmarshalJSON on nil pointer")
	}
	*j = append((*j)[0:0], data...)
	return nil
}
