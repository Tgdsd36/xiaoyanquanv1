package handler

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/xiaoyanquan/server/internal/model"
	"github.com/xiaoyanquan/server/pkg/response"
)

type CategoryHandler struct {
	DB *gorm.DB
}

type CategoryResponse struct {
	ID        uint               `json:"id"`
	ParentID  *uint              `json:"parent_id"`
	Name      string             `json:"name"`
	Slug      string             `json:"slug"`
	SortOrder int                `json:"sort_order"`
	Children  []CategoryResponse `json:"children,omitempty"`
}

// List 获取所有可见分类（树形结构）
func (h *CategoryHandler) List(c *gin.Context) {
	var categories []model.Category
	if err := h.DB.Where("is_visible = ?", true).
		Order("sort_order ASC, id ASC").
		Find(&categories).Error; err != nil {
		response.ServerError(c, "获取分类失败")
		return
	}

	tree := buildCategoryTree(categories, nil)
	response.Success(c, tree)
}

// buildCategoryTree 将扁平列表组装为树形结构
func buildCategoryTree(all []model.Category, parentID *uint) []CategoryResponse {
	var result []CategoryResponse
	for _, cat := range all {
		// 匹配 parent_id
		if (parentID == nil && cat.ParentID == nil) ||
			(parentID != nil && cat.ParentID != nil && *parentID == *cat.ParentID) {
			node := CategoryResponse{
				ID:        cat.ID,
				ParentID:  cat.ParentID,
				Name:      cat.Name,
				Slug:      cat.Slug,
				SortOrder: cat.SortOrder,
				Children:  buildCategoryTree(all, &cat.ID),
			}
			result = append(result, node)
		}
	}
	return result
}
