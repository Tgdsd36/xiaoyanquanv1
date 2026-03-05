package response

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

type PageData struct {
	List     interface{} `json:"list"`
	Total    int64       `json:"total"`
	Page     int         `json:"page"`
	PageSize int         `json:"page_size"`
	HasMore  bool        `json:"has_more"`
}

// 成功响应
func Success(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Response{
		Code:    0,
		Message: "ok",
		Data:    data,
	})
}

// 成功响应（无数据）
func SuccessMessage(c *gin.Context, msg string) {
	c.JSON(http.StatusOK, Response{
		Code:    0,
		Message: msg,
	})
}

// 分页响应
func SuccessPage(c *gin.Context, list interface{}, total int64, page, pageSize int) {
	hasMore := int64(page*pageSize) < total
	c.JSON(http.StatusOK, Response{
		Code:    0,
		Message: "ok",
		Data: PageData{
			List:     list,
			Total:    total,
			Page:     page,
			PageSize: pageSize,
			HasMore:  hasMore,
		},
	})
}

// 错误响应
func Error(c *gin.Context, httpCode int, errCode int, msg string) {
	c.JSON(httpCode, Response{
		Code:    errCode,
		Message: msg,
	})
}

// 常用错误快捷方法
func BadRequest(c *gin.Context, errCode int, msg string) {
	Error(c, http.StatusBadRequest, errCode, msg)
}

func Unauthorized(c *gin.Context, msg string) {
	Error(c, http.StatusUnauthorized, 401, msg)
}

func Forbidden(c *gin.Context, msg string) {
	Error(c, http.StatusForbidden, 403, msg)
}

func NotFound(c *gin.Context, msg string) {
	Error(c, http.StatusNotFound, 404, msg)
}

func ServerError(c *gin.Context, msg string) {
	Error(c, http.StatusInternalServerError, 500, msg)
}

// 业务错误码
const (
	ErrCodeSMSCodeInvalid   = 10001
	ErrCodeSMSCodeExpired   = 10002
	ErrCodePasswordWrong    = 10003
	ErrCodePhoneRegistered  = 10004
	ErrCodePhoneNotFound    = 10005
	ErrCodeDeviceIDRequired = 10006
	ErrCodeDeviceBoundOther = 10007
	ErrCodeDeviceMismatch   = 10008
	ErrCodeDownloadLimit    = 20001
	ErrCodeMaterialNotFound = 20002
	ErrCodePaymentFailed    = 30001
	ErrCodeOrderNotFound    = 30002
)
