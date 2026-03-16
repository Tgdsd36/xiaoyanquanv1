#!/usr/bin/env python3
"""碰友素材抓取脚本。

功能：
- 分页拉取列表，保存 list_cache.json
- 逐条拉取详情，保存 details/{id}.json
- 断点续跑：已有详情文件的 ID 自动跳过
- 支持 --detail-limit 限制单次新增详情数量

用法：
  python3 crawl.py --output-dir /path/to/data
  python3 crawl.py --output-dir /path/to/data --detail-limit 20
  python3 crawl.py --output-dir /path/to/data --skip-list --detail-limit 50
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.request import Request, urlopen
from urllib.error import URLError

BASE_URL = "https://zl.ljtao.cn"
HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                  "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
    "Referer": "https://zl.ljtao.cn/",
}
DEFAULT_OUTPUT_DIR = "/Users/a15554022309/Documents/碰友_素材数据"
RETRY_TIMES = 3
RETRY_DELAY = 2.0   # 秒
REQUEST_INTERVAL = 0.5  # 两次请求间隔，避免触发限流


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())


def log(msg: str) -> None:
    print(f"[{now()}] {msg}")


def api_post(path: str, data: Dict[str, Any], timeout: int = 20) -> Optional[Any]:
    """POST 请求，自动重试，返回 data 字段或 None。"""
    url = f"{BASE_URL}{path}"
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    for attempt in range(1, RETRY_TIMES + 1):
        try:
            req = Request(url, data=body, method="POST", headers=HEADERS)
            with urlopen(req, timeout=timeout) as resp:
                result = json.loads(resp.read().decode("utf-8"))
            code = result.get("code")
            if code == 200:
                return result.get("data")
            log(f"  API 返回异常 code={code} msg={result.get('msg')} (attempt {attempt})")
        except (URLError, OSError) as exc:
            log(f"  请求失败: {exc} (attempt {attempt}/{RETRY_TIMES})")
        if attempt < RETRY_TIMES:
            time.sleep(RETRY_DELAY)
    return None


def load_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


# ──────────────────────────────────────────────
# 第一步：拉取列表
# ──────────────────────────────────────────────

def fetch_list(output_dir: Path, need: int = 0, start_page: int = 1) -> List[Dict[str, Any]]:
    """分页拉取素材列表，保存到 list_cache.json，返回列表。
    need>0 时，拿到足够数量即停止翻页（用于快速测试）。
    start_page: 从第几页开始拉取（默认 1）。
    """
    cache_path = output_dir / "list_cache.json"
    all_items: List[Dict[str, Any]] = []
    page = start_page

    log("开始拉取素材列表...")
    while True:
        log(f"  拉取第 {page} 页...")
        data = api_post("/api/index/getGoodslist", {"page": page})
        if not data:
            log(f"  第 {page} 页返回空，停止")
            break

        items = data.get("data") or []
        if not items:
            break

        all_items.extend(items)
        total = int(data.get("total") or 0)
        log(f"  第 {page} 页 {len(items)} 条 | 累计 {len(all_items)}/{total}")

        if len(all_items) >= total:
            break
        if need > 0 and len(all_items) >= need:
            log(f"  已有 {len(all_items)} 条，够用，停止翻页")
            break

        page += 1
        time.sleep(REQUEST_INTERVAL)

    save_json(cache_path, all_items)
    log(f"列表已保存 {len(all_items)} 条 -> {cache_path}")
    log(f"list_next_page={page + 1}")  # 供 shell 解析，下次从此页继续
    return all_items


def load_list(output_dir: Path) -> List[Dict[str, Any]]:
    cache_path = output_dir / "list_cache.json"
    items = load_json(cache_path, [])
    log(f"使用缓存列表: {len(items)} 条 ({cache_path})")
    return items


# ──────────────────────────────────────────────
# 第二步：抓取详情
# ──────────────────────────────────────────────

def fetch_details(
    items: List[Dict[str, Any]],
    output_dir: Path,
    detail_limit: int,
) -> None:
    """对列表中的每个 ID 抓取详情，已存在的跳过。"""
    details_dir = output_dir / "details"
    details_dir.mkdir(parents=True, exist_ok=True)

    new_count = 0
    skip_count = 0
    fail_count = 0
    total = len(items)
    # 预算：本次最多新增多少条
    limit_display = str(detail_limit) if detail_limit > 0 else "不限"
    log(f"待处理列表: {total} 条 | 本次最多新增: {limit_display} 条")

    for idx, item in enumerate(items, start=1):
        if detail_limit > 0 and new_count >= detail_limit:
            log(f"已达 detail-limit={detail_limit}，停止抓取详情")
            break

        item_id = item.get("id")
        if not item_id:
            continue

        dest = details_dir / f"{item_id}.json"
        if dest.exists():
            skip_count += 1
            continue

        # 进度：列表第几条 / 总条数，已新增多少
        progress = f"[{idx}/{total}] 新增={new_count}"
        log(f"  {progress} 抓取 id={item_id}...")
        detail = api_post("/api/goods/goodsdetail", {"id": item_id})
        if not detail:
            log(f"  {progress} id={item_id} 失败，跳过")
            fail_count += 1
            time.sleep(REQUEST_INTERVAL)
            continue

        # 补充列表字段（部分字段详情里可能没有）
        for key in ("livepoto", "sex", "city"):
            if key not in detail and key in item:
                detail[key] = item[key]

        save_json(dest, detail)
        new_count += 1

        # 简单判断类型，输出提示
        type_hint = ""
        if detail.get("livepoto"):
            type_hint = "[LIVE]"
        elif detail.get("vod"):
            type_hint = "[VIDEO]"
        else:
            type_hint = "[IMAGE]"
        title = str(detail.get("content") or detail.get("new_content") or "")[:35]
        log(f"  ✓ [{idx}/{total}] 新增第{new_count}条 {type_hint} id={item_id} {title}")

        time.sleep(REQUEST_INTERVAL)

    log(f"详情抓取完成: 新增={new_count}, 跳过={skip_count}, 失败={fail_count}")


# ──────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="碰友素材爬取脚本")
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR,
                        help="数据输出目录（默认：%(default)s）")
    parser.add_argument("--detail-limit", type=int, default=50,
                        help="单次最多新抓详情数，0=不限（默认：%(default)s）")
    parser.add_argument("--list-start-page", type=int, default=1,
                        help="从第几页开始拉取列表（默认：1）")
    parser.add_argument("--skip-list", action="store_true",
                        help="跳过列表拉取，使用已有 list_cache.json")
    # 以下为 pengyou_sync.sh 传入的占位参数，保持兼容，不影响实际行为
    parser.add_argument("--skip-config", action="store_true")
    parser.add_argument("--skip-categories", action="store_true")
    parser.add_argument("--skip-tags2", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    log(f"========== 碰友抓取开始 ==========")
    log(f"输出目录: {output_dir}")
    log(f"detail-limit: {args.detail_limit} (0=不限)")
    log(f"skip-list: {args.skip_list}")

    # 第一步：列表
    if args.skip_list:
        items = load_list(output_dir)
    else:
        items = fetch_list(output_dir, need=args.detail_limit, start_page=args.list_start_page)

    if not items:
        log("列表为空，退出")
        return 1

    # 第二步：详情
    fetch_details(items, output_dir, args.detail_limit)

    log("========== 抓取完成 ==========")
    return 0


if __name__ == "__main__":
    sys.exit(main())
