package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/xiaoyanquan/server/internal/config"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/internal/router"
)

func main() {
	config.LoadEnvFiles()
	cfg := config.Load()

	// 数据库连接
	db, err := initDB(cfg)
	if err != nil {
		log.Fatalf("数据库连接失败: %v", err)
	}

	// 自动迁移
	if err := autoMigrate(db); err != nil {
		log.Fatalf("数据库迁移失败: %v", err)
	}

	// 数据迁移：删除废弃的 gender_category_id 列
	migrateGenderField(db)

	// 数据迁移：收藏分组（为旧收藏记录创建默认分组）
	migrateFavoriteGroups(db)

	// 数据迁移：将已关联 Live Pack 的 .mov 资产从 video 修正为 live_video
	migrateLiveVideoFileType(db)

	// 数据迁移：为 live_photo 素材补全 original_urls 中缺失的视频 URL
	migrateLivePhotoOriginalURLs(db, cfg)

	// 数据迁移：为已有视频资产生成首帧缩略图，修正素材 thumbnail_url
	migrateVideoThumbnails(db, cfg)

	// 初始化种子数据
	seedData(db)

	// Redis 连接
	rdb := initRedis(cfg)

	// 路由
	r := router.Setup(cfg, db, rdb)

	// 启动服务
	srv := &http.Server{
		Addr:    ":" + cfg.Server.Port,
		Handler: r,
	}

	go func() {
		log.Printf("小颜圈服务启动 http://localhost:%s", cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("服务启动失败: %v", err)
		}
	}()

	// 优雅关闭
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("正在关闭服务...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("服务关闭异常:", err)
	}
	log.Println("服务已停止")
}

func ensureDatabase(cfg *config.Config) {
	// 先连接默认 postgres 库，检查目标库是否存在
	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=postgres sslmode=%s",
		cfg.Database.Host, cfg.Database.Port, cfg.Database.User, cfg.Database.Password, cfg.Database.SSLMode)
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{Logger: logger.Default.LogMode(logger.Silent)})
	if err != nil {
		return
	}
	var count int64
	db.Raw("SELECT count(*) FROM pg_database WHERE datname = ?", cfg.Database.DBName).Scan(&count)
	if count == 0 {
		db.Exec("CREATE DATABASE " + cfg.Database.DBName)
		log.Printf("数据库 %s 已自动创建", cfg.Database.DBName)
	}
	sqlDB, _ := db.DB()
	sqlDB.Close()
}

func initDB(cfg *config.Config) (*gorm.DB, error) {
	// 自动创建数据库（如果不存在）
	ensureDatabase(cfg)

	var logLevel logger.LogLevel
	if cfg.Server.Mode == "debug" {
		logLevel = logger.Info
	} else {
		logLevel = logger.Silent
	}

	db, err := gorm.Open(postgres.Open(cfg.Database.DSN()), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
	if err != nil {
		return nil, fmt.Errorf("连接数据库失败: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	return db, nil
}

func initRedis(cfg *config.Config) *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.Redis.Addr,
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})

	ctx := context.Background()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Printf("Redis 连接失败: %v （验证码等功能将不可用）", err)
	} else {
		log.Println("Redis 连接成功")
	}

	return rdb
}

func autoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&model.User{},
		&model.UserDeviceBinding{},
		&model.Material{},
		&model.Category{},
		&model.FavoriteGroup{},
		&model.Favorite{},
		&model.Download{},
		&model.Question{},
		&model.Order{},
		&model.UserBehavior{},
		&model.SystemConfig{},
		&model.Admin{},
		&model.Asset{},
		&model.LiveAssetPack{},
		&model.AssetFolder{},
	)
}

