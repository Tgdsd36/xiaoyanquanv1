#!/bin/bash
#
# 碰友素材同步 - 交互式管理脚本
#

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CRAWL_SCRIPT="$BASE_DIR/crawl.py"
IMPORT_SCRIPT="$BASE_DIR/batch_upload_pengyou.py"
DATA_DIR="$HOME/Documents/碰友_素材数据"
ENV_FILE="$BASE_DIR/xiaoyanquan-server/.env.production"
LOG_DIR="$BASE_DIR/logs"
PYTHON="$BASE_DIR/venv/bin/python3"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 读取 JWT_SECRET
load_secret() {
    if [[ -f "$ENV_FILE" ]]; then
        local val
        val=$(grep -E '^(JWT_SECRET|XYQ_ADMIN_JWT_SECRET)=' "$ENV_FILE" | head -1 | cut -d= -f2-)
        echo "$val"
    fi
}

# 确保日志目录存在
mkdir -p "$LOG_DIR"

log_file() {
    echo "$LOG_DIR/sync_$(date +%Y%m%d_%H%M%S).log"
}

run_with_log() {
    local log="$(log_file)"
    echo -e "${CYAN}>>> 日志: $log${NC}"
    echo ""
    "$@" 2>&1 | tee "$log"
}

# ── 各操作 ────────────────────────────────────────

do_crawl() {
    echo -e "${GREEN}[抓取] 增量拉取碰友素材详情（limit=50）${NC}"
    run_with_log "$PYTHON" "$CRAWL_SCRIPT" \
        --output-dir "$DATA_DIR" \
        --skip-list \
        --detail-limit 50
}

do_crawl_full() {
    echo -e "${GREEN}[抓取] 拉取列表 + 详情（limit=100）${NC}"
    run_with_log "$PYTHON" "$CRAWL_SCRIPT" \
        --output-dir "$DATA_DIR" \
        --detail-limit 100
}

do_import_dryrun() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi
    echo -e "${GREEN}[导入-演习] dry-run 预览，不写入任何数据${NC}"
    run_with_log env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
        --details-dir "$DATA_DIR/details" \
        --dry-run
}

do_import_draft() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi
    echo -e "${GREEN}[导入-草稿] 导入为 draft，不上传 COS${NC}"
    run_with_log env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
        --details-dir "$DATA_DIR/details"
}

do_import_publish() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi
    echo -e "${GREEN}[导入-发布] published + 投放灵感/朋友圈 + COS 转存${NC}"
    run_with_log env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
        --details-dir "$DATA_DIR/details" \
        --publish \
        --show-inspiration \
        --show-moments \
        --create-missing-categories \
        --upload-to-cos
}

do_sync_incremental() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi
    echo -e "${GREEN}[增量同步] 跳过列表，只抓新详情 → 导入 → 发布 → COS 转存${NC}"
    local log="$(log_file)"
    echo -e "${CYAN}>>> 日志: $log${NC}"
    echo ""
    {
        echo "===== [1/2] 增量抓取（skip-list, limit=50）====="
        "$PYTHON" "$CRAWL_SCRIPT" \
            --output-dir "$DATA_DIR" \
            --skip-list \
            --detail-limit 50

        echo ""
        echo "===== [2/2] 导入 ====="
        env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
            --details-dir "$DATA_DIR/details" \
            --publish \
            --show-inspiration \
            --show-moments \
            --create-missing-categories \
            --upload-to-cos
    } 2>&1 | tee "$log"
}

do_sync_full() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi
    echo -e "${GREEN}[完整同步] 拉列表 + 抓详情 + 导入 + 发布 + COS 转存${NC}"
    local log="$(log_file)"
    echo -e "${CYAN}>>> 日志: $log${NC}"
    echo ""
    {
        echo "===== [1/2] 完整抓取（拉列表 + 详情, limit=100）====="
        "$PYTHON" "$CRAWL_SCRIPT" \
            --output-dir "$DATA_DIR" \
            --detail-limit 100

        echo ""
        echo "===== [2/2] 导入 ====="
        env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
            --details-dir "$DATA_DIR/details" \
            --publish \
            --show-inspiration \
            --show-moments \
            --create-missing-categories \
            --upload-to-cos
    } 2>&1 | tee "$log"
}

