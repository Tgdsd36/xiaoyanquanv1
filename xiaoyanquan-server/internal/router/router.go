package router

import (
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/config"
	"github.com/xiaoyanquan/server/internal/handler"
	"github.com/xiaoyanquan/server/internal/middleware"
)

func Setup(cfg *config.Config, db *gorm.DB, rdb *redis.Client) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.Default()
	r.Use(middleware.CORS())

	// 初始化 handlers
	authHandler := &handler.AuthHandler{DB: db, RDB: rdb, Cfg: cfg}
	categoryHandler := &handler.CategoryHandler{DB: db}
	materialHandler := &handler.MaterialHandler{DB: db}
	inspirationHandler := &handler.InspirationHandler{DB: db}
	momentHandler := &handler.MomentHandler{DB: db}
	favoriteHandler := &handler.FavoriteHandler{DB: db}
	questionHandler := &handler.QuestionHandler{DB: db}
	userHandler := &handler.UserHandler{DB: db}
	membershipHandler := &handler.MembershipHandler{DB: db}

	// 公共 API
	v1 := r.Group("/api/v1")
	{
		// 认证（无需登录）
		auth := v1.Group("/auth")
		{
			auth.POST("/sms/send", authHandler.SendSMS)
			auth.POST("/sms/login", authHandler.SMSLogin)
			auth.POST("/login", authHandler.Login)
			auth.POST("/register", authHandler.Register)
			auth.POST("/refresh", authHandler.Refresh)
		}

		// 认证（需登录）
		authRequired := v1.Group("/auth")
		authRequired.Use(middleware.AuthRequired(&cfg.JWT))
		{
			authRequired.DELETE("/account", authHandler.DeleteAccount)
		}

		// 分类（游客可访问）
		v1.GET("/categories", categoryHandler.List)

		// 素材（游客可浏览，登录用户有 is_favorited 状态）
		materials := v1.Group("/materials")
		materials.Use(middleware.AuthOptional(&cfg.JWT))
		{
			materials.GET("", materialHandler.List)
			materials.GET("/:id", materialHandler.Detail)
			materials.GET("/search", materialHandler.Search)
		}

		// 素材下载（需会员）
		materialsAuth := v1.Group("/materials")
		materialsAuth.Use(middleware.AuthRequired(&cfg.JWT))
		{
			materialsAuth.GET("/:id/download", materialHandler.Download)
		}

		// 找灵感（游客可浏览）
		inspiration := v1.Group("/inspiration")
		inspiration.Use(middleware.AuthOptional(&cfg.JWT))
		{
			inspiration.GET("/feed", inspirationHandler.Feed)
		}
		v1.POST("/inspiration/dislike", middleware.AuthRequired(&cfg.JWT), inspirationHandler.Dislike)

		// 朋友圈（游客可浏览）
		moments := v1.Group("/moments")
		moments.Use(middleware.AuthOptional(&cfg.JWT))
		{
			moments.GET("", momentHandler.List)
			moments.GET("/:id", momentHandler.Detail)
			moments.GET("/:id/questions", momentHandler.Questions)
		}

		// 收藏（需会员）
		favorites := v1.Group("/favorites")
		favorites.Use(middleware.AuthRequired(&cfg.JWT))
		{
			favorites.POST("", favoriteHandler.Create)
			favorites.DELETE("/:id", favoriteHandler.Delete)
			favorites.GET("", favoriteHandler.List)
		}

		// 提问（需会员）
		questions := v1.Group("/questions")
		questions.Use(middleware.AuthRequired(&cfg.JWT))
		{
			questions.POST("", questionHandler.Create)
			questions.GET("", questionHandler.MyList)
		}
		// 公开提问列表
		v1.GET("/questions/material/:id", questionHandler.PublicList)

		// 用户（需登录）
		user := v1.Group("/user")
		user.Use(middleware.AuthRequired(&cfg.JWT))
		{
			user.GET("/profile", userHandler.Profile)
			user.PUT("/profile", userHandler.UpdateProfile)
			user.GET("/downloads", userHandler.Downloads)
			user.PUT("/password", userHandler.ChangePassword)
		}

		// 会员（需登录）
		membership := v1.Group("/membership")
		membership.Use(middleware.AuthRequired(&cfg.JWT))
		{
			membership.GET("/status", membershipHandler.Status)
			membership.POST("/purchase", membershipHandler.Purchase)
		}
	}

	// ==================== 管理后台 API ====================
	adminHandler := &handler.AdminHandler{DB: db, Cfg: cfg}

	adminGroup := r.Group("/api/admin")
	{
		// 无需认证
		adminGroup.POST("/login", adminHandler.Login)
		adminGroup.GET("/init", adminHandler.InitAdmin) // 开发环境初始化

		// 需管理员认证
		adminAuth := adminGroup.Group("")
		adminAuth.Use(middleware.AdminRequired(&cfg.JWT))
		{
			// Dashboard
			adminAuth.GET("/dashboard", adminHandler.Dashboard)

			// 素材管理
			adminAuth.GET("/materials", adminHandler.MaterialList)
			adminAuth.POST("/materials", adminHandler.MaterialCreate)
			adminAuth.PUT("/materials/:id", adminHandler.MaterialUpdate)
			adminAuth.DELETE("/materials/:id", adminHandler.MaterialDelete)
			adminAuth.POST("/materials/batch-status", adminHandler.MaterialBatchStatus)
			adminAuth.POST("/materials/batch-delete", adminHandler.MaterialBatchDelete)

			// 分类管理
			adminAuth.GET("/categories", adminHandler.CategoryList)
			adminAuth.POST("/categories", adminHandler.CategoryCreate)
			adminAuth.PUT("/categories/:id", adminHandler.CategoryUpdate)
			adminAuth.DELETE("/categories/:id", adminHandler.CategoryDelete)
			adminAuth.POST("/categories/sort", adminHandler.CategorySort)
			adminAuth.POST("/categories/batch-delete", adminHandler.CategoryBatchDelete)

			// 动态管理
			adminAuth.GET("/moments", adminHandler.MomentList)
			adminAuth.POST("/moments", adminHandler.MomentCreate)
			adminAuth.PUT("/moments/:id", adminHandler.MomentUpdate)
			adminAuth.DELETE("/moments/:id", adminHandler.MomentDelete)
			adminAuth.POST("/moments/batch-delete", adminHandler.MomentBatchDelete)
			adminAuth.POST("/moments/batch-status", adminHandler.MomentBatchStatus)

			// 提问管理
			adminAuth.GET("/questions", adminHandler.QuestionList)
			adminAuth.PUT("/questions/:id/reply", adminHandler.QuestionReply)

			// 用户管理
			adminAuth.GET("/users", adminHandler.UserList)
			adminAuth.GET("/users/:id", adminHandler.UserDetail)
			adminAuth.POST("/users", adminHandler.UserCreate)
			adminAuth.DELETE("/users/:id", adminHandler.UserDelete)
			adminAuth.POST("/users/batch-delete", adminHandler.UserBatchDelete)
			adminAuth.POST("/users/batch-status", adminHandler.UserBatchStatus)
			adminAuth.PUT("/users/:id/status", adminHandler.UserToggleStatus)

			// 素材库(文件管理)
			adminAuth.POST("/assets/upload", adminHandler.AssetUpload)
			adminAuth.GET("/assets", adminHandler.AssetList)
			adminAuth.DELETE("/assets/:id", adminHandler.AssetDelete)
			adminAuth.GET("/assets/folders", adminHandler.AssetFolders)
			adminAuth.PUT("/assets/folders/rename", adminHandler.AssetFolderRename)
			adminAuth.POST("/assets/folders/delete", adminHandler.AssetFolderDelete)

			// 订单管理
			adminAuth.GET("/orders", adminHandler.OrderList)

			// 系统配置
			adminAuth.GET("/configs", adminHandler.ConfigList)
			adminAuth.PUT("/configs", adminHandler.ConfigUpdate)
		}
	}

	// 分享页（网页端打开时尝试打开 App，否则跳转下载页）
	r.GET("/share/material/:id", func(c *gin.Context) {
		id := c.Param("id")
		c.Data(200, "text/html; charset=utf-8", []byte(
			`<!DOCTYPE html><html><head><meta charset="utf-8"><title>小颜圈</title>`+
				`<meta http-equiv="refresh" content="0;url=xiaoyanquan://material/`+id+`">`+
				`</head><body><p>正在打开小颜圈...</p></body></html>`,
		))
	})
	r.GET("/share/moment/:id", func(c *gin.Context) {
		id := c.Param("id")
		c.Data(200, "text/html; charset=utf-8", []byte(
			`<!DOCTYPE html><html><head><meta charset="utf-8"><title>小颜圈</title>`+
				`<meta http-equiv="refresh" content="0;url=xiaoyanquan://moment/`+id+`">`+
				`</head><body><p>正在打开小颜圈...</p></body></html>`,
		))
	})

	// 静态文件服务（素材库上传文件）
	r.Static("/static", "./static")

	// 健康检查
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	return r
}
