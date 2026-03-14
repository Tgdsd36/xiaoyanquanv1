#!/usr/bin/env bash
# ============================================================
#  碰友素材增量同步脚本
#  用法:
#    ./pengyou_sync.sh              # 抓取+导入（COS 上传）
#    ./pengyou_sync.sh --crawl-only  # 只抓取，不导入
#    ./pengyou_sync.sh --import-only # 只导入（使用已有详情）
#    ./pengyou_sync.sh --dry-run     # 演习模式（不实际写入）
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRAWL_SCRIPT="$SCRIPT_DIR/crawl.py"
IMPORT_SCRIPT="$SCRIPT_DIR/batch_upload_pengyou.py"
DATA_DIR="/Users/a15554022309/Documents/碰友_素材数据"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/pengyou_sync_$(date +%Y%m%d_%H%M%S).log"

# ---- 参数解析 ----
MODE_CRAWL=true
MODE_IMPORT=true
DRY_RUN=""
DETAIL_LIMIT=50       # 每次最多新抓详情数（0=不限）
IMPORT_LIMIT=0        # 每次最多导入数（0=不限）

for arg in "$@"; do
  case "$arg" in
    --crawl-only)  MODE_IMPORT=false ;;
    --import-only) MODE_CRAWL=false ;;
    --dry-run)     DRY_RUN="--dry-run" ;;
    --help|-h)
      grep '^#  ' "$0" | sed 's/^#  //'
      exit 0
      ;;
  esac
done

mkdir -p "$LOG_DIR"

# ---- 工具函数 ----
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }

log "========== 碰友素材增量同步开始 =========="
log "模式: crawl=$MODE_CRAWL  import=$MODE_IMPORT  dry_run=${DRY_RUN:-off}"
log "日志: $LOG_FILE"

# ---- 第一步：抓取详情 ----
if $MODE_CRAWL; then
  log ">>> [1/2] 增量抓取碰友详情（limit=${DETAIL_LIMIT}）"
  python3 "$CRAWL_SCRIPT" \
    --output-dir "$DATA_DIR" \
    --skip-config \
    --skip-categories \
    --skip-tags2 \
    --skip-list \
    --detail-limit "$DETAIL_LIMIT" \
    2>&1 | tee -a "$LOG_FILE" || die "抓取脚本异常退出"
  log "<<< 抓取完成"
else
  log ">>> [1/2] 跳过抓取"
fi

# ---- 第二步：导入到小颜圈 ----
if $MODE_IMPORT; then
  log ">>> [2/2] 批量导入到小颜圈（COS 上传）"
  python3 "$IMPORT_SCRIPT" \
    --details-dir "$DATA_DIR/details" \
    --publish \
    --create-missing-categories \
    --upload-to-cos \
    ${IMPORT_LIMIT:+--limit "$IMPORT_LIMIT"} \
    ${DRY_RUN} \
    2>&1 | tee -a "$LOG_FILE" || die "导入脚本异常退出"
  log "<<< 导入完成"
else
  log ">>> [2/2] 跳过导入"
fi

log "========== 同步结束 =========="
