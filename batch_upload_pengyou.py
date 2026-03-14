#!/usr/bin/env python3
"""将碰友已抓取的详情 JSON 导入到小颜圈后台。

默认策略:
- 读取 /Users/.../碰友_素材数据/details/*.json
- 使用线上 JWT secret 直接签 admin token，走正式后台 API
- 默认导入为 draft，且不投放到找灵感/朋友圈
- 默认先做远端去重：按 original_urls 和 title 检查
- 默认会自动补建缺失分类，优先挂到已有一级分类下

依赖:
- 仅需 Python 标准库

运行示例:
  XYQ_ADMIN_JWT_SECRET='...' /usr/bin/python3 batch_upload_pengyou.py --limit 10
  XYQ_ADMIN_JWT_SECRET='...' /usr/bin/python3 batch_upload_pengyou.py --dry-run
  XYQ_ADMIN_JWT_SECRET='...' /usr/bin/python3 batch_upload_pengyou.py --publish --show-inspiration --show-moments
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.parse import urlencode
from urllib.request import Request, urlopen

DETAILS_DIR = Path("/Users/a15554022309/Documents/碰友_素材数据/details")
DEFAULT_API_BASE = "https://xyqapi.cfqfwl.cn/api/admin"
DEFAULT_ADMIN_ID = 1
DEFAULT_ADMIN_USERNAME = "admin"
DEFAULT_ADMIN_ROLE = "admin"
DEFAULT_TIMEOUT = 20
STATE_FILE = "import_state.json"
DOTENV_PATH = Path("/Users/a15554022309/Documents/素材库app/xiaoyanquan-server/.env.production")
_KNOWN_EXTS = {"jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "mp4", "mov", "mp3"}


def load_dotenv(path: Path) -> None:
    """读取 .env 文件，仅填充尚未设置的环境变量（不覆盖已显式传入的值）。"""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        if k and not os.environ.get(k):
            os.environ[k] = v.strip()


class CosUploader:
    """下载远端 URL 并上传到腾讯云 COS，返回 COS 公开链接。"""

    def __init__(self, secret_id: str, secret_key: str, bucket: str, region: str, cdn_domain: str = "") -> None:
        from qcloud_cos import CosConfig, CosS3Client  # type: ignore
        self.client = CosS3Client(CosConfig(Region=region, SecretId=secret_id, SecretKey=secret_key))
        self.bucket = bucket
        self.base_url = cdn_domain.rstrip("/") if cdn_domain else f"https://{bucket}.cos.{region}.myqcloud.com"
        self._cache: Dict[str, str] = {}

    def _ext(self, url: str) -> str:
        if "vframe/jpg" in url or "imageMogr2" in url:
            return "jpg"
        part = url.split("?")[0].split("#")[0]
        ext = part.rsplit(".", 1)[-1].lower() if "." in part else ""
        return ext if ext in _KNOWN_EXTS else "bin"

    def upload_url(self, src_url: str, source_id: int) -> str:
        """下载 src_url 并上传至 COS；失败时返回原 URL。"""
        if not src_url:
            return src_url
        if src_url in self._cache:
            return self._cache[src_url]
        if src_url.startswith(self.base_url):
            return src_url
        key = f"pengyou/{time.strftime('%Y%m')}/{source_id}/{hashlib.sha256(src_url.encode()).hexdigest()[:10]}.{self._ext(src_url)}"
        try:
            req = Request(src_url, headers={
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                "Referer": "https://zl.ljtao.cn/",
            })
            with urlopen(req, timeout=60) as resp:
                body = resp.read()
            self.client.put_object(Bucket=self.bucket, Body=body, Key=key)
            cos_url = f"{self.base_url}/{key}"
            self._cache[src_url] = cos_url
            log(f"  COS ✓ {key}")
            return cos_url
        except Exception as exc:
            log(f"  COS ✗ {src_url[:60]}...: {exc}，保留原链接")
            return src_url

    def replace_urls(self, payload: Dict[str, Any], source_id: int) -> None:
        """原地替换 payload 中所有媒体 URL 为 COS URL。"""
        payload["original_urls"] = [self.upload_url(u, source_id) for u in payload.get("original_urls") or []]
        if payload.get("thumbnail_url"):
            payload["thumbnail_url"] = self.upload_url(payload["thumbnail_url"], source_id)
        if payload.get("preview_mov_url"):
            payload["preview_mov_url"] = self.upload_url(payload["preview_mov_url"], source_id)


def now_text() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())


def log(message: str) -> None:
    print(f"[{now_text()}] {message}")


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return default


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
    tmp.replace(path)


def normalize_name(value: str) -> str:
    value = (value or "").strip().lower()
    value = value.replace("\u3000", " ")
    value = re.sub(r"\s+", "", value)
    value = value.replace("·", "").replace("•", "")
    return value


def sanitize_title(value: str, source_id: int) -> str:
    text = (value or "").strip()
    if not text:
        return f"碰友素材_{source_id}"
    text = re.sub(r"\s+", " ", text)
    if len(text) > 200:
        text = text[:200].rstrip()
    return text


def dedupe_keep_order(values: Iterable[str]) -> List[str]:
    out: List[str] = []
    seen = set()
    for value in values:
        text = (value or "").strip()
        if not text or text in seen:
            continue
        out.append(text)
        seen.add(text)
    return out


def extract_hashtags(detail: Dict[str, Any]) -> List[str]:
    candidates = [
        str(detail.get("desc") or ""),
        str(detail.get("search_keywords") or ""),
        str(detail.get("keywords") or ""),
    ]
    tags: List[str] = []
    for text in candidates:
        tags.extend(re.findall(r"#([^#\[\]]+)(?:\[话题\])?#", text))
    return dedupe_keep_order(tags)


def split_candidates(detail: Dict[str, Any]) -> List[str]:
    values = [
        detail.get("grouptitle_sub"),
        detail.get("grouptitle"),
        detail.get("tixing"),
        detail.get("juese"),
        detail.get("time"),
        detail.get("jijie"),
    ]
    tags = extract_hashtags(detail)
    for tag in tags:
        values.append(tag)
    # 也解析空格分隔的关键词（search_keywords / desc）
    for field in ("search_keywords", "desc"):
        text = str(detail.get(field) or "").strip()
        if text:
            for word in re.split(r"[\s,;\uff0c\uff1b]+", text):
                word = word.strip()
                if len(word) >= 2:
                    values.append(word)
    return dedupe_keep_order(str(v) for v in values if v)


def parse_media_data_urls(detail: Dict[str, Any]) -> Tuple[List[str], str]:
    raw = detail.get("media_data")
    if raw in (None, "", []):
        return [], ""
    parsed = raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except Exception:
            return [], ""

    urls: List[str] = []
    preview = ""

    def walk(node: Any) -> None:
        nonlocal preview
        if isinstance(node, dict):
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, str):
            if node.startswith("http://") or node.startswith("https://"):
                urls.append(node)
                lowered = node.lower()
                if preview == "" and (lowered.endswith(".mov") or lowered.endswith(".mp4")):
                    preview = node

    walk(parsed)
    image_urls = [url for url in dedupe_keep_order(urls) if not re.search(r"\.(mov|mp4)(\?|$)", url, re.I)]
    return image_urls, preview


def resolve_type(detail: Dict[str, Any]) -> str:
    if detail.get("livepoto"):
        image_urls, preview = parse_media_data_urls(detail)
        if image_urls and preview:
            return "live_photo"
    if detail.get("vod"):
        return "video"
    return "image"


def resolve_original_urls(detail: Dict[str, Any], material_type: str) -> Tuple[List[str], str]:
    if material_type == "video":
        vod = str(detail.get("vod") or "").strip()
        thumb = str(detail.get("vod_img") or "").strip()
        return dedupe_keep_order([vod]), thumb or vod

    if material_type == "live_photo":
        image_urls, preview = parse_media_data_urls(detail)
        if image_urls and preview:
            thumb = image_urls[0]
            return image_urls, thumb

    images = detail.get("mainImage") or detail.get("images") or []
    if isinstance(images, str):
        images = [images]
    image_urls = dedupe_keep_order(str(item) for item in images if item)
    thumb = image_urls[0] if image_urls else ""
    return image_urls, thumb


def resolve_preview_mov_url(detail: Dict[str, Any], material_type: str) -> str:
    if material_type != "live_photo":
        return ""
    _, preview = parse_media_data_urls(detail)
    return preview


def resolve_description(detail: Dict[str, Any]) -> str:
    parts = [
        str(detail.get("desc") or "").strip(),
        str(detail.get("new_content") or "").strip(),
        str(detail.get("content") or "").strip(),
    ]
    text = "\n".join(part for part in parts if part)
    return text[:5000]


def make_jwt(secret: str, admin_id: int, username: str, role: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    payload = {
        "user_id": admin_id,
        "phone": username,
        "type": "admin_access",
        "iss": "xiaoyanquan-admin",
        "sub": role,
        "iat": now,
        "exp": now + 86400,
    }

    def b64(data: Dict[str, Any]) -> bytes:
        raw = json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        return base64.urlsafe_b64encode(raw).rstrip(b"=")

    signing_input = b".".join([b64(header), b64(payload)])
    signature = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return b".".join(
        [signing_input, base64.urlsafe_b64encode(signature).rstrip(b"=")]
    ).decode("utf-8")


class AdminAPI:
    def __init__(self, api_base: str, token: str, timeout: int) -> None:
        self.api_base = api_base.rstrip("/")
        self.timeout = timeout
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            "User-Agent": "xiaoyanquan-importer/1.0",
        }

    def request(
        self,
        method: str,
        path: str,
        data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        url = f"{self.api_base}{path}"
        if params:
            url = f"{url}?{urlencode(params, doseq=True)}"
        body = None if data is None else json.dumps(data, ensure_ascii=False).encode("utf-8")
        req = Request(url, data=body, method=method.upper(), headers=self.headers)
        with urlopen(req, timeout=self.timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        if payload.get("code") != 0:
            raise RuntimeError(f"{path} -> {payload.get('message')}")
        return payload["data"]

    def get_categories(self) -> List[Dict[str, Any]]:
        return self.request("GET", "/categories")

    def list_materials(self, page: int, page_size: int, keyword: str = "") -> Dict[str, Any]:
        params: Dict[str, Any] = {"page": page, "page_size": page_size}
        if keyword:
            params["keyword"] = keyword
        return self.request("GET", "/materials", params=params)

    def create_material(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self.request("POST", "/materials", data=payload)

    def create_category(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self.request("POST", "/categories", data=payload)

    def update_material(self, material_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self.request("PUT", f"/materials/{material_id}", data=payload)

    def batch_delete_materials(self, ids: List[int]) -> Dict[str, Any]:
        return self.request("POST", "/materials/batch-delete", data={"ids": ids})


@dataclass
class CategoryMaps:
    parents: Dict[str, Dict[str, Any]]
    children: Dict[str, Dict[str, Any]]


def build_category_maps(categories: Sequence[Dict[str, Any]]) -> CategoryMaps:
    parents: Dict[str, Dict[str, Any]] = {}
    children: Dict[str, Dict[str, Any]] = {}
    for parent in categories:
        parent_key = normalize_name(str(parent.get("name") or ""))
        if parent_key:
            parents[parent_key] = parent
        for child in parent.get("children", []) or []:
            child_key = normalize_name(str(child.get("name") or ""))
            if child_key:
                children[child_key] = child
    return CategoryMaps(parents=parents, children=children)


PARENT_KEYWORDS = {
    "旅行度假": [
        "旅行", "旅游", "海岸", "海边", "海岛", "大海", "沙滩", "景点",
        "澳大利亚", "澳洲", "墨尔本", "悉尼", "布里斯班", "黄金海岸", "机场", "高铁",
        "酒店", "民宿", "出海", "帆船", "游艇", "环球影城", "迪士尼", "度假",
        "三亚", "丽江", "大理", "西藏", "新疆", "泰国", "日本", "韩国", "马尔代夫",
    ],
    "魅力展示类": [
        "身材", "穿搭", "自拍", "腹肌", "西装", "背影", "体重", "OOTD", "搭配",
        "写真", "美照", "镜子", "造型", "发型", "丝袜", "腿", "美足", "颜值",
    ],
    "运动": [
        "健身", "跑步", "游泳", "篮球", "足球", "瑜伽", "羽毛球", "网球",
        "高尔夫", "滑雪", "保龄球", "射箭", "滑板", "跳伞", "撸铁", "拳击",
    ],
    "生活": [
        "清晨", "早餐", "日出", "日落", "夜跑", "做饭", "水果", "周末", "散步",
        "夜景", "烟花", "家务", "理发", "饺子", "汤圆", "海鲜", "减肥餐",
    ],
    "吃饭美食类": [
        "火锅", "烧烤", "烤肉", "撸串", "小龙虾", "大闸蟹", "快餐", "西餐", "海底捞",
        "三文鱼", "路边摊", "成都火锅",
    ],
    "咖啡奶茶": [
        "奶茶", "咖啡", "下午茶", "蛋糕", "星巴克", "茶姬", "冰淇淋", "甜品",
    ],
    "夜生活": [
        "KTV", "酒吧", "蹦迪", "夜宵", "清吧", "夜店", "派对",
    ],
    "聚会类": [
        "聚会", "团建", "闺蜜", "兄弟聚", "应酬", "酒局",
    ],
    "秀恩爱": [
        "约会", "牵手", "鲜花", "礼物", "副驾", "纪念日", "婚礼", "婚纱", "领证",
        "求婚", "订婚", "情侣", "恋爱",
    ],
    "购物类": [
        "逛街", "超市", "菜市场", "购物", "网购", "奢侈品",
    ],
    "宠物": [
        "猫", "狗", "喵", "汪", "宠物", "铲屎",
    ],
    "享受生活": [
        "SPA", "温泉", "美容院", "按摩", "泡澡", "洗浴",
    ],
    "娱乐类": [
        "打牌", "桌游", "密室", "麻将", "剧本杀",
    ],
    "闲时周末类": [
        "追剧", "看电影", "打游戏", "外卖", "葛优躺", "音乐会", "话剧",
    ],
    "烟酒": [
        "茅台", "雪茄", "红酒", "啤酒", "白酒", "威士忌", "酒庄",
    ],
    "爬山类": [
        "爬山", "登山", "徒步",
    ],
    "车类": [
        "豪车", "跑车", "提车", "新车", "改装", "自驾",
    ],
    "技能魅力": [
        "画画", "手工", "烘焙", "钢琴", "吉他", "书法", "写字", "茶艺", "插花",
    ],
}


def infer_parent_name(detail: Dict[str, Any], maps: CategoryMaps) -> str:
    explicit = str(detail.get("grouptitle") or "").strip()
    if explicit and normalize_name(explicit) in maps.parents:
        return explicit

    text_parts = [
        str(detail.get("content") or ""),
        str(detail.get("new_content") or ""),
        str(detail.get("desc") or ""),
        str(detail.get("search_keywords") or ""),
        str(detail.get("city") or ""),
    ]
    candidates = " ".join(part for part in text_parts if part)
    for parent_name, keywords in PARENT_KEYWORDS.items():
        if any(keyword in candidates for keyword in keywords):
            if normalize_name(parent_name) in maps.parents:
                return parent_name
    return ""


def infer_child_name(detail: Dict[str, Any], parent_name: str) -> str:
    explicit_child = str(detail.get("grouptitle_sub") or "").strip()
    if explicit_child:
        return explicit_child

    hashtags = extract_hashtags(detail)
    filtered = []
    for tag in hashtags:
        tag = tag.strip()
        if not tag:
            continue
        if tag in {"我的旅行碎片", "旅行碎片", "澳大利亚", "澳洲"}:
            continue
        filtered.append(tag)
    if filtered:
        return filtered[0]

    return ""  # 无法推断子分类时返回空，由 ensure_category 直接挂到父分类


def ensure_category(
    api: AdminAPI,
    maps: CategoryMaps,
    parent_name: str,
    child_name: str,
    dry_run: bool,
) -> Optional[int]:
    parent_name = (parent_name or "").strip()
    child_name = (child_name or "").strip()

    if child_name:
        child_key = normalize_name(child_name)
        existing_child = maps.children.get(child_key)
        if existing_child:
            return int(existing_child["id"])

    if not parent_name:
        return None

    parent_key = normalize_name(parent_name)
    parent = maps.parents.get(parent_key)
    if not parent:
        if dry_run:
            log(f"[dry-run] 将创建一级分类: {parent_name}")
            return None
        parent = api.create_category(
            {"name": parent_name, "sort_order": 0, "is_visible": True}
        )
        maps.parents[parent_key] = parent
        log(f"创建一级分类: {parent_name} -> {parent['id']}")

    if not child_name:
        return int(parent["id"])

    child_key = normalize_name(child_name)
    existing_child = maps.children.get(child_key)
    if existing_child:
        return int(existing_child["id"])

    if dry_run:
        log(f"[dry-run] 将创建二级分类: {parent_name} / {child_name}")
        return int(parent["id"])

    created = api.create_category(
        {
            "name": child_name,
            "parent_id": int(parent["id"]),
            "sort_order": 0,
            "is_visible": True,
        }
    )
    maps.children[child_key] = created
    log(f"创建二级分类: {parent_name}/{child_name} -> {created['id']}")
    return int(created["id"])


def resolve_category_id(
    detail: Dict[str, Any],
    maps: CategoryMaps,
    api: AdminAPI,
    create_missing_categories: bool,
    dry_run: bool,
) -> Optional[int]:
    candidates = split_candidates(detail)
    for name in candidates:
        child = maps.children.get(normalize_name(name))
        if child:
            return int(child["id"])
    for name in candidates:
        parent = maps.parents.get(normalize_name(name))
        if parent:
            return int(parent["id"])

    if create_missing_categories:
        parent_name = infer_parent_name(detail, maps)
        child_name = infer_child_name(detail, parent_name)
        if not parent_name and child_name and normalize_name(child_name) in maps.parents:
            parent_name = child_name
            child_name = ""
        if parent_name or child_name:
            return ensure_category(api, maps, parent_name, child_name, dry_run)

    return None


def fetch_all_existing_materials(api: AdminAPI) -> List[Dict[str, Any]]:
    page = 1
    page_size = 200
    items: List[Dict[str, Any]] = []
    while True:
        data = api.list_materials(page=page, page_size=page_size)
        page_items = data.get("list", []) or []
        items.extend(page_items)
        total = int(data.get("total") or 0)
        if len(items) >= total or not page_items:
            break
        page += 1
    return items


def build_existing_indexes(items: Sequence[Dict[str, Any]]) -> Tuple[set, set]:
    url_set = set()
    title_set = set()
    for item in items:
        title = sanitize_title(str(item.get("title") or ""), 0)
        material_type = str(item.get("type") or "")
        title_set.add((title, material_type))
        for url in item.get("original_urls", []) or []:
            if url:
                url_set.add(str(url).strip())
    return url_set, title_set


def make_payload(
    detail: Dict[str, Any],
    category_id: Optional[int],
    status: str,
    show_inspiration: bool,
    show_moments: bool,
) -> Dict[str, Any]:
    source_id = int(detail["id"])
    material_type = resolve_type(detail)
    original_urls, thumbnail_url = resolve_original_urls(detail, material_type)
    preview_mov_url = resolve_preview_mov_url(detail, material_type)
    title = sanitize_title(str(detail.get("content") or detail.get("new_content") or ""), source_id)
    tags = extract_hashtags(detail)
    gender = ""
    sex = detail.get("sex")
    if sex == 1:
        gender = "male"
    elif sex == 2:
        gender = "female"

    payload: Dict[str, Any] = {
        "title": title,
        "description": resolve_description(detail),
        "type": material_type,
        "category_id": category_id or 0,
        "gender": gender,
        "tags": tags,
        "width": 0,
        "height": 0,
        "duration": 0,
        "file_size": 0,
        "original_urls": original_urls,
        "thumbnail_url": thumbnail_url,
        "watermark_url": "",
        "preview_mov_url": preview_mov_url,
        "show_inspiration": show_inspiration,
        "show_moments": show_moments,
        "status": status,
    }
    if payload["category_id"] == 0:
        payload["category_id"] = None
    return payload


def load_detail_files(details_dir: Path, limit: int) -> List[Path]:
    files = sorted(
        [path for path in details_dir.glob("*.json") if path.stem.isdigit()],
        key=lambda path: int(path.stem),
    )
    if limit > 0:
        return files[:limit]
    return files


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="将碰友详情 JSON 导入小颜圈")
    parser.add_argument("--details-dir", default=str(DETAILS_DIR))
    parser.add_argument("--api-base", default=DEFAULT_API_BASE)
    parser.add_argument("--state-file", default=None)
    parser.add_argument("--limit", type=int, default=0, help="最多处理多少条详情，0 表示不限")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--publish", action="store_true", help="导入后直接 published")
    parser.add_argument("--show-inspiration", action="store_true")
    parser.add_argument("--show-moments", action="store_true")
    parser.add_argument("--create-missing-categories", dest="create_missing_categories", action="store_true")
    parser.add_argument("--no-create-missing-categories", dest="create_missing_categories", action="store_false")
    parser.set_defaults(create_missing_categories=True)
    parser.add_argument("--no-resume", action="store_true")
    parser.add_argument("--admin-id", type=int, default=DEFAULT_ADMIN_ID)
    parser.add_argument("--admin-username", default=DEFAULT_ADMIN_USERNAME)
    parser.add_argument("--admin-role", default=DEFAULT_ADMIN_ROLE)
    parser.add_argument(
        "--upload-to-cos", action="store_true",
        help="将媒体文件下载后上传到腾讯云 COS，用 COS URL 替换碰友 CDN（需 qcloud_cos 已安装）",
    )
    parser.add_argument(
        "--rollback", action="store_true",
        help="回滚已导入的素材（从 import_state.json 读取 target_id 批量删除）",
    )
    parser.add_argument(
        "--rollback-last", type=int, default=0, metavar="N",
        help="仅回滚最近 N 条（0 表示全部）",
    )
    return parser.parse_args()


def main() -> int:
    load_dotenv(DOTENV_PATH)
    args = parse_args()
    secret = (os.getenv("XYQ_ADMIN_JWT_SECRET") or os.getenv("JWT_SECRET") or "").strip()
    if not secret:
        print("缺少环境变量 XYQ_ADMIN_JWT_SECRET 或 JWT_SECRET", file=sys.stderr)
        return 1

    details_dir = Path(args.details_dir).expanduser().resolve()
    if not details_dir.exists():
        print(f"详情目录不存在: {details_dir}", file=sys.stderr)
        return 1

    state_path = (
        Path(args.state_file).expanduser().resolve()
        if args.state_file
        else details_dir.parent / STATE_FILE
    )
    state = load_json(state_path, {"imported": {}, "skipped": {}, "failed": {}})
    imported_state: Dict[str, Any] = state.setdefault("imported", {})
    skipped_state: Dict[str, Any] = state.setdefault("skipped", {})
    failed_state: Dict[str, Any] = state.setdefault("failed", {})

    token = make_jwt(secret, args.admin_id, args.admin_username, args.admin_role)
    api = AdminAPI(args.api_base, token, args.timeout)

    # ---- 回滚模式 ----
    if args.rollback:
        imported: Dict[str, Any] = state.get("imported", {})
        if not imported:
            log("无已导入记录，无需回滚")
            return 0
        # 按 imported_at 排序，取最近 N 条
        sorted_items = sorted(
            imported.items(),
            key=lambda kv: kv[1].get("imported_at", ""),
            reverse=True,
        )
        if args.rollback_last > 0:
            sorted_items = sorted_items[:args.rollback_last]
        target_ids = [int(v["target_id"]) for _, v in sorted_items if v.get("target_id")]
        source_ids = [k for k, _ in sorted_items]
        log(f"将删除 {len(target_ids)} 条素材: material_ids={target_ids}")
        if not target_ids:
            log("没有有效的 target_id，终止")
            return 0
        try:
            api.batch_delete_materials(target_ids)
            log(f"删除成功: {len(target_ids)} 条")
        except Exception as exc:
            log(f"删除失败: {exc}")
            return 1
        # 从 state 中移除已回滚的记录
        for sid in source_ids:
            imported.pop(sid, None)
        save_json(state_path, state)
        log(f"回滚完成，已从 import_state.json 清除 {len(source_ids)} 条记录")
        return 0

    cos_uploader: Optional[CosUploader] = None
    if args.upload_to_cos:
        _id = os.getenv("COS_SECRET_ID", "").strip()
        _key = os.getenv("COS_SECRET_KEY", "").strip()
        if not _id or not _key:
            print("缺少 COS_SECRET_ID / COS_SECRET_KEY，请检查 .env.production 或环境变量", file=sys.stderr)
            return 1
        cos_uploader = CosUploader(
            _id, _key,
            os.getenv("COS_BUCKET", "xyq02871-1409098971"),
            os.getenv("COS_REGION", "ap-guangzhou"),
            os.getenv("COS_CDN_DOMAIN", ""),
        )
        log(f"COS 上传已启用: bucket={cos_uploader.bucket}")

    log("读取后台分类")
    categories = api.get_categories()
    category_maps = build_category_maps(categories)

    log("读取现有素材用于去重")
    existing_items = fetch_all_existing_materials(api)
    existing_urls, existing_title_types = build_existing_indexes(existing_items)
    log(f"现有素材: {len(existing_items)} 条")

    status = "published" if args.publish else "draft"
    detail_files = load_detail_files(details_dir, args.limit)
    if not detail_files:
        log("没有可导入的详情文件")
        return 0

    created = 0
    skipped = 0
    failed = 0

    for path in detail_files:
        detail = load_json(path, None)
        if not isinstance(detail, dict):
            continue

        source_id = str(detail.get("id") or path.stem)
        if not args.no_resume and source_id in imported_state:
            skipped += 1
            continue

        try:
            category_id = resolve_category_id(
                detail=detail,
                maps=category_maps,
                api=api,
                create_missing_categories=args.create_missing_categories,
                dry_run=args.dry_run,
            )
            payload = make_payload(
                detail=detail,
                category_id=category_id,
                status=status,
                show_inspiration=args.show_inspiration,
                show_moments=args.show_moments,
            )

            original_urls = payload.get("original_urls", []) or []
            if not original_urls:
                skipped_state[source_id] = {"reason": "empty_original_urls"}
                skipped += 1
                continue

            dedupe_hit = False
            for url in original_urls:
                if url in existing_urls:
                    dedupe_hit = True
                    break
            if (payload["title"], payload["type"]) in existing_title_types:
                dedupe_hit = True

            if dedupe_hit:
                skipped_state[source_id] = {"reason": "duplicate_remote", "title": payload["title"]}
                skipped += 1
                continue

            if args.dry_run:
                log(
                    f"[dry-run] 将导入 source_id={source_id} "
                    f"type={payload['type']} title={payload['title']}"
                )
                created += 1
                continue

            if cos_uploader:
                log(f"  上传媒体至 COS (source_id={source_id})…")
                cos_uploader.replace_urls(payload, int(source_id))

            created_material = api.create_material(payload)
            target_id = created_material.get("id")
            imported_state[source_id] = {
                "target_id": target_id,
                "title": payload["title"],
                "type": payload["type"],
                "category_id": payload["category_id"],
                "imported_at": now_text(),
            }
            for url in original_urls:
                existing_urls.add(url)
            existing_title_types.add((payload["title"], payload["type"]))
            created += 1
            log(f"导入成功 source_id={source_id} -> material_id={target_id} title={payload['title']}")
        except Exception as exc:
            failed_state[source_id] = {"reason": str(exc), "file": str(path)}
            failed += 1
            log(f"导入失败 source_id={source_id}: {exc}")

        save_json(state_path, state)

    save_json(state_path, state)
    log(f"完成: created={created}, skipped={skipped}, failed={failed}, state={state_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
