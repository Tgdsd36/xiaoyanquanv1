package handler

import (
	"encoding/json"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/middleware"
	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

type MaterialHandler struct {
	DB      *gorm.DB
	BaseURL string
}

// cosPublicBase COS 公网域名前缀，由 router 层在启动时设置。
// 为空时表示未启用 COS，所有路径走 BaseURL。
var cosPublicBase string

// SetCOSPublicBase 设置 COS 公网域名，在 router.Setup 中调用。
func SetCOSPublicBase(base string) {
	cosPublicBase = strings.TrimRight(base, "/")
}

// fullURL 将相对路径或 COS Key 转换为完整 URL
// - 已是完整 URL → 直接返回
// - 以 /static/ 开头 → 旧本地路径，拼 baseURL
// - 其他 → COS Key，拼 cosPublicBase
func fullURL(baseURL, p string) string {
	if p == "" {
		return ""
	}
	// 已经是完整 URL 的直接返回
	if len(p) > 4 && (p[:4] == "http" || p[:2] == "//") {
		return p
	}
	// 旧本地路径
	if strings.HasPrefix(p, "/static/") {
		return baseURL + p
	}
	// COS Key
	if cosPublicBase != "" {
		return cosPublicBase + "/" + p
	}
	return baseURL + "/" + p
}

// parseOriginalURLs 解析 jsonb 中的 original_urls 并补全域名
func parseOriginalURLs(baseURL string, raw model.JSON) []string {
	if len(raw) == 0 {
		return []string{}
	}
	var urls []string
	if err := json.Unmarshal(raw, &urls); err != nil {
		return []string{}
	}
	result := make([]string, 0, len(urls))
	for _, u := range urls {
		if fu := fullURL(baseURL, u); fu != "" {
			result = append(result, fu)
		}
	}
	return result
}

// ==================== 响应结构 ====================

type MaterialListItem struct {
	ID            uint     `json:"id"`
	Title         string   `json:"title"`
	Type          string   `json:"type"`
	ThumbnailURL  string   `json:"thumbnail_url"`
	WatermarkURL  string   `json:"watermark_url,omitempty"`
	OriginalURLs  []string `json:"original_urls"`
	Width         int      `json:"width"`
	Height        int      `json:"height"`
	Duration      float64  `json:"duration,omitempty"`
	HotScore      float64  `json:"hot_score"`
	DownloadCount int      `json:"download_count"`
	FavoriteCount int      `json:"favorite_count"`
	Tags          []string `json:"tags"`
	IsFavorited   bool     `json:"is_favorited"`
}

type MaterialDetailResp struct {
	ID            uint     `json:"id"`
	Title         string   `json:"title"`
	Description   string   `json:"description"`
	Type          string   `json:"type"`
	CategoryID    *uint    `json:"category_id"`
	CategoryName  string   `json:"category_name"`
	Tags          []string `json:"tags"`
	Width         int      `json:"width"`
	Height        int      `json:"height"`
	Duration      float64  `json:"duration,omitempty"`
	FileSize      int64    `json:"file_size"`
	FileSizeText  string   `json:"file_size_text"`
	ThumbnailURL  string   `json:"thumbnail_url"`
	WatermarkURL  string   `json:"watermark_url"`
	PreviewMovURL string   `json:"preview_mov_url,omitempty"`
	OriginalURLs  []string `json:"original_urls"`
	HotScore      float64  `json:"hot_score"`
	DownloadCount int      `json:"download_count"`
	FavoriteCount int      `json:"favorite_count"`
	ViewCount     int      `json:"view_count"`
	IsFavorited   bool     `json:"is_favorited"`
	CreatedAt     string   `json:"created_at"`
}

// ==================== 列表 ====================

func (h *MaterialHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	categoryID, _ := strconv.Atoi(c.DefaultQuery("category_id", "0"))
	gender := c.DefaultQuery("gender", "")
	materialType := c.DefaultQuery("type", "")
	sort := c.DefaultQuery("sort", "hot") // hot, latest, downloads

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 50 {
		pageSize = 20
	}

	query := h.DB.Model(&model.Material{}).Where("status = ?", "published")

	// 时段过滤：空值和 all 的素材全天展示
	if timePeriod := c.Query("time_period"); timePeriod != "" {
		query = query.Where("time_period = '' OR time_period = 'all' OR time_period IS NULL OR time_period = ?", timePeriod)
	}

	if categoryID > 0 {
		// 检查是否为一级分类（有子分类），若是则展开查询
		var childIDs []uint
		h.DB.Model(&model.Category{}).Where("parent_id = ?", categoryID).Pluck("id", &childIDs)
		if len(childIDs) > 0 {
			// 一级分类：查子分类下的所有素材
			query = query.Where("category_id IN ?", childIDs)
		} else {
			// 二级分类：直接筛选
			query = query.Where("category_id = ?", categoryID)
		}
	}
	if gender != "" {
		query = query.Where("gender = ?", gender)
	}
	if materialType != "" {
		query = query.Where("type = ?", materialType)
	}

	var total int64
	query.Count(&total)

	switch sort {
	case "latest":
		query = query.Order("created_at DESC")
	case "downloads":
		query = query.Order("download_count DESC")
	default:
		query = query.Order("hot_score DESC")
	}

	var materials []model.Material
	query.Offset((page - 1) * pageSize).Limit(pageSize).Find(&materials)

	// 检查当前用户收藏状态
	userID := middleware.GetUserID(c)
	favoriteMap := h.getUserFavorites(userID, materials)

	list := make([]MaterialListItem, len(materials))
	for i, m := range materials {
		tags := make([]string, 0)
		if m.Tags != nil {
			tags = m.Tags
		}
		list[i] = MaterialListItem{
			ID:            m.ID,
			Title:         m.Title,
			Type:          m.Type,
			ThumbnailURL:  fullURL(h.BaseURL, m.ThumbnailURL),
			WatermarkURL:  fullURL(h.BaseURL, m.WatermarkURL),
			OriginalURLs:  parseOriginalURLs(h.BaseURL, m.OriginalURLs),
			Width:         m.Width,
			Height:        m.Height,
			Duration:      m.Duration,
			HotScore:      m.HotScore,
			DownloadCount: m.DownloadCount,
			FavoriteCount: m.FavoriteCount,
			Tags:          tags,
			IsFavorited:   favoriteMap[m.ID],
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// ==================== 详情 ====================

func (h *MaterialHandler) Detail(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	var material model.Material
	if err := h.DB.Preload("Category").First(&material, id).Error; err != nil {
		response.NotFound(c, "素材不存在")
		return
	}

	if material.Status != "published" {
		response.NotFound(c, "素材不存在")
		return
	}

	// 异步增加浏览量
	go h.DB.Model(&material).UpdateColumn("view_count", gorm.Expr("view_count + 1"))

	// 记录浏览行为
	userID := middleware.GetUserID(c)
	if userID > 0 {
		go h.DB.Create(&model.UserBehavior{
			UserID:     userID,
			MaterialID: uint(id),
			Action:     "view",
			CreatedAt:  time.Now(),
		})
	}

	isFavorited := false
	if userID > 0 {
		var count int64
		h.DB.Model(&model.Favorite{}).
			Where("user_id = ? AND target_type = ? AND target_id = ?", userID, "material", id).
			Count(&count)
		isFavorited = count > 0
	}

	categoryName := ""
	if material.Category != nil {
		categoryName = material.Category.Name
	}

	tags := make([]string, 0)
	if material.Tags != nil {
		tags = material.Tags
	}

	// 解析原图 URLs
	var originalURLs []string
	if len(material.OriginalURLs) > 0 {
		json.Unmarshal(material.OriginalURLs, &originalURLs)
	}
	fullOriginalURLs := make([]string, len(originalURLs))
	for i, u := range originalURLs {
		fullOriginalURLs[i] = fullURL(h.BaseURL, u)
	}

	resp := MaterialDetailResp{
		ID:            material.ID,
		Title:         material.Title,
		Description:   material.Description,
		Type:          material.Type,
		CategoryID:    material.CategoryID,
		CategoryName:  categoryName,
		Tags:          tags,
		Width:         material.Width,
		Height:        material.Height,
		Duration:      material.Duration,
		FileSize:      material.FileSize,
		FileSizeText:  material.FileSizeText(),
		ThumbnailURL:  fullURL(h.BaseURL, material.ThumbnailURL),
		WatermarkURL:  fullURL(h.BaseURL, material.WatermarkURL),
		PreviewMovURL: fullURL(h.BaseURL, material.PreviewMovURL),
		OriginalURLs:  fullOriginalURLs,
		HotScore:      material.HotScore,
		DownloadCount: material.DownloadCount,
		FavoriteCount: material.FavoriteCount,
		ViewCount:     material.ViewCount,
		IsFavorited:   isFavorited,
		CreatedAt:     material.CreatedAt.Format("2006-01-02 15:04"),
	}

	response.Success(c, resp)
}

// ==================== 搜索 ====================

func (h *MaterialHandler) Search(c *gin.Context) {
	keyword := c.Query("keyword")
	if keyword == "" {
		response.BadRequest(c, 400, "请输入搜索关键词")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 50 {
		pageSize = 20
	}

	query := h.DB.Model(&model.Material{}).
		Where("status = ?", "published").
		Where("title ILIKE ? OR ? = ANY(tags)", "%"+keyword+"%", keyword)

	// 类型筛选
	if materialType := c.Query("type"); materialType != "" {
		query = query.Where("type = ?", materialType)
	}

	// 分类筛选
	if categoryID, _ := strconv.Atoi(c.DefaultQuery("category_id", "0")); categoryID > 0 {
		var childIDs []uint
		h.DB.Model(&model.Category{}).Where("parent_id = ?", categoryID).Pluck("id", &childIDs)
		if len(childIDs) > 0 {
			query = query.Where("category_id IN ?", childIDs)
		} else {
			query = query.Where("category_id = ?", categoryID)
		}
	}

	var total int64
	query.Count(&total)

	var materials []model.Material
	query.Order("hot_score DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&materials)

	userID := middleware.GetUserID(c)
	favoriteMap := h.getUserFavorites(userID, materials)

	list := make([]MaterialListItem, len(materials))
	for i, m := range materials {
		tags := make([]string, 0)
		if m.Tags != nil {
			tags = m.Tags
		}
		list[i] = MaterialListItem{
			ID:            m.ID,
			Title:         m.Title,
			Type:          m.Type,
			ThumbnailURL:  fullURL(h.BaseURL, m.ThumbnailURL),
			WatermarkURL:  fullURL(h.BaseURL, m.WatermarkURL),
			Width:         m.Width,
			Height:        m.Height,
			Duration:      m.Duration,
			HotScore:      m.HotScore,
			DownloadCount: m.DownloadCount,
			FavoriteCount: m.FavoriteCount,
			Tags:          tags,
			IsFavorited:   favoriteMap[m.ID],
		}
	}

	response.SuccessPage(c, list, total, page, pageSize)
}

// ==================== 下载 ====================

func (h *MaterialHandler) Download(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, 400, "参数错误")
		return
	}

	userID := middleware.GetUserID(c)

	// 查询用户信息
	var user model.User
	if err := h.DB.First(&user, userID).Error; err != nil {
		response.ServerError(c, "系统错误")
		return
	}

	// 检查是否会员
	if !user.IsMember() {
		response.Forbidden(c, "请先开通会员")
		return
	}

	// 检查月下载额度
	monthlyLimit := 5000
	if user.MemberType == "flagship" {
		monthlyLimit = 10000
	}

	// 重置月计数器
	now := time.Now()
	if user.DownloadCountResetAt == nil || user.DownloadCountResetAt.Month() != now.Month() {
		h.DB.Model(&user).Updates(map[string]interface{}{
			"monthly_download_count":  0,
			"download_count_reset_at": now,
		})
		user.MonthlyDownloadCount = 0
	}

	if user.MonthlyDownloadCount >= monthlyLimit {
		response.Error(c, 403, response.ErrCodeDownloadLimit, "本月下载次数已用完")
		return
	}

	// 查询素材
	var material model.Material
	if err := h.DB.First(&material, id).Error; err != nil {
		response.NotFound(c, "素材不存在")
		return
	}

	// 记录下载
	h.DB.Create(&model.Download{
		UserID:       userID,
		MaterialID:   uint(id),
		DownloadedAt: now,
	})

	// 更新计数
	h.DB.Model(&user).UpdateColumn("monthly_download_count", gorm.Expr("monthly_download_count + 1"))
	h.DB.Model(&material).UpdateColumn("download_count", gorm.Expr("download_count + 1"))

	// 记录行为
	h.DB.Create(&model.UserBehavior{
		UserID:     userID,
		MaterialID: uint(id),
		Action:     "download",
		CreatedAt:  now,
	})

	// 更新热度
	go h.updateHotScore(&material)

	// 解析原图 URLs（视频下载优先返回可用的移动端 MP4）
	var urls []string
	if len(material.OriginalURLs) > 0 {
		json.Unmarshal(material.OriginalURLs, &urls)
	}
	// Live Photo 兜底：确保 preview_mov_url 也在下载列表中
	if material.Type == "live_photo" && strings.TrimSpace(material.PreviewMovURL) != "" {
		urls = append(urls, fullURL(h.BaseURL, material.PreviewMovURL))
	}
	urls = normalizeDownloadURLs(urls)
	if material.Type == "video" {
		urls = prioritizeVideoURLsForMobile(urls)
	}
	downloadURL := ""
	if len(urls) > 0 {
		downloadURL = urls[0]
	}

	response.Success(c, gin.H{
		"download_url":    downloadURL,
		"download_urls":   urls,
		"remaining_count": monthlyLimit - user.MonthlyDownloadCount - 1,
		"monthly_limit":   monthlyLimit,
	})
}

func normalizeDownloadURLs(raw []string) []string {
	out := make([]string, 0, len(raw))
	seen := make(map[string]struct{}, len(raw))
	for _, item := range raw {
		u := strings.TrimSpace(item)
		if u == "" {
			continue
		}
		if _, exists := seen[u]; exists {
			continue
		}
		seen[u] = struct{}{}
		out = append(out, u)
	}
	return out
}

func prioritizeVideoURLsForMobile(urls []string) []string {
	if len(urls) == 0 {
		return urls
	}

	preferred := ""
	for _, u := range urls {
		if !isVideoURL(u) {
			continue
		}
		if mobile := findMobileVideoVariantURL(u); mobile != "" {
			preferred = mobile
			break
		}
	}
	if preferred == "" {
		for _, u := range urls {
			if isVideoURL(u) {
				preferred = u
				break
			}
		}
	}
	if preferred == "" {
		return urls
	}

	out := make([]string, 0, len(urls)+1)
	out = append(out, preferred)
	for _, u := range urls {
		if u == preferred {
			continue
		}
		out = append(out, u)
	}
	return normalizeDownloadURLs(out)
}

func isVideoURL(raw string) bool {
	ext := strings.ToLower(filepath.Ext(extractURLPath(raw)))
	switch ext {
	case ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm":
		return true
	default:
		return false
	}
}

func findMobileVideoVariantURL(raw string) string {
	cleanPath := extractURLPath(raw)
	if cleanPath == "" {
		return ""
	}

	ext := strings.ToLower(filepath.Ext(cleanPath))
	if ext == ".mp4" {
		return raw
	}
	if !isVideoURL(raw) {
		return ""
	}

	dir := path.Dir(cleanPath)
	base := strings.TrimSuffix(path.Base(cleanPath), path.Ext(cleanPath))
	candidates := []string{
		path.Join(dir, base+"_mobile.mp4"),
		path.Join(dir, base+".mp4"),
	}

	for _, candidatePath := range candidates {
		candidate := rewriteURLPath(raw, candidatePath)
		if localStaticURLExists(candidate) {
			return candidate
		}
	}
	return ""
}

func extractURLPath(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	if strings.HasPrefix(trimmed, "/") {
		return trimmed
	}
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return ""
	}
	return parsed.Path
}

func rewriteURLPath(raw, newPath string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return newPath
	}
	if strings.HasPrefix(trimmed, "/") {
		return newPath
	}
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return newPath
	}
	parsed.Path = newPath
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String()
}

func localStaticURLExists(raw string) bool {
	p := extractURLPath(raw)
	if p == "" || !strings.HasPrefix(p, "/static/") {
		return false
	}
	local := filepath.Join(".", strings.TrimPrefix(p, "/"))
	_, err := os.Stat(local)
	return err == nil
}

// ==================== 内部方法 ====================

func (h *MaterialHandler) getUserFavorites(userID uint, materials []model.Material) map[uint]bool {
	result := make(map[uint]bool)
	if userID == 0 || len(materials) == 0 {
		return result
	}

	ids := make([]uint, len(materials))
	for i, m := range materials {
		ids[i] = m.ID
	}

	var favorites []model.Favorite
	h.DB.Where("user_id = ? AND target_type = ? AND target_id IN ?", userID, "material", ids).
		Find(&favorites)

	for _, f := range favorites {
		result[f.TargetID] = true
	}
	return result
}

func (h *MaterialHandler) updateHotScore(m *model.Material) {
	hours := time.Since(m.CreatedAt).Hours()
	rawScore := float64(m.DownloadCount)*5 + float64(m.FavoriteCount)*3 + float64(m.ViewCount)*1
	denom := 1.0
	base := hours + 2
	// (hours+2)^1.5
	denom = base * base * base
	if denom > 0 {
		denom = sqrt(denom)
	}
	hotScore := rawScore / denom
	h.DB.Model(m).UpdateColumn("hot_score", hotScore)
}

// 简单 sqrt 近似，避免引入 math 包的 Pow
func sqrt(x float64) float64 {
	if x <= 0 {
		return 0
	}
	z := x / 2
	for i := 0; i < 20; i++ {
		z = z - (z*z-x)/(2*z)
	}
	return z
}
