package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

// ── Handler ────────────────────────────────────────────────────

type AICopyHandler struct {
	DB           *gorm.DB
	DoubaoAPIKey string
	DoubaoModel  string
}

// ── 请求 / 响应结构 ───────────────────────────────────────────

type AICopyReq struct {
	Style string `json:"style"` // natural | lively | literary | descriptive
}

// ── 豆包 Ark API 数据结构 ──────────────────────────────────────

type doubaoMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type doubaoReqBody struct {
	Model    string      `json:"model"`
	Messages []doubaoMsg `json:"messages"`
}

type doubaoRespBody struct {
	Choices []struct {
		Message doubaoMsg `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// ── Generate 入口 ──────────────────────────────────────────────

func (h *AICopyHandler) Generate(c *gin.Context) {
	userID := middleware.GetUserID(c)

	// 验证会员身份
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		response.ServerError(c, "用户不存在")
		return
	}
	if !user.IsMember() {
		response.Forbidden(c, "该功能仅限会员使用")
		return
	}

	// 获取素材信息
	materialID, err := strconv.Atoi(c.Param("id"))
	if err != nil || materialID <= 0 {
		response.BadRequest(c, 400, "参数错误")
		return
	}
	var material model.Material
	if err := h.DB.First(&material, materialID).Error; err != nil {
		response.NotFound(c, "素材不存在")
		return
	}

	// 解析风格参数
	var req AICopyReq
	_ = c.ShouldBindJSON(&req)
	if req.Style == "" {
		req.Style = "natural"
	}

	// 构造 prompt
	systemPrompt := "你是一位专业的朋友圈文案写手，擅长为女性用户创作吸引人的社交媒体文案。风格自然真实、有感染力，适合直接发布到微信朋友圈。"
	userPrompt := fmt.Sprintf(
		"请基于以下素材信息，生成3条【%s】风格的朋友圈文案：\n\n素材类型：%s\n参考标题：%s\n\n要求：\n1. 每条文案50字以内\n2. 适当使用emoji\n3. 贴合女性用户朋友圈发布场景\n4. 3条文案风格各有差异\n5. 直接输出3条，每条单独一行，用「1. 」「2. 」「3. 」开头，不加其他说明",
		styleDesc(req.Style),
		mediaTypeDesc(material.Type),
		material.Title,
	)

	// 调用豆包
	copies, err := h.callDoubao(systemPrompt, userPrompt)
	if err != nil {
		response.ServerError(c, "AI生成失败，请稍后重试")
		return
	}

	response.Success(c, gin.H{"copies": copies})
}

// ── 调用豆包 Ark API ───────────────────────────────────────────

func (h *AICopyHandler) callDoubao(systemPrompt, userPrompt string) ([]string, error) {
	if h.DoubaoAPIKey == "" || h.DoubaoModel == "" {
		return nil, fmt.Errorf("AI 服务未配置")
	}

	reqBody := doubaoReqBody{
		Model: h.DoubaoModel,
		Messages: []doubaoMsg{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequest(
		http.MethodPost,
		"https://ark.cn-beijing.volces.com/api/v3/chat/completions",
		bytes.NewReader(bodyBytes),
	)
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+h.DoubaoAPIKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	rawBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var doubaoResp doubaoRespBody
	if err := json.Unmarshal(rawBody, &doubaoResp); err != nil {
		return nil, fmt.Errorf("解析响应失败: %w", err)
	}
	if doubaoResp.Error != nil {
		return nil, fmt.Errorf("豆包 API 错误: %s", doubaoResp.Error.Message)
	}
	if len(doubaoResp.Choices) == 0 {
		return nil, fmt.Errorf("AI 返回内容为空")
	}

	return parseCopies(doubaoResp.Choices[0].Message.Content), nil
}

// ── 解析 AI 输出为3条文案 ──────────────────────────────────────

func parseCopies(content string) []string {
	lines := strings.Split(content, "\n")
	copies := make([]string, 0, 3)
	prefixes := []string{"1. ", "2. ", "3. ", "1、", "2、", "3、", "1.", "2.", "3."}
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		for _, p := range prefixes {
			if strings.HasPrefix(line, p) {
				line = strings.TrimSpace(strings.TrimPrefix(line, p))
				break
			}
		}
		if line != "" {
			copies = append(copies, line)
		}
		if len(copies) == 3 {
			break
		}
	}
	return copies
}

// ── 辅助：风格 / 媒体类型描述 ──────────────────────────────────

func styleDesc(style string) string {
	switch style {
	case "lively":
		return "活泼可爱"
	case "literary":
		return "文艺清新"
	case "descriptive":
		return "细腻描绘"
	default:
		return "自然真实"
	}
}

func mediaTypeDesc(t string) string {
	switch t {
	case "video":
		return "视频"
	case "live_photo":
		return "Live Photo 动态图"
	default:
		return "图片"
	}
}
