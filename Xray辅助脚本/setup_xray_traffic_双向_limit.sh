#!/bin/bash

set -e

echo "🔧 设置 Xray 双向流量限制脚本"

# 📥 交互式输入
read -p "请输入网络接口名称（如 ens5）: " INTERFACE
read -p "请输入双向流量限制（GiB，例如 210）: " LIMIT_GB
read -p "请输入 Telegram Bot Token: " BOT_TOKEN
read -p "请输入 Telegram Chat ID: " CHAT_ID

SCRIPT_PATH="/usr/local/bin/xray-traffic-limit.sh"
STATE_FILE="/var/log/xray_traffic_limit_state.txt"
HISTORY_LOG="/var/log/xray_traffic_history.log"

# 🛠️ 生成脚本
echo "📄 正在生成脚本到 $SCRIPT_PATH ..."
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

INTERFACE="${INTERFACE}"
LIMIT_GB=${LIMIT_GB}
STATE_FILE="${STATE_FILE}"
HISTORY_LOG="${HISTORY_LOG}"

BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

NOW=\$(date '+%Y-%m-%d %H:%M:%S')
YEAR_MONTH=\$(date +%Y-%m)
DAY=\$(date +%d)

read RX_GB TX_GB <<< \$(vnstat -m | awk -v ym="\$YEAR_MONTH" '
  \$1 == ym {
    gsub(",", ".", \$2); gsub(",", ".", \$5);
    print \$2, \$5;
    exit
}')

if [[ -z "\$RX_GB" || -z "\$TX_GB" ]]; then
  echo "\$NOW | ❌ 无法解析流量数据，退出"
  exit 1
fi

echo "\$NOW | RX: \${RX_GB} GiB | TX: \${TX_GB} GiB" >> "\$HISTORY_LOG"

if [[ "\$DAY" == "01" ]]; then
  if [[ -f "\$STATE_FILE" ]]; then
    systemctl restart xray
    rm -f "\$STATE_FILE"
    curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \\
      -d chat_id="\$CHAT_ID" \\
      -d text="📅 \$NOW
✅ 已进入新月份，Xray 已自动恢复运行。"
  fi
  exit 0
fi

RX_VAL=\$(echo "\$RX_GB" | grep -oE '^[0-9]+(\\.[0-9]+)?\$')
TX_VAL=\$(echo "\$TX_GB" | grep -oE '^[0-9]+(\\.[0-9]+)?\$')

if [[ -z "\$RX_VAL" || -z "\$TX_VAL" ]]; then
  echo "❌ 流量数据无效"
  exit 1
fi

TOTAL_VAL=\$(awk -v rx="\$RX_VAL" -v tx="\$TX_VAL" 'BEGIN { printf "%.2f", rx + tx }')

LIMIT_REACHED=\$(awk -v total="\$TOTAL_VAL" -v limit="\$LIMIT_GB" 'BEGIN { print (total >= limit) ? 1 : 0 }')

if [[ "\$LIMIT_REACHED" == "1" ]]; then
  if [[ ! -f "\$STATE_FILE" ]]; then
    systemctl stop xray
    touch "\$STATE_FILE"
    curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \\
      -d chat_id="\$CHAT_ID" \\
      -d text="🚫 \$NOW
⚠️ 本月双向流量已达上限 \${LIMIT_GB} GiB
🔸 入站 RX：\${RX_GB} GiB
🔹 出站 TX：\${TX_GB} GiB
📦 总计：\${TOTAL_VAL} GiB
Xray 已停止运行。"
  fi
  exit 0
else
  [[ -f "\$STATE_FILE" ]] && rm -f "\$STATE_FILE"
fi

if [[ "\$1" == "manual" ]]; then
  XRAY_STATUS=\$(systemctl is-active xray | grep -q "active" && echo "运行中" || echo "已停止")

  AVG_RAW=\$(vnstat -m | awk -v ym="\$YEAR_MONTH" '\$1 == ym { print \$(NF-1), \$NF; exit }')
  AVG_VALUE=\$(echo "\$AVG_RAW" | awk '{print \$1}')
  AVG_UNIT=\$(echo "\$AVG_RAW" | awk '{print \$2}')

  AVG_MBPS=\$(awk -v v="\$AVG_VALUE" -v u="\$AVG_UNIT" '
    BEGIN {
      if (u == "kbit/s") printf "%.2f Mbps", v / 1000;
      else if (u == "Mbit/s") printf "%.2f Mbps", v;
      else if (u == "Gbit/s") printf "%.2f Mbps", v * 1000;
      else print v " " u;
    }')

  curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \\
    -d chat_id="\${CHAT_ID}" \\
    -d text="📊 流量统计 - \${NOW}
🔸 入站流量（RX）：\${RX_GB} GiB
🔹 出站流量（TX）：\${TX_GB} GiB
📦 总流量：\${TOTAL_VAL} GiB
🚀 平均速率：\${AVG_MBPS}
⚙️ Xray 状态：\${XRAY_STATUS}"
fi

exit 0
EOF

chmod +x "$SCRIPT_PATH"

# ⏱️ 设置 crontab（root 用户）
echo "🕒 正在设置定时任务..."

(
crontab -l 2>/dev/null | grep -v 'xray-traffic-limit.sh'
echo "0 */4 * * 1-5 root $SCRIPT_PATH"
echo "0 * * * 6,7 root $SCRIPT_PATH"
echo "30 17 * * 5 root $SCRIPT_PATH manual"
echo "50 23 * * 7 root $SCRIPT_PATH manual"
) | sudo tee /etc/cron.d/xray-traffic-limit > /dev/null

echo "✅ 安装完成！"
echo "📍 脚本位置：$SCRIPT_PATH"
echo "📄 日志文件：$HISTORY_LOG"
