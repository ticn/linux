#!/bin/bash

INSTALL_PATH="/usr/local/bin/xray_traffic_limit.sh"
CONFIG_FILE="/etc/xray_traffic_limit.conf"
STATE_FILE="/var/log/xray_traffic_limit_state.txt"
HISTORY_LOG="/var/log/xray_traffic_history.log"

echo "📦 正在安装 Xray 流量限制控制器..."

# 交互式设置
read -rp "🧩 请输入网卡名称（如 ens5）: " INTERFACE
read -rp "📊 请输入接收流量限制 (GiB): " RX_LIMIT
read -rp "📤 请输入发送流量限制 (GiB): " TX_LIMIT

echo "⚙️ 请选择触发操作类型："
select ACTION in "关闭 systemctl 管理的 Xray 服务" "关闭 docker 管理的 Xray 服务" "关机服务器"; do
  case $REPLY in
    1) MODE="systemctl" && break ;;
    2) MODE="docker" && break ;;
    3) MODE="shutdown" && break ;;
    *) echo "无效选择，请重新输入。" ;;
  esac
done

# 保存配置
cat > "$CONFIG_FILE" <<EOF
INTERFACE=$INTERFACE
RX_LIMIT=$RX_LIMIT
TX_LIMIT=$TX_LIMIT
MODE=$MODE
EOF

# 写入主脚本
cat > "$INSTALL_PATH" <<'EOF'
#!/bin/bash

CONFIG_FILE="/etc/xray_traffic_limit.conf"
STATE_FILE="/var/log/xray_traffic_limit_state.txt"
HISTORY_LOG="/var/log/xray_traffic_history.log"
[ -f "$CONFIG_FILE" ] || exit 1
source "$CONFIG_FILE"

# 获取总接收和发送流量
rx=$(awk -v iface="$INTERFACE" '$1 ~ iface {gsub(/:/,"",$1); sum+=$2} END{print sum}' /proc/net/dev)
tx=$(awk -v iface="$INTERFACE" '$1 ~ iface {gsub(/:/,"",$1); sum+=$10} END{print sum}' /proc/net/dev)

# 将 GB 限制值转换为字节
rx_limit_bytes=$((RX_LIMIT * 1024 * 1024 * 1024))
tx_limit_bytes=$((TX_LIMIT * 1024 * 1024 * 1024))

# 写入历史日志
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
rx_gb=$((rx / 1024 / 1024 / 1024))
tx_gb=$((tx / 1024 / 1024 / 1024))
echo "$timestamp | 接收: ${rx_gb} GB | 发送: ${tx_gb} GB" >> "$HISTORY_LOG"

# 每周六 17:30 流量通知（仅通知）
now=$(date '+%u %H:%M')
if [[ "$now" == "6 17:30" ]]; then
  echo "📊 [流量通知] 当前接收：${rx_gb} GB，发送：${tx_gb} GB"
  exit 0
fi

# 每月1号自动恢复服务
today=$(date '+%d')
hour=$(date '+%H')
if [[ "$today" == "01" && "$hour" == "01" ]]; then
  if [[ "$MODE" == "systemctl" ]]; then
    systemctl start xray
    echo "✅ 每月1日自动恢复 Xray 服务 (systemctl)"
  elif [[ "$MODE" == "docker" ]]; then
    docker start xray
    echo "✅ 每月1日自动恢复 Xray 服务 (docker)"
  fi
  rm -f "$STATE_FILE"
  exit 0
fi

# 是否已触发关闭
if [[ -f "$STATE_FILE" ]]; then
  echo "⚠️ 已触发过限，不重复处理。"
  exit 0
fi

# 超限判断与操作
if (( rx > rx_limit_bytes || tx > tx_limit_bytes )); then
  echo "$(date) 超过限制！RX: $rx / $rx_limit_bytes, TX: $tx / $tx_limit_bytes" >> "$STATE_FILE"
  case "$MODE" in
    "systemctl") systemctl stop xray ;;
    "docker") docker stop xray ;;
    "shutdown") shutdown -h now ;;
  esac
  echo "⛔ 已达到流量限制，已执行操作：$MODE"
  exit 0
fi
EOF

chmod +x "$INSTALL_PATH"

# 添加到 crontab
echo "📅 添加定时任务到 crontab..."
(crontab -l 2>/dev/null; echo "* * * * * $INSTALL_PATH") | sort -u | crontab -
if [[ "$MODE" == "shutdown" ]]; then
  (crontab -l 2>/dev/null; echo "0 1 1 * * /sbin/reboot") | sort -u | crontab -
fi

echo "✅ 安装完成。主脚本路径：$INSTALL_PATH"
echo "📘 流量日志保存在：$HISTORY_LOG"
