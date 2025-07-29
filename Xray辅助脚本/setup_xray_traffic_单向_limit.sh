#!/bin/bash

CONFIG_FILE="/etc/xray_traffic_config.conf"
STATE_FILE="/var/log/xray_traffic_limit_state.txt"
HISTORY_LOG="/var/log/xray_traffic_history.log"

# 🛠️ 首次运行交互设置
if [ ! -f "$CONFIG_FILE" ]; then
  echo "首次运行，开始设置配置参数："

  read -rp "请输入网络接口名称（例如 ens5）: " INTERFACE
  read -rp "请输入出站流量限制阈值（GiB，例如 210）: " LIMIT_GB
  read -rp "请输入 Telegram Bot Token: " BOT_TOKEN
  read -rp "请输入 Telegram Chat ID: " CHAT_ID

  cat > "$CONFIG_FILE" <<EOF
INTERFACE="$INTERFACE"
LIMIT_GB="$LIMIT_GB"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
EOF

  echo "✅ 配置已保存到 $CONFIG_FILE"
else
  # 加载配置
  source "$CONFIG_FILE"
fi

# 📆 当前时间
NOW=$(date '+%Y-%m-%d %H:%M:%S')
YEAR_MONTH=$(date +%Y-%m)
DAY=$(date +%d)

# 📊 获取当月 RX / TX（GiB）
read RX_GB TX_GB <<< $(vnstat -i "$INTERFACE" -m | awk -v ym="$YEAR_MONTH" '
  $1 == ym {
    gsub(",", ".", $2); gsub(",", ".", $5);
    print $2, $5;
    exit
}')

# ❗ 无法解析流量
if [[ -z "$RX_GB" || -z "$TX_GB" ]]; then
  echo "$NOW | ❌ 无法解析流量数据，退出"
  exit 1
fi

# ✅ 记录日志
echo "$NOW | RX: ${RX_GB} GiB | TX: ${TX_GB} GiB" >> "$HISTORY_LOG"

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
TX_VAL=$(echo "$TX_GB" | grep -oE '^[0-9]+(\.[0-9]+)?$')
if [[ -z "$TX_VAL" ]]; then
  echo "❌ TX 数据无效"
  exit 1
fi

LIMIT_REACHED=$(awk -v tx="$TX_VAL" -v limit="$LIMIT_GB" 'BEGIN { print (tx >= limit) ? 1 : 0 }')

if [[ "$LIMIT_REACHED" == "1" ]]; then
  if [[ ! -f "$STATE_FILE" ]]; then
    systemctl stop xray
    touch "$STATE_FILE"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="$CHAT_ID" \
      -d text="🚫 $NOW
⚠️ 本月出站流量已达上限 ${LIMIT_GB} GiB
当前出站流量：${TX_GB} GiB
Xray 已停止运行。"
  fi
  exit 0
else
  [[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE"
fi

# ✋ 手动运行信息返回
if [[ "$1" == "manual" ]]; then
  XRAY_STATUS=$(systemctl is-active xray | grep -q "active" && echo "运行中" || echo "已停止")
  TOTAL_VAL=$(awk -v rx="$RX_GB" -v tx="$TX_GB" 'BEGIN { printf "%.2f", rx + tx }')

  # 获取平均速率
  AVG_RAW=$(vnstat -i "$INTERFACE" -m | awk -v ym="$YEAR_MONTH" '$1 == ym { print $(NF-1), $NF; exit }')
  AVG_VALUE=$(echo "$AVG_RAW" | awk '{print $1}')
  AVG_UNIT=$(echo "$AVG_RAW" | awk '{print $2}')

  # 转换为 Mbps
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
🔸 入站流量（RX）：${RX_GB} GiB
🔹 出站流量（TX）：${TX_GB} GiB
📦 总流量：${TOTAL_VAL} GiB
🚀 平均速率：${AVG_MBPS}
⚙️ Xray 状态：${XRAY_STATUS}"
fi

exit 0