// migrateGenderField 将旧的 gender_category_id 迁移到 gender 字符串字段
func migrateGenderField(db *gorm.DB) {
	if db.Migrator().HasColumn(&model.Material{}, "gender_category_id") {
		// 将已有数据迁移到新字段
		db.Exec(`UPDATE materials SET gender = 'male' WHERE gender_category_id IN (SELECT id FROM categories WHERE slug = 'male')`)
		db.Exec(`UPDATE materials SET gender = 'female' WHERE gender_category_id IN (SELECT id FROM categories WHERE slug = 'female')`)
		// 删除旧列
		db.Migrator().DropColumn(&model.Material{}, "gender_category_id")
		log.Println("已迁移 gender_category_id -> gender")
	}
}

// migrateFavoriteGroups 为已有收藏记录的用户创建默认分组，并将 group_id=0 的记录迁移到默认分组
func migrateFavoriteGroups(db *gorm.DB) {
	// 检查是否有 group_id=0 的收藏记录需要迁移
	var count int64
	db.Model(&model.Favorite{}).Where("group_id = 0").Count(&count)
	if count == 0 {
		return
	}

	log.Printf("发现 %d 条旧收藏记录需要迁移到默认分组", count)

	// 查找所有有收藏的用户 ID
	var userIDs []uint
	db.Model(&model.Favorite{}).Where("group_id = 0").Distinct("user_id").Pluck("user_id", &userIDs)

	for _, uid := range userIDs {
		// 检查该用户是否已有默认分组
		var group model.FavoriteGroup
		err := db.Where("user_id = ? AND is_default = true", uid).First(&group).Error
		if err != nil {
			// 创建默认分组
			group = model.FavoriteGroup{
				UserID:    uid,
				Name:      "默认收藏",
				IsDefault: true,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			}
			db.Create(&group)
		}
		// 将该用户的旧记录更新到默认分组
		db.Model(&model.Favorite{}).Where("user_id = ? AND group_id = 0", uid).
			Update("group_id", group.ID)
	}

	log.Printf("收藏分组迁移完成，处理 %d 个用户", len(userIDs))
}

// migrateLiveVideoFileType 将已关联到 LiveAssetPack 的 .mov 资产 file_type 从 video 修正为 live_video
func migrateLiveVideoFileType(db *gorm.DB) {
	result := db.Exec(`
		UPDATE assets SET file_type = 'live_video'
		WHERE id IN (
			SELECT video_asset_id FROM live_asset_packs WHERE video_asset_id IS NOT NULL
		)
		AND file_type = 'video'
	`)
	if result.Error == nil && result.RowsAffected > 0 {
		log.Printf("已迁移 %d 条 Live 视频资产: video -> live_video", result.RowsAffected)
	}
}

