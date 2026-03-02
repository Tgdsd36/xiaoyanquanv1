#!/bin/bash
#
# 小颜圈 - 交互式启动脚本
# 输入数字选择服务，每个服务在新终端窗口中运行
#

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$BASE_DIR/xiaoyanquan-server"
APP_DIR="$BASE_DIR/xiaoyanquan"
ADMIN_DIR="$BASE_DIR/xiaoyanquan-admin"
FLUTTER="$HOME/development/flutter/bin/flutter"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 在新 Terminal 窗口中执行命令
open_new_terminal() {
    local title="$1"
    local cmd="$2"
    osascript <<EOF
tell application "Terminal"
    activate
    do script "$cmd"
end tell
EOF
}

# 启动后端
start_server() {
    echo -e "${GREEN}[✓] 正在新窗口启动 Go 后端...${NC}"
    open_new_terminal "小颜圈-后端" "cd $SERVER_DIR && export PATH=/Applications/ServBay/script/alias:\$PATH && echo '🚀 启动 Go 后端 (热重载)...' && $HOME/go/bin/air"
    echo -e "${GREEN}[✓] 后端窗口已打开 → http://localhost:8080${NC}"
}

# 启动 Flutter
start_app() {
    echo -e "${GREEN}[✓] 正在新窗口启动 Flutter 客户端...${NC}"
    open_new_terminal "小颜圈-客户端" "cd $APP_DIR && echo '📱 启动 Flutter 客户端 (macOS)...' && $FLUTTER run -d macos"
    echo -e "${GREEN}[✓] Flutter 窗口已打开${NC}"
}

# 启动管理后台
start_admin() {
    echo -e "${GREEN}[✓] 正在新窗口启动 React 管理后台...${NC}"
    open_new_terminal "小颜圈-管理后台" "cd $ADMIN_DIR && echo '🖥️  启动 React 管理后台...' && npm run dev"
    echo -e "${GREEN}[✓] 管理后台窗口已打开 → http://localhost:5173${NC}"
}

# 全部启动
start_all() {
    start_server
    sleep 1
    start_admin
    sleep 1
    start_app
}

# 显示菜单
show_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}    ${BOLD}小颜圈 XiaoYanQuan${NC}            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    服务启动管理面板              ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}1${NC} - 启动 Go 后端       :8080   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}2${NC} - 启动 Flutter 客户端        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}3${NC} - 启动 React 管理后台 :5173  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}4${NC} - 全部启动                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${RED}0${NC} - 退出                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}提示: 确保 ServBay 中 PostgreSQL 和 Redis 已开启${NC}"
    echo ""
}

# 主循环
while true; do
    show_menu
    echo -ne "${BOLD}请输入数字选择: ${NC}"
    read -r choice

    case "$choice" in
        1) start_server ;;
        2) start_app ;;
        3) start_admin ;;
        4) start_all ;;
        0)
            echo -e "${CYAN}再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 0-4${NC}"
            ;;
    esac

    echo ""
    echo -ne "按回车返回菜单..."
    read -r
done
