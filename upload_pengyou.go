package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	pengyouBaseURL = "https://zl.ljtao.cn"
	serverBaseURL  = "https://xyqapi.cfqfwl.cn"
)

type PengyouResponse struct {
	Code int         `json:"code"`
	Msg  string      `json:"msg"`
	Data interface{} `json:"data"`
}

type MaterialDetail struct {
	ID        int      `json:"id"`
	Title     string   `json:"title"`
	Describe  string   `json:"describe"`
	Type      string   `json:"type"`
	Tags      []string `json:"tags"`
	MainImage []string `json:"mainImage"`
}

func pengyouPost(path string, data map[string]interface{}) (interface{}, error) {
	url := pengyouBaseURL + path
	jsonData, _ := json.Marshal(data)

	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result PengyouResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	if result.Code != 200 {
		return nil, fmt.Errorf("API error: %s", result.Msg)
	}

	return result.Data, nil
}

func main() {
	fmt.Println("===== 开始爬取碰友素材 =====\n")

	// 1. 获取素材列表
	fmt.Println("正在获取素材列表...")
	listData, err := pengyouPost("/api/index/getGoodslist", map[string]interface{}{"page": 1})
	if err != nil {
		fmt.Printf("获取列表失败: %v\n", err)
		return
	}

	listMap := listData.(map[string]interface{})
	dataList := listMap["data"].([]interface{})
	if len(dataList) == 0 {
		fmt.Println("没有素材")
		return
	}

	firstItem := dataList[0].(map[string]interface{})
	materialID := int(firstItem["id"].(float64))

	// 2. 获取素材详情
	fmt.Printf("正在获取素材详情 (ID: %d)...\n", materialID)
	detailData, err := pengyouPost("/api/goods/goodsdetail", map[string]interface{}{"id": materialID})
	if err != nil {
		fmt.Printf("获取详情失败: %v\n", err)
		return
	}

	detailMap := detailData.(map[string]interface{})
	title := detailMap["title"].(string)
	fmt.Printf("素材标题: %s\n", title)

	// 3. 准备数据并调用小颜圈API
	fmt.Println("\n正在上传到小颜圈...")

	materialType := 1
	if detailMap["type"].(string) == "视频" {
		materialType = 2
	}

	tags := []string{}
	if tagList, ok := detailMap["tags"].([]interface{}); ok {
		for _, tag := range tagList {
			tags = append(tags, tag.(string))
		}
	}

	mainImages := []string{}
	if imgList, ok := detailMap["mainImage"].([]interface{}); ok {
		for _, img := range imgList {
			mainImages = append(mainImages, img.(string))
		}
	}

	uploadData := map[string]interface{}{
		"title":         title,
		"description":   detailMap["describe"],
		"type":          materialType,
		"tags":          tags,
		"original_urls": mainImages,
		"thumbnail_url": mainImages[0],
		"gender":        0,
		"category_id":   1,
	}

	jsonData, _ := json.Marshal(uploadData)
	fmt.Printf("上传数据: %s\n", string(jsonData))

	// 调用小颜圈API
	req, _ := http.NewRequest("POST", serverBaseURL+"/api/admin/materials", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	// TODO: 需要添加认证token

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("上传失败: %v\n", err)
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	fmt.Printf("响应: %s\n", string(body))

	fmt.Println("\n===== 完成 =====")
}