// migrateLivePhotoOriginalURLs 为 live_photo 类型素材补全 original_urls 中缺失的 .mov 视频 URL。
// 发布时可能只存了静态图地址，视频地址需要通过 live_asset_packs 反查补回。
func migrateLivePhotoOriginalURLs(db *gorm.DB, cfg *config.Config) {
	var materials []model.Material
	db.Where("type = ?", "live_photo").Find(&materials)
	if len(materials) == 0 {
		return
	}

	// 批量加载所有 complete 的 Live Pack 及其 image/video 资产
	var packs []model.LiveAssetPack
	db.Where("status = 'complete' AND image_asset_id IS NOT NULL AND video_asset_id IS NOT NULL").Find(&packs)
	if len(packs) == 0 {
		return
	}

	assetIDs := make([]uint, 0, len(packs)*2)
	for _, p := range packs {
		assetIDs = append(assetIDs, *p.ImageAssetID, *p.VideoAssetID)
	}
	var assets []model.Asset
	db.Where("id IN ?", assetIDs).Find(&assets)
	assetMap := map[uint]model.Asset{}
	for _, a := range assets {
		assetMap[a.ID] = a
	}

	// 构建 fullURL（不依赖 handler 包，自行拼接）
	cosBase := ""
	if cfg.Storage.COSEnabled && cfg.Storage.COSBucket != "" {
		if cfg.Storage.COSCDNDomain != "" {
			cosBase = strings.TrimRight(cfg.Storage.COSCDNDomain, "/")
		} else {
			cosBase = fmt.Sprintf("https://%s.cos.%s.myqcloud.com",
				cfg.Storage.COSBucket, cfg.Storage.COSRegion)
		}
	}
	baseURL := cfg.Server.BaseURL

	makeFullURL := func(p string) string {
		if p == "" {
			return ""
		}
		if len(p) > 4 && (p[:4] == "http" || p[:2] == "//") {
			return p
		}
		if strings.HasPrefix(p, "/static/") {
			return baseURL + p
		}
		if cosBase != "" {
			return cosBase + "/" + p
		}
		return baseURL + "/" + p
	}

	// 构建 imageURL -> videoURL 映射
	img2vid := map[string]string{}
	for _, p := range packs {
		imgAsset, okI := assetMap[*p.ImageAssetID]
		vidAsset, okV := assetMap[*p.VideoAssetID]
		if !okI || !okV {
			continue
		}
		imgFull := makeFullURL(imgAsset.URL)
		vidFull := makeFullURL(vidAsset.URL)
		if imgFull != "" && vidFull != "" {
			img2vid[imgFull] = vidFull
		}
	}

	updated := 0
	for _, m := range materials {
		var urls []string
		if len(m.OriginalURLs) > 0 {
			json.Unmarshal(m.OriginalURLs, &urls)
		}
		if len(urls) == 0 {
			continue
		}

		// 检查是否已有视频 URL
		hasVideo := false
		for _, u := range urls {
			if isVideoURL(u) {
				hasVideo = true
				break
			}
		}
		if hasVideo {
			continue
		}

		// 通过 img2vid 映射补全视频 URL
		videos := make([]string, 0, len(urls))
		for _, imgURL := range urls {
			if vid, ok := img2vid[imgURL]; ok {
				videos = append(videos, vid)
			}
		}
		if len(videos) == 0 {
			continue
		}

		newURLs := append(urls, videos...)
		newJSON, err := json.Marshal(newURLs)
		if err != nil {
			continue
		}
		db.Model(&model.Material{}).Where("id = ?", m.ID).
			Update("original_urls", string(newJSON))
		updated++
	}

	if updated > 0 {
		log.Printf("已为 %d 条 live_photo 素材补全视频 URL 到 original_urls", updated)
	}
}

func isVideoURL(u string) bool {
	l := strings.ToLower(u)
	for _, ext := range []string{".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi"} {
		if strings.HasSuffix(strings.SplitN(l, "?", 2)[0], ext) {
			return true
		}
	}
	return false
}

// migrateVideoThumbnails 为已有视频资产生成首帧缩略图，并修正 Material 中以视频 URL 作为 thumbnail_url 的记录
func migrateVideoThumbnails(db *gorm.DB, cfg *config.Config) {
	// Step 1: 为缺少 preview_url 的视频资产生成缩略图
	var assets []model.Asset
	db.Where("file_type IN ? AND (preview_url IS NULL OR preview_url = '')",
		[]string{"video", "live_video"}).
		Find(&assets)

	if len(assets) == 0 {
		// 没有需要处理的视频资产，检查是否有素材需要修正
		migrateFixMaterialThumbnails(db, cfg)
		return
	}

	generated := 0
	for _, asset := range assets {
		url := asset.URL
		if url == "" {
			continue
		}

		// 本地模式：文件在 static/uploads/ 下
		if strings.HasPrefix(url, "/static/") {
			sourcePath := "." + url
			ext := strings.ToLower(filepath.Ext(sourcePath))
			baseName := strings.TrimSuffix(filepath.Base(sourcePath), ext)
			thumbFilename := baseName + "_thumb.jpg"
			thumbPath := filepath.Join(filepath.Dir(sourcePath), thumbFilename)
			thumbURL := filepath.Dir(url) + "/" + thumbFilename

			// 已存在或生成成功
			if _, err := os.Stat(thumbPath); err != nil {
				// 需要生成
				if _, err := os.Stat(sourcePath); err != nil {
					continue // 源文件不存在
				}
				cmd := exec.Command("ffmpeg", "-y", "-i", sourcePath,
					"-vframes", "1", "-q:v", "2", thumbPath)
				if err := cmd.Run(); err != nil {
					continue
				}
			}

			db.Model(&model.Asset{}).Where("id = ?", asset.ID).
				Update("preview_url", thumbURL)
			generated++
		}
		// COS 模式的资产跳过（需要下载后处理，太慢）
	}

	if generated > 0 {
		log.Printf("已为 %d 个视频资产生成首帧缩略图", generated)
	}

	// Step 2: 修正素材 thumbnail_url
	migrateFixMaterialThumbnails(db, cfg)
}

