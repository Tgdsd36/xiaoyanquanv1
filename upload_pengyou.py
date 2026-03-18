#!/usr/bin/env python3
"""从碰友API爬取一条素材并上传到小颜圈服务器"""

import json
import os
import requests
import psycopg2
from qcloud_cos import CosConfig, CosS3Client
from datetime import datetime

# 碰友API配置
BASE_URL = "https://zl.ljtao.cn"
HEADERS = {"Content-Type": "application/json"}

# 小颜圈数据库配置（远程连接）
DB_CONFIG = {
    "host": "159.75.44.225",
    "port": 15432,
    "user": "postgres",
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": "xiaoyanquan"
}

# 腾讯云COS配置（从环境变量读取，勿硬编码密钥）
COS_CONFIG = {
    "secret_id": os.environ.get("COS_SECRET_ID", ""),
    "secret_key": os.environ.get("COS_SECRET_KEY", ""),
    "bucket": "xyq02871-1409098971",
    "region": "ap-guangzhou"
}


def api_post(path, data=None):
    """调用碰友API"""
    url = f"{BASE_URL}{path}"
    try:
        r = requests.post(url, json=data or {}, headers=HEADERS, timeout=15)
        r.raise_for_status()
        result = r.json()
        if result.get("code") == 200:
            return result.get("data")
        else:
            print(f"API返回异常: {result.get('msg')}")
            return None
    except Exception as e:
        print(f"请求失败: {e}")
        return None


def main():
    print("===== 开始爬取碰友素材 =====\n")

    # 1. 获取一条素材
    print("正在获取素材列表...")
    list_data = api_post("/api/index/getGoodslist", {"page": 1})
    if not list_data or not list_data.get("data"):
        print("获取素材列表失败")
        return

    first_item = list_data["data"][0]
    material_id = first_item["id"]

    print(f"正在获取素材详情 (ID: {material_id})...")
    detail = api_post("/api/goods/goodsdetail", {"id": material_id})
    if not detail:
        print("获取素材详情失败")
        return

    print(f"素材标题: {detail.get('title', '无标题')}")

    # 2. 下载媒体文件
    main_images = detail.get("mainImage", [])
    if not main_images:
        print("素材没有主图")
        return

    media_url = main_images[0]
    print(f"\n正在下载媒体文件: {media_url}")
    try:
        r = requests.get(media_url, timeout=30)
        r.raise_for_status()
        file_content = r.content
        print(f"下载成功，文件大小: {len(file_content)} 字节")
    except Exception as e:
        print(f"下载失败: {e}")
        return

    # 3. 上传到COS
    print("\n正在上传到腾讯云COS...")
    try:
        config = CosConfig(
            Region=COS_CONFIG["region"],
            SecretId=COS_CONFIG["secret_id"],
            SecretKey=COS_CONFIG["secret_key"]
        )
        client = CosS3Client(config)

        file_ext = media_url.split(".")[-1].split("?")[0]
        filename = f"pengyou_{material_id}.{file_ext}"
        cos_key = f"materials/{datetime.now().strftime('%Y%m')}/{filename}"

        client.put_object(
            Bucket=COS_CONFIG["bucket"],
            Body=file_content,
            Key=cos_key
        )

        cos_url = f"https://{COS_CONFIG['bucket']}.cos.{COS_CONFIG['region']}.myqcloud.com/{cos_key}"
        print(f"上传成功: {cos_url}")
    except Exception as e:
        print(f"上传COS失败: {e}")
        return

    # 4. 插入数据库
    print("\n正在插入数据库...")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()

        title = detail.get("title", "")
        description = detail.get("describe", "")
        material_type = 1 if detail.get("type") == "图片" else 2
        tags = detail.get("tags", [])
        gender = 0

        if "男生" in str(tags):
            gender = 1
        elif "女生" in str(tags):
            gender = 2

        cursor.execute("""
            INSERT INTO materials (
                title, description, type, tags, original_urls, thumbnail_url,
                gender, view_count, favorite_count, category_id,
                created_at, updated_at
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW()
            ) RETURNING id
        """, (
            title, description, material_type, tags,
            [cos_url], cos_url, gender, 0, 0, 1
        ))

        new_id = cursor.fetchone()[0]
        conn.commit()
        cursor.close()
        conn.close()

        print(f"插入成功! 素材ID: {new_id}")
        print(f"\n===== 完成! =====")
        print(f"可以在管理后台查看: https://xyqad.cfqfwl.cn")

    except Exception as e:
        print(f"数据库插入失败: {e}")
        if 'conn' in locals():
            conn.rollback()


if __name__ == "__main__":
    main()