do_sync_all() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi

    local BATCH=100
    local CURSOR_FILE="$DATA_DIR/list_page_cursor.txt"

    # 读取上次已存游标
    local list_page=1
    if [[ -f "$CURSOR_FILE" ]]; then
        list_page=$(cat "$CURSOR_FILE" 2>/dev/null || echo 1)
        echo -e "${CYAN}ℹ️  上次进度: 列表第 ${list_page} 页。直接继续。（删除 $CURSOR_FILE 可重置）${NC}"
    fi

    echo -e "${YELLOW}⚠️  分批循环模式：每批 $BATCH 条，边抓边导入，直到没有新数据${NC}"
    echo -ne "确认继续？(y/N): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        return 0
    fi

    local log
    log="$(log_file)"
    local round=0 total_new=0 new_count list_next_page
    local tmp_crawl
    tmp_crawl=$(mktemp)

    echo -e "${GREEN}[分批循环同步] 每批 $BATCH 条，从列表第 ${list_page} 页起抓取导入${NC}"
    echo -e "${CYAN}>>> 日志: $log${NC}"
    echo ""

    while true; do
        round=$((round + 1))
        echo -e "\n${CYAN}====== 第 ${round} 轮（列表第 $list_page 页起）======${NC}" | tee -a "$log"

        # ── 抓取（每轮从不同页拉列表）──
        > "$tmp_crawl"
        echo "--- [拉列表 page=$list_page, limit=$BATCH] ---" | tee -a "$log"
        PYTHONUNBUFFERED=1 "$PYTHON" "$CRAWL_SCRIPT" \
            --output-dir "$DATA_DIR" \
            --list-start-page "$list_page" \
            --detail-limit "$BATCH" 2>&1 | tee -a "$tmp_crawl" "$log"

        # 解析本轮新增详情数 & 下一页码
        new_count=$(grep -oE '新增=[0-9]+' "$tmp_crawl" | tail -1 | cut -d= -f2)
        new_count="${new_count:-0}"
        list_next_page=$(grep -oE 'list_next_page=[0-9]+' "$tmp_crawl" | tail -1 | cut -d= -f2)
        list_next_page="${list_next_page:-$((list_page + 1))}"

        total_new=$((total_new + new_count))
        echo -e "${CYAN}>>> 本轮新增详情: $new_count 条 | 累计: $total_new 条 | 下轮起始页: $list_next_page${NC}" | tee -a "$log"

        # 将游标写入文件（无论本轮有没有新数据都推进）
        echo "$list_next_page" > "$CURSOR_FILE"
        list_page="$list_next_page"

        # 本轮没有新详情 → 全部完成，不再执行导入
        if [[ "$new_count" -eq 0 ]]; then
            echo -e "\n${GREEN}✔ 没有更多新详情，循环结束！共处理 $total_new 条新详情${NC}" | tee -a "$log"
            echo -e "${CYAN}>>> 记录已存: 下次执行 a 将从列表第 $list_page 页继续${NC}" | tee -a "$log"
            break
        fi

        # ── 导入（只在有新数据时执行）──
        echo "--- [导入到小颜圈] ---" | tee -a "$log"
        PYTHONUNBUFFERED=1 env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
            --details-dir "$DATA_DIR/details" \
            --publish \
            --show-inspiration \
            --show-moments \
            --create-missing-categories \
            --upload-to-cos 2>&1 | tee -a "$log"
    done

    rm -f "$tmp_crawl"
}

