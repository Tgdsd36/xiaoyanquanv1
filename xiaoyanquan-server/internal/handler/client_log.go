package handler

import (
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type clientLogRequest struct {
	Tag     string `json:"tag"`
	Message string `json:"message"`
}

// ClientLog 接收客户端上报的调试日志，写入 server.log
func ClientLog(c *gin.Context) {
	var req clientLogRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "invalid body"})
		return
	}
	if req.Tag == "" {
		req.Tag = "client"
	}
	log.Printf("[CLIENT-LOG] %s | tag=%s | %s", time.Now().Format("2006-01-02 15:04:05"), req.Tag, req.Message)
	c.JSON(http.StatusOK, gin.H{"code": 0})
}
