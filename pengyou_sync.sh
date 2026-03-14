#!/usr/bin/env bash
# ============================================================
#  碰友素材增量同步脚本
#  用法:
#    ./pengyou_sync.sh                    # 抓取+导入（COS 上传）
#    ./pengyou_sync.sh --crawl-only       # 只抓取，不导入
#    ./pengyou_sync.sh --import-only      # 只导入（使用已有详情）
#    ./pengyou_sync.sh --dry-run          # 演习模式（不实际写入）
#    ./pengyou_sync.sh --rollback         # 回滚全部已导入素材
#    ./pengyou_sync.sh --rollback --last 10  # 只回滚最近 10 条
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
MODE_ROLLBACK=false
DRY_RUN=""
DETAIL_LIMIT=50       # 每次最多新抓详情数（0=不限）
IMPORT_LIMIT=0        # 每次最多导入数（0=不限）
ROLLBACK_LAST=0       # 回滚最近 N 条（0=全部）

_NEXT_IS_LAST=false
for arg in "$@"; do
  if $_NEXT_IS_LAST; then
    ROLLBACK_LAST="$arg"
    _NEXT_IS_LAST=false
    continue
  fi
  case "$arg" in
    --crawl-only)  MODE_IMPORT=false ;;
    --import-only) MODE_CRAWL=false ;;
    --dry-run)     DRY_RUN="--dry-run" ;;
    --rollback)    MODE_ROLLBACK=true; MODE_CRAWL=false; MODE_IMPORT=false ;;
    --last)        _NEXT_IS_LAST=true ;;
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
log "模式: crawl=$MODE_CRAWL  import=$MODE_IMPORT  rollback=$MODE_ROLLBACK  dry_run=${DRY_RUN:-off}"
log "日志: $LOG_FILE"

# ---- 回滚模式 ----
if $MODE_ROLLBACK; then
  ROLLBACK_ARGS="--rollback"
  [[ "$ROLLBACK_LAST" -gt 0 ]] && ROLLBACK_ARGS="$ROLLBACK_ARGS --rollback-last $ROLLBACK_LAST"
  log ">>> 回滚模式: 将删除已导入素材（last=${ROLLBACK_LAST:-全部}）"
  python3 "$IMPORT_SCRIPT" \
    --details-dir "$DATA_DIR/details" \
    $ROLLBACK_ARGS \
    2>&1 | tee -a "$LOG_FILE" || die "回滚脚本异常退出"
  log "<<< 回滚完成"
  log "========== 同步结束 =========="
  exit 0
fi

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