// migrateFixMaterialThumbnails 将以视频 URL 作为 thumbnail_url 的素材替换为图片缩略图
func migrateFixMaterialThumbnails(db *gorm.DB, cfg *config.Config) {
	// 查找所有 type=video 的素材
	var materials []model.Material
	db.Where("type = 'video'").Find(&materials)

	// 加载所有视频资产的 URL -> preview_url 映射
	var videoAssets []model.Asset
	db.Where("file_type IN ? AND preview_url IS NOT NULL AND preview_url != ''",
		[]string{"video", "live_video"}).
		Select("url, preview_url").
		Find(&videoAssets)

	urlToPreview := map[string]string{}
	for _, a := range videoAssets {
		urlToPreview[a.URL] = a.PreviewURL
	}

	baseURL := cfg.Server.BaseURL
	updated := 0
	for _, m := range materials {
		thumbnail := m.ThumbnailURL
		if thumbnail == "" || !isVideoURL(thumbnail) {
			continue
		}

		// 尝试直接匹配
		if preview, ok := urlToPreview[thumbnail]; ok {
			db.Model(&model.Material{}).Where("id = ?", m.ID).
				Update("thumbnail_url", preview)
			updated++
			continue
		}

		// 去掉域名前缀后匹配
		clean := thumbnail
		if strings.HasPrefix(clean, baseURL) {
			clean = strings.TrimPrefix(clean, baseURL)
		}
		if preview, ok := urlToPreview[clean]; ok {
			db.Model(&model.Material{}).Where("id = ?", m.ID).
				Update("thumbnail_url", preview)
			updated++
			continue
		}

		// 按文件名模糊匹配
		baseName := filepath.Base(clean)
		if idx := strings.Index(baseName, "?"); idx >= 0 {
			baseName = baseName[:idx]
		}
		for assetURL, preview := range urlToPreview {
			if strings.HasSuffix(assetURL, baseName) {
				db.Model(&model.Material{}).Where("id = ?", m.ID).
					Update("thumbnail_url", preview)
				updated++
				break
			}
		}
	}

	if updated > 0 {
		log.Printf("已修正 %d 条视频素材的 thumbnail_url 为图片缩略图", updated)
	}
}

// seedData 初始化种子数据（系统配置）
func seedData(db *gorm.DB) {

	// 初始化系统配置
	configs := []model.SystemConfig{
		{Key: "pro_monthly_download_limit", Value: "5000", Description: "标准版每月下载次数"},
		{Key: "flagship_monthly_download_limit", Value: "10000", Description: "专业版每月下载次数"},
		{Key: "pro_monthly_price", Value: "299", Description: "标准版月费(元)"},
		{Key: "flagship_monthly_price", Value: "499", Description: "专业版月费(元)"},
		{Key: "sms_daily_limit", Value: "5", Description: "每日单号码短信上限"},
		{Key: "sms_code_ttl_minutes", Value: "5", Description: "验证码有效期(分钟)"},
	}
	for _, c := range configs {
		db.Where("key = ?", c.Key).FirstOrCreate(&c)
	}

	log.Println("种子数据初始化完成")
}
