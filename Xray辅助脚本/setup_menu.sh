#!/usr/bin/env bash

set -e

# 主菜单脚本
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 子脚本路径
ONE_WAY_SCRIPT="${SCRIPT_DIR}/setup_xray_traffic_\u5355\u5411_limit.sh"
TWO_WAY_SCRIPT="${SCRIPT_DIR}/setup_xray_traffic_\u53cc\u5411_limit.sh"
BOT_SCRIPT="${SCRIPT_DIR}/setup_xray_bot.sh"

function check_file() {
  if [[ ! -x "$1" ]]; then
    echo "\u26a0\ufe0f \u672a\u627e\u5230\u6216\u65e0\u6267\u884c\u6743\u9650: $1"
    exit 1
  fi
}

function install_one_way() {
  check_file "$ONE_WAY_SCRIPT"
  echo "\ud83d\ude80 \u6267\u884c\u5355\u5411\u6d41\u91cf\u9650\u5236\u811a\u672c..."
  bash "$ONE_WAY_SCRIPT"
}

function install_two_way() {
  check_file "$TWO_WAY_SCRIPT"
  echo "\ud83d\ude80 \u6267\u884c\u53cc\u5411\u6d41\u91cf\u9650\u5236\u811a\u672c..."
  bash "$TWO_WAY_SCRIPT"
}

function install_bot() {
  check_file "$BOT_SCRIPT"
  echo "\ud83e\uddd1\u200d\ud83e\udd16 \u6267\u884c Telegram Bot \u5b89\u88c5..."
  bash "$BOT_SCRIPT"
}

function show_menu() {
  clear
  echo "=============================="
  echo "🌐 Xray 辅助脚本安装菜单"
  echo "=============================="
  echo "1. 单向流量限制脚本"
  echo "2. 双向流量限制脚本"
  echo "3. Telegram Bot 安装"
  echo "4. 退出"
  echo "=============================="
  read -rp "请选择 [1-4]: " choice

  case "$choice" in
    1) install_one_way ;;
    2) install_two_way ;;
    3) install_bot ;;
    4) echo "\u9000\u51fa\u7a0b\u5e8f..." && exit 0 ;;
    *) echo "\u9519\u8bef\uff0c\u8bf7\u91cd\u8bd5..." && sleep 1 && show_menu ;;
  esac
}

show_menu
