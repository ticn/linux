#!/bin/bash
# 一键管理 IPv6 SIT 隧道服务，支持安装、卸载、状态、自动检测和修复及日志清理

set -e

SERVICE_NAME="tunnel.service"
TIMER_NAME="tunnel-check.timer"
CHECK_SERVICE_NAME="tunnel-check.service"
LOGCLEAN_TIMER="tunnel-logclean.timer"
LOGCLEAN_SERVICE="tunnel-logclean.service"

SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
TIMER_FILE="/etc/systemd/system/$TIMER_NAME"
CHECK_SERVICE_FILE="/etc/systemd/system/$CHECK_SERVICE_NAME"
CHECK_SCRIPT_FILE="/usr/local/bin/check-tunnel.sh"
SCRIPT_FILE="/usr/local/bin/setup-tunnel.sh"
CONFIG_FILE="/etc/tunnel_setup.conf"
LOG_FILE="/var/log/tunnel-check.log"
LOGROTATE_FILE="/etc/logrotate.d/tunnel-check"
LOGCLEAN_SERVICE_FILE="/etc/systemd/system/$LOGCLEAN_SERVICE"
LOGCLEAN_TIMER_FILE="/etc/systemd/system/$LOGCLEAN_TIMER"

function show_usage() {
    echo "用法: $0 {install|uninstall|status}"
    echo "  install   安装并配置隧道服务和自动检测及日志清理"
    echo "  uninstall 卸载所有相关配置和服务"
    echo "  status    查看隧道接口和连通状态"
    exit 1
}

function install() {
    echo "=== 安装 IPv6 SIT 隧道服务及自动检测和日志清理 ==="

    # 交互输入参数
    read -rp "请输入隧道远端 IPv4（默认: 216.218.221.42，可留空）: " REMOTE_IPV4
    REMOTE_IPV4=${REMOTE_IPV4:-216.218.221.42}

    read -rp "请输入本地 IPv4（必填）: " LOCAL_IPV4
    if [[ -z "$LOCAL_IPV4" ]]; then
        echo "本地 IPv4 不能为空"
        exit 1
    fi

    read -rp "请输入分配的 IPv6 地址（默认: 2001:470:eff9::2/48，可留空）: " IPV6_ADDR
    IPV6_ADDR=${IPV6_ADDR:-2001:470:eff9::2/48}

    # 保存配置
    echo "REMOTE_IPV4=$REMOTE_IPV4" > "$CONFIG_FILE"
    echo "LOCAL_IPV4=$LOCAL_IPV4" >> "$CONFIG_FILE"
    echo "IPV6_ADDR=$IPV6_ADDR" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    # 写主配置脚本 setup-tunnel.sh
    cat > "$SCRIPT_FILE" <<EOF
#!/bin/bash
set -e
CONFIG_FILE="$CONFIG_FILE"
source "\$CONFIG_FILE"

function interface_exists() {
    ip link show "\$1" &>/dev/null
}

if interface_exists sit0; then
    ip link del sit0
fi
ip link add sit0 type sit remote "\$REMOTE_IPV4" local "\$LOCAL_IPV4" ttl 255
ip link set sit0 up

if interface_exists sit1; then
    ip link del sit1
fi
ip link add sit1 type sit
ip link set sit1 up

ip -6 addr add "\$IPV6_ADDR" dev sit1

ip -6 route add ::/0 dev sit1
EOF

    chmod +x "$SCRIPT_FILE"

    # 写检查脚本 check-tunnel.sh
    cat > "$CHECK_SCRIPT_FILE" <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/tunnel-check.log"
TIMESTAMP() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(TIMESTAMP)] $*" | tee -a "$LOG_FILE"; }

if ! ping6 -c 2 -W 2 ipv6.google.com &>/dev/null; then
    log "IPv6 连接失败，尝试重建隧道..."
    /usr/local/bin/setup-tunnel.sh
    sleep 3
    if ping6 -c 2 -W 2 ipv6.google.com &>/dev/null; then
        log "恢复成功，IPv6 通道已连接。"
    else
        log "恢复失败，IPv6 通道依旧不可用！"
    fi
else
    log "IPv6 连接正常。"
fi
EOF

    chmod +x "$CHECK_SCRIPT_FILE"

    # systemd 主服务 tunnel.service
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=IPv6 Tunnel Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_FILE
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # systemd 检测服务 tunnel-check.service
    cat > "$CHECK_SERVICE_FILE" <<EOF
[Unit]
Description=Check and Repair IPv6 Tunnel
After=network-online.target

[Service]
Type=oneshot
ExecStart=$CHECK_SCRIPT_FILE
EOF

    # systemd 检测定时器 tunnel-check.timer
    cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run IPv6 Tunnel Check Every 5 Minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # systemd 日志清理服务 tunnel-logclean.service
    cat > "$LOGCLEAN_SERVICE_FILE" <<EOF
[Unit]
Description=Clean Tunnel Log File

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'truncate -s 0 $LOG_FILE || true'
EOF

    # systemd 日志清理定时器 tunnel-logclean.timer
    cat > "$LOGCLEAN_TIMER_FILE" <<EOF
[Unit]
Description=Run Tunnel Log Clean Daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # 日志轮转配置
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

    # 确保日志文件存在
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE" || true

    systemctl daemon-reload

    systemctl enable --now $SERVICE_NAME
    systemctl enable --now $TIMER_NAME
    systemctl enable --now $LOGCLEAN_TIMER

    echo "安装完成！服务已启动，自动检测每 5 分钟运行一次，日志每日清理。"
}

function uninstall() {
    echo "=== 卸载 IPv6 SIT 隧道服务及自动检测和日志清理 ==="

    systemctl stop $LOGCLEAN_TIMER $TIMER_NAME $CHECK_SERVICE_NAME $SERVICE_NAME 2>/dev/null || true
    systemctl disable $LOGCLEAN_TIMER $TIMER_NAME $CHECK_SERVICE_NAME $SERVICE_NAME 2>/dev/null || true

    rm -f "$SERVICE_FILE" "$CHECK_SERVICE_FILE" "$TIMER_FILE" "$SCRIPT_FILE" "$CHECK_SCRIPT_FILE" "$CONFIG_FILE" "$LOGROTATE_FILE" "$LOG_FILE" "$LOGCLEAN_SERVICE_FILE" "$LOGCLEAN_TIMER_FILE"

    ip link del sit0 2>/dev/null || true
    ip link del sit1 2>/dev/null || true

    systemctl daemon-reload

    echo "卸载完成，所有配置和隧道接口已清理。"
}

function status() {
    echo "=== IPv6 SIT 隧道状态 ==="
    ip link show sit0 || echo "sit0 接口不存在"
    ip link show sit1 || echo "sit1 接口不存在"
    ip -6 addr show dev sit1 || echo "sit1 没有 IPv6 地址"
    ip -6 route show dev sit1 || echo "sit1 无 IPv6 路由"

    echo
    echo "测试 IPv6 连通性 (ping6 ipv6.google.com):"
    if ping6 -c 3 -W 2 ipv6.google.com &>/dev/null; then
        echo "✅ IPv6 连通正常"
    else
        echo "❌ IPv6 连通异常"
    fi

    echo
    echo "自动检测服务状态:"
    systemctl status $TIMER_NAME $CHECK_SERVICE_NAME $SERVICE_NAME $LOGCLEAN_TIMER --no-pager || true
}

if [[ $# -ne 1 ]]; then
    show_usage
fi

case "$1" in
    install) install ;;
    uninstall) uninstall ;;
    status) status ;;
    *) show_usage ;;
esac
