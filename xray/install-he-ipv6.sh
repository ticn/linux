#!/bin/bash
# 一键安装/卸载/状态检查 HE IPv6 隧道 + 自检 + 定时自愈 + 日志归档 + 即时检测
# 适配 Debian/Ubuntu 系统，确保内核转发、systemd-networkd 运行，netplan 配置权限安全

set -e

MODE="$1"  # install / uninstall / status

NETPLAN_FILE_NAME="50-he-ipv6.yaml"
NETPLAN_PATH="/etc/netplan/$NETPLAN_FILE_NAME"
CHECK_SCRIPT="/usr/local/bin/check-he-ipv6.sh"
SERVICE_FILE="/etc/systemd/system/check-he-ipv6.service"
TIMER_FILE="/etc/systemd/system/check-he-ipv6.timer"
LOG_FILE="/var/log/he-ipv6.log"
LOGROTATE_FILE="/etc/logrotate.d/he-ipv6"
MODULES_FILE="/etc/modules-load.d/sit.conf"

show_usage() {
    echo "用法: $0 [install|uninstall|status]"
    echo "  install   安装或更新 HE IPv6 隧道配置（默认）"
    echo "  uninstall 卸载并清理所有相关配置"
    echo "  status    查看当前 HE IPv6 隧道状态"
    exit 1
}

if [[ -z "$MODE" ]]; then
    MODE="install"
fi

if [[ "$MODE" == "uninstall" ]]; then
    echo "=== 🧹 卸载 HE IPv6 隧道配置 ==="

    systemctl disable --now check-he-ipv6.timer 2>/dev/null || true
    systemctl disable --now check-he-ipv6.service 2>/dev/null || true

    rm -f "$NETPLAN_PATH" "$CHECK_SCRIPT" "$SERVICE_FILE" "$TIMER_FILE" "$LOGROTATE_FILE" "$MODULES_FILE" "$LOG_FILE"

    netplan apply || true

    echo "✅ 卸载完成，已移除所有相关配置和文件。"
    exit 0
fi

if [[ "$MODE" == "status" ]]; then
    echo "=== 🔍 HE IPv6 隧道状态 ==="

    echo "--- 隧道接口信息 ---"
    ip link show he-ipv6 || echo "隧道接口 he-ipv6 不存在"

    echo
    echo "--- IPv6 地址 ---"
    ip -6 addr show dev he-ipv6 || echo "无 IPv6 地址"

    echo
    echo "--- 路由表（IPv6 默认路由） ---"
    ip -6 route show default || echo "无 IPv6 默认路由"

    echo
    echo "--- IPv6 连通性测试 ---"
    if ping6 -c 3 -W 2 ipv6.google.com &>/dev/null; then
        echo "✅ IPv6 连通正常"
    else
        echo "❌ IPv6 连通异常，建议运行安装脚本进行修复"
    fi

    exit 0
fi

if [[ "$MODE" != "install" ]]; then
    show_usage
fi

echo "=== 🛰️ 安装 Netplan 和配置 HE IPv6 隧道 ==="

# 1️⃣ 安装 netplan
if ! command -v netplan &>/dev/null; then
    echo "[INFO] 安装 netplan..."
    apt update
    apt install -y netplan.io
else
    echo "[OK] Netplan 已安装."
fi

# 2️⃣ 永久启用 sit 模块
echo "[INFO] 启用 sit 模块..."
rm -f /etc/modprobe.d/blacklist-sit.conf
echo "sit" > "$MODULES_FILE"
modprobe sit
echo "[OK] sit 模块已启用."

# 3️⃣ 启用 systemd-networkd 并设为网络后端
echo "[INFO] 启用 systemd-networkd 服务..."
systemctl enable systemd-networkd --now

# 4️⃣ 内核开启 IPv4 和 IPv6 转发
echo "[INFO] 开启内核 IPv4 和 IPv6 转发..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# 写入 sysctl 配置文件，永久生效
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi

