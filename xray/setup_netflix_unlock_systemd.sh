#!/bin/bash

read -rp "请输入你的 Telegram Bot Token: " BOT_TOKEN
read -rp "请输入你的 Telegram Chat ID: " CHAT_ID

SCRIPT_PATH="/usr/local/bin/check_netflix_unlock.sh"
LOG_FILE="/var/log/netflix_unlock.log"
SERVICE_FILE="/etc/systemd/system/netflix-check.service"
TIMER_FILE="/etc/systemd/system/netflix-check.timer"

# ✅ 生成主检测脚本
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

NETFLIX_URL="https://www.netflix.com/hk/title/80018959"
STATE_FILE="/tmp/netflix_unlock_status.txt"
LAST_RUN_FILE="/tmp/netflix_check_last_run.txt"

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"

NOW_TS=\$(date +%s)
LAST_TS=0
[[ -f "\$LAST_RUN_FILE" ]] && LAST_TS=\$(cat "\$LAST_RUN_FILE")
[[ -f "\$STATE_FILE" ]] && LAST_STATE=\$(cat "\$STATE_FILE") || LAST_STATE="unknown"

if [[ "\$LAST_STATE" == "unlocked" ]]; then
    MIN_INTERVAL=\$((4 * 3600))
else
    MIN_INTERVAL=\$((1 * 3600))
fi

ELAPSED=\$((NOW_TS - LAST_TS))
if (( ELAPSED < MIN_INTERVAL )); then
    echo "\$(date) ⏳ \$ELAPSED 秒未达到 \$MIN_INTERVAL 秒，跳过。" >> "$LOG_FILE"
    exit 0
fi

echo "\$NOW_TS" > "\$LAST_RUN_FILE"

HTML=\$(curl -s --max-time 10 --retry 3 "\$NETFLIX_URL")

if echo "\$HTML" | grep -q "這部影片目前無法在您的國家/地區觀賞"; then
    CURRENT_STATE="locked"
elif echo "\$HTML" | grep -q "銀魂"; then
    CURRENT_STATE="unlocked"
else
    echo "\$(date) ⚠️ 无法判断状态" >> "$LOG_FILE"
    exit 2
fi

if [[ "\$CURRENT_STATE" != "\$LAST_STATE" ]]; then
    echo "\$CURRENT_STATE" > "\$STATE_FILE"

    if [[ "\$CURRENT_STATE" == "unlocked" ]]; then
        MESSAGE="✅ 当前 IP 已解锁 Netflix 香港，可观看《銀魂》🎉"
    else
        MESSAGE="❌ 当前 IP 无法解锁 Netflix 香港，已受限 🚫"
    fi

    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
        -d chat_id="\$CHAT_ID" \
        -d text="\$MESSAGE" > /dev/null

    echo "\$(date) 📨 状态变化：\$LAST_STATE -> \$CURRENT_STATE，已通知" >> "$LOG_FILE"
else
    echo "\$(date) ℹ️ 状态未变化：\$CURRENT_STATE" >> "$LOG_FILE"
fi
EOF

chmod +x "$SCRIPT_PATH"

# ✅ 创建 systemd service
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Netflix Unlock Checker

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

# ✅ 创建 systemd timer（每小时运行一次）
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run Netflix Unlock Checker hourly

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Unit=netflix-check.service

[Install]
WantedBy=timers.target
EOF

# ✅ 重载并启用 timer
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now netflix-check.timer

# ✅ 初始化日志文件
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# ✅ 手动首次运行一次检测
echo "首次运行脚本进行状态检测..."
bash "$SCRIPT_PATH"

echo
echo "✅ 安装完成！Netflix 解锁检测已部署 systemd 定时任务。"
echo "🗂️ 脚本路径：$SCRIPT_PATH"
echo "📄 日志文件：$LOG_FILE"
echo "🕒 systemd timer: netflix-check.timer 每小时运行"
echo "🔧 可用命令："
echo "   journalctl -u netflix-check.service --no-pager"
echo "   systemctl list-timers | grep netflix"
