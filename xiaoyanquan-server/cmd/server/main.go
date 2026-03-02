package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
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
		&model.Material{},
		&model.Category{},
		&model.Moment{},
		&model.Favorite{},
		&model.Download{},
		&model.Question{},
		&model.Order{},
		&model.UserBehavior{},
		&model.SystemConfig{},
		&model.Admin{},
		&model.Asset{},
	)
}

// seedData 初始化种子数据（分类 + 系统配置）
func seedData(db *gorm.DB) {

	// 初始化系统配置
	configs := []model.SystemConfig{
		{Key: "pro_monthly_download_limit", Value: "5000", Description: "专业版每月下载次数"},
		{Key: "flagship_monthly_download_limit", Value: "10000", Description: "旗舰版每月下载次数"},
		{Key: "pro_monthly_price", Value: "299", Description: "专业版月费(元)"},
		{Key: "flagship_monthly_price", Value: "499", Description: "旗舰版月费(元)"},
		{Key: "sms_daily_limit", Value: "5", Description: "每日单号码短信上限"},
		{Key: "sms_code_ttl_minutes", Value: "5", Description: "验证码有效期(分钟)"},
	}
	for _, c := range configs {
		db.Where("key = ?", c.Key).FirstOrCreate(&c)
	}

	log.Println("种子数据初始化完成")
}
