#!/bin/bash

# 👉 接口名称 & 限制阈值（GiB）
INTERFACE="ens5"
LIMIT_GB=210

# 📁 状态与历史日志
STATE_FILE="/var/log/xray_traffic_limit_state.txt"
HISTORY_LOG="/var/log/xray_traffic_history.log"
LAST_MONTH_FILE="/var/log/last_month_traffic.txt"

# 📨 Telegram 配置
BOT_TOKEN="YOUR_BOT_TOKEN"
CHAT_ID="YOUR_CHAT_ID"

# 📆 当前时间
NOW=$(date '+%Y-%m-%d %H:%M:%S')
YEAR_MONTH=$(date +%Y-%m)
DAY=$(date +%d)

# 🚩 单位转换函数（统一转 GiB）
parse_gib() {
  local value unit result
  value=$(echo "$1" | sed 's/,/./')
  unit=$2
  case "$unit" in
    KiB) result=$(awk "BEGIN { printf \"%.6f\", $value / 1024 / 1024 }") ;;
    MiB) result=$(awk "BEGIN { printf \"%.6f\", $value / 1024 }") ;;
    GiB) result=$value ;;
    TiB) result=$(awk "BEGIN { printf \"%.6f\", $value * 1024 }") ;;
    *) result=0 ;;
  esac
  echo "$result"
}

# 📊 获取当月 RX / TX（带单位）
read RX_VAL RX_UNIT TX_VAL TX_UNIT <<< $(vnstat -m | awk -v ym="$YEAR_MONTH" '
  $1 == ym { print $2, $3, $5, $6; exit }
')

RX_GB=$(parse_gib "$RX_VAL" "$RX_UNIT")
TX_GB=$(parse_gib "$TX_VAL" "$TX_UNIT")

# ❗ 无法解析流量
if [[ -z "$RX_GB" || -z "$TX_GB" ]]; then
  echo "$NOW | ❌ 无法解析流量数据，退出"
  exit 1
fi

# 📌 记录流量基线或计算当月流量
if [[ "$DAY" == "01" ]]; then
    # 记录上月流量基线
    LAST_MONTH_RX=$RX_GB
    LAST_MONTH_TX=$TX_GB
    echo "$LAST_MONTH_RX $LAST_MONTH_TX" > $LAST_MONTH_FILE
    CURRENT_RX=0
    CURRENT_TX=0
else
    # 读取上月流量基线，若文件不存在则设为 0
    if [[ -f $LAST_MONTH_FILE ]]; then
        read LAST_MONTH_RX LAST_MONTH_TX < $LAST_MONTH_FILE
    else
        LAST_MONTH_RX=0
        LAST_MONTH_TX=0
    fi
    # 计算当月实际流量
    CURRENT_RX=$(awk -v rx="$RX_GB" -v last="$LAST_MONTH_RX" 'BEGIN { print rx - last }')
    CURRENT_TX=$(awk -v tx="$TX_GB" -v last="$LAST_MONTH_TX" 'BEGIN { print tx - last }')
fi

# ✅ 记录日志
echo "$NOW | RX: ${RX_GB} GiB | TX: ${TX_GB} GiB | Current RX: ${CURRENT_RX} GiB | Current TX: ${CURRENT_TX} GiB" >> "$HISTORY_LOG"

# 📌 每月1日自动恢复
if [[ "$DAY" == "01" ]]; then
  if [[ -f "$STATE_FILE" ]]; then
    systemctl restart xray
    rm -f "$STATE_FILE"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="$CHAT_ID" \
      -d text="📅 $NOW
✅ 已进入新月份，Xray 已自动恢复运行。"
  fi
  exit 0
fi

# ⚠️ 判断是否超出限制
TX_VAL=$CURRENT_TX
LIMIT_REACHED=$(awk -v tx="$TX_VAL" -v limit="$LIMIT_GB" 'BEGIN { print (tx >= limit) ? 1 : 0 }')

if [[ "$LIMIT_REACHED" == "1" ]]; then
  if [[ ! -f "$STATE_FILE" ]]; then
    systemctl stop xray
    touch "$STATE_FILE"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="$CHAT_ID" \
      -d text="🚫 $NOW
⚠️ 本月出站流量已达上限 ${LIMIT_GB} GiB
当前出站流量：${TX_VAL} GiB
Xray 已停止运行。"
  fi
  exit 0
else
  [[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE"
fi

# ✋ 手动运行信息返回
if [[ "$1" == "manual" ]]; then
  XRAY_STATUS=$(systemctl is-active xray | grep -q "active" && echo "运行中" || echo "已停止")
  TOTAL_VAL=$(awk -v rx="$CURRENT_RX" -v tx="$CURRENT_TX" 'BEGIN { printf "%.2f", rx + tx }')

  # 获取平均速率（原始值如 215 kbit/s）
  AVG_RAW=$(vnstat -m | awk -v ym="$YEAR_MONTH" '$1 == ym { print $(NF-1), $NF; exit }')
  AVG_VALUE=$(echo "$AVG_RAW" | awk '{print $1}')
  AVG_UNIT=$(echo "$AVG_RAW" | awk '{print $2}')

  # 转换为 Mbps（统一显示）
  AVG_MBPS=$(awk -v v="$AVG_VALUE" -v u="$AVG_UNIT" '
    BEGIN {
      if (u == "kbit/s") printf "%.2f Mbps", v / 1000;
      else if (u == "Mbit/s") printf "%.2f Mbps", v;
      else if (u == "Gbit/s") printf "%.2f Mbps", v * 1000;
      else print v " " u;
    }')

  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="📊 流量统计 - ${NOW}
🔸 入站流量（RX）：${CURRENT_RX} GiB
🔹 出站流量（TX）：${CURRENT_TX} GiB
📦 总流量：${TOTAL_VAL} GiB
🚀 平均速率：${AVG_MBPS}
⚙️ Xray 状态：${XRAY_STATUS}"
fi

exit 0