do_rollback_last() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi
    echo -ne "${YELLOW}回滚最近几条？（输入数字，默认10）: ${NC}"
    read -r n
    n="${n:-10}"
    echo -e "${YELLOW}[回滚] 将删除最近 $n 条已导入素材...${NC}"
    run_with_log env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
        --details-dir "$DATA_DIR/details" \
        --rollback \
        --rollback-last "$n"
}

do_rollback_all() {
    local secret
    secret="$(load_secret)"
    if [[ -z "$secret" ]]; then
        echo -e "${RED}[错误] 未找到 JWT_SECRET，请检查 $ENV_FILE${NC}"
        return 1
    fi
    echo -ne "${RED}确认回滚全部已导入素材？(y/N): ${NC}"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        return 0
    fi
    echo -e "${RED}[回滚] 删除全部已导入素材...${NC}"
    run_with_log env XYQ_ADMIN_JWT_SECRET="$secret" "$PYTHON" "$IMPORT_SCRIPT" \
        --details-dir "$DATA_DIR/details" \
        --rollback
}

show_data_stats() {
    echo -e "${CYAN}── 数据目录统计 ──────────────────────────${NC}"
    if [[ -d "$DATA_DIR/details" ]]; then
        local cnt
        cnt=$(ls "$DATA_DIR/details"/*.json 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  详情文件: ${GREEN}$cnt 条${NC}  ($DATA_DIR/details)"
    else
        echo -e "  详情目录不存在: $DATA_DIR/details"
    fi
    if [[ -f "$DATA_DIR/import_state.json" ]]; then
        local imported
        imported=$("$PYTHON" -c "import json; d=json.load(open('$DATA_DIR/import_state.json')); print(len(d.get('imported',{})))" 2>/dev/null || echo "?")
        echo -e "  已导入素材: ${GREEN}$imported 条${NC}  (import_state.json)"
    fi
    if [[ -f "$DATA_DIR/list_page_cursor.txt" ]]; then
        local cursor
        cursor=$(cat "$DATA_DIR/list_page_cursor.txt" 2>/dev/null || echo "?")
        echo -e "  全量同步游标: ${YELLOW}列表第 $cursor 页${NC}  (list_page_cursor.txt)"
    fi
    echo -e "${CYAN}─────────────────────────────────────────${NC}"
}

# ── 菜单 ─────────────────────────────────────────

show_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}    ${BOLD}碰友素材同步管理${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${CYAN}── 爬取 ──────────────────────${NC}       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}1${NC} - 增量抓取详情（skip-list）       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}2${NC} - 完整抓取（列表 + 详情）         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${CYAN}── 导入 ──────────────────────${NC}       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}3${NC} - dry-run 预览（不写入）          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}4${NC} - 导入为草稿（draft）             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}5${NC} - 导入并发布 + COS 转存           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${CYAN}── 一键同步 ──────────────────${NC}       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}6${NC} - 增量同步（skip-list + 发布）    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}9${NC} - 完整同步（拉列表+详情+发布）    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}a${NC} - 全量同步（不限条数，全部导入） ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${CYAN}── 回滚 ──────────────────────${NC}       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}7${NC} - 回滚最近 N 条                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${RED}8${NC} - 回滚全部已导入素材               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${RED}0${NC} - 退出                             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                       ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    show_data_stats
    echo ""
}

# ── 主循环 ────────────────────────────────────────

while true; do
    show_menu
    echo -ne "${BOLD}请输入数字选择: ${NC}"
    read -r choice

    case "$choice" in
        1) do_crawl ;;
        2) do_crawl_full ;;
        3) do_import_dryrun ;;
        4) do_import_draft ;;
        5) do_import_publish ;;
        6) do_sync_incremental ;;
        9) do_sync_full ;;
        a|A) do_sync_all ;;
        7) do_rollback_last ;;
        8) do_rollback_all ;;
        0)
            echo -e "${CYAN}再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 0-9 / a${NC}"
            ;;
    esac

    echo ""
    echo -ne "按回车返回菜单..."
    read -r
done