# 5️⃣ 交互式输入用户信息
read -rp "请输入 HE 服务器 IPv4: " HE_SERVER
read -rp "请输入本机公网 IPv4: " LOCAL_IPV4
read -rp "请输入分配的 IPv6 地址（带 /64，例如 2001:470:18:a47::2/64）: " IPV6_ADDR
read -rp "请输入 IPv6 网关（例如 2001:470:18:a47::1）: " IPV6_GW
read -rp "请输入 Netplan 配置文件名（默认 ${NETPLAN_FILE_NAME}）: " CUSTOM_FILE
NETPLAN_FILE_NAME=${CUSTOM_FILE:-$NETPLAN_FILE_NAME}
NETPLAN_PATH="/etc/netplan/$NETPLAN_FILE_NAME"

# 6️⃣ 生成 Netplan 配置（带 renderer: networkd）
cat > "$NETPLAN_PATH" <<EOF
network:
  version: 2
  renderer: networkd
  tunnels:
    he-ipv6:
      mode: sit
      remote: $HE_SERVER
      local: $LOCAL_IPV4
      addresses:
        - "$IPV6_ADDR"
      routes:
        - to: default
          via: "$IPV6_GW"
EOF

chown root:root "$NETPLAN_PATH"
chmod 600 "$NETPLAN_PATH"
echo "[OK] Netplan 配置已生成：$NETPLAN_PATH （权限 600）"

# 7️⃣ 应用 Netplan
netplan generate
netplan apply
echo "[OK] Netplan 配置已应用."

# 8️⃣ 创建自检脚本
cat > "$CHECK_SCRIPT" <<'EOF'
#!/bin/bash
TUN_NAME="he-ipv6"
TEST_ADDR="ipv6.google.com"
LOG_FILE="/var/log/he-ipv6.log"

log() {
    local msg="[$(date '+%F %T')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
fi

if ! lsmod | grep -q "^sit"; then
    log "Loading sit module..."
    modprobe sit
else
    log "sit module already loaded."
fi

if ! ip link show "$TUN_NAME" &>/dev/null; then
    log "Tunnel $TUN_NAME not found, reapplying netplan..."
    netplan apply
else
    log "Tunnel $TUN_NAME exists."
fi

if ! ping6 -c 2 -W 2 "$TEST_ADDR" &>/dev/null; then
    log "IPv6 test failed, reapplying netplan..."
    netplan apply
else
    log "IPv6 is working."
fi
EOF
chmod 755 "$CHECK_SCRIPT"

# 9️⃣ 创建 systemd service
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Check and fix HE IPv6 tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CHECK_SCRIPT
EOF

# 🔟 创建 systemd timer
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run HE IPv6 tunnel check every 5 minutes

[Timer]
OnBootSec=30
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 1️⃣1️⃣ 配置 logrotate
cat > "$LOGROTATE_FILE" <<EOF
$LOG_FILE {
    monthly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

# 1️⃣2️⃣ 启用服务
systemctl daemon-reload
systemctl enable --now check-he-ipv6.timer

# 1️⃣3️⃣ 立即检测 IPv6 隧道可用性（失败自动二次恢复）
echo "[INFO] 正在检测 IPv6 隧道可用性..."
if ping6 -c 2 -W 2 ipv6.google.com &>/dev/null; then
    echo "✅ IPv6 隧道配置成功！"
else
    echo "⚠️ 第一次检测失败，尝试自动恢复..."
    netplan apply
    sleep 3
    if ping6 -c 2 -W 2 ipv6.google.com &>/dev/null; then
        echo "✅ 二次检测成功！IPv6 隧道已恢复。"
    else
        echo "❌ IPv6 隧道检测失败，请检查配置。"
    fi
fi

echo "==============================================="
echo "✅ 完成！用法示例："
echo "  $0 install    # 安装或更新配置（默认）"
echo "  $0 uninstall  # 卸载并清理"
echo "  $0 status     # 查看 IPv6 隧道状态"
echo "==============================================="
