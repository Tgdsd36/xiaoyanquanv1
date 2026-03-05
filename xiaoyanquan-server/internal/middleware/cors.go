package middleware

import (
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"

	"github.com/xiaoyanquan/server/internal/config"
)

func CORS(cfg *config.Config) gin.HandlerFunc {
	origins := []string{"*"}
	if cfg != nil && len(cfg.CORS.AllowOrigins) > 0 {
		origins = cfg.CORS.AllowOrigins
	}

	allowAll := len(origins) == 1 && origins[0] == "*"

	return cors.New(cors.Config{
		AllowOrigins:     origins,
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: !allowAll,
		AllowAllOrigins:  allowAll,
		MaxAge:           12 * time.Hour,
	})
}
