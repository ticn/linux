#!/bin/bash

# 📍 Netflix 节目链接（香港地区）
NETFLIX_URL="https://www.netflix.com/hk/title/80018959"

# 🧾 状态记录文件 + 上次检测时间
STATE_FILE="/tmp/netflix_unlock_status.txt"
LAST_RUN_FILE="/tmp/netflix_check_last_run.txt"

# 📨 Telegram Bot 配置
BOT_TOKEN="123456789:ABCDEF-your-telegram-bot-token"
CHAT_ID="123456789"

# 获取当前时间（时间戳）
NOW_TS=$(date +%s)

# 如果有上次检测时间，就加载
if [[ -f "$LAST_RUN_FILE" ]]; then
    LAST_TS=$(cat "$LAST_RUN_FILE")
else
    LAST_TS=0
fi

# 获取上次解锁状态
if [[ -f "$STATE_FILE" ]]; then
    LAST_STATE=$(cat "$STATE_FILE")
else
    LAST_STATE="unknown"
fi

# 定义最小间隔：解锁状态下 4 小时，未解锁 1 小时（单位：秒）
if [[ "$LAST_STATE" == "unlocked" ]]; then
    MIN_INTERVAL=$((4 * 3600))
else
    MIN_INTERVAL=$((1 * 3600))
fi

# 判断是否需要跳过这次检测
ELAPSED=$((NOW_TS - LAST_TS))
if (( ELAPSED < MIN_INTERVAL )); then
    echo "⏳ 距离上次检测 $ELAPSED 秒，未达到最小间隔 $MIN_INTERVAL 秒，跳过。"
    exit 0
fi

# ✍️ 更新检测时间
echo "$NOW_TS" > "$LAST_RUN_FILE"

# 🧪 抓取网页内容
HTML=$(curl -s --max-time 10 --retry 3 "$NETFLIX_URL")

# 🧩 解锁判断逻辑
if echo "$HTML" | grep -q "這部影片目前無法在您的國家/地區觀賞"; then
    CURRENT_STATE="locked"
elif echo "$HTML" | grep -q "銀魂"; then
    CURRENT_STATE="unlocked"
else
    CURRENT_STATE="unknown"
fi

# 如果当前状态无法判断，不发送通知并退出
if [[ "$CURRENT_STATE" == "unknown" ]]; then
    echo "⚠️ 无法判断当前状态，请检查网络或页面结构"
    exit 2
fi

# 检查状态是否变化，并在变化时发送通知
if [[ "$CURRENT_STATE" != "$LAST_STATE" ]]; then
    if [[ "$CURRENT_STATE" == "unlocked" ]]; then
        MESSAGE="✅ 当前 IP 已解锁 Netflix 香港，可观看《銀魂》🎉"
        echo "✅ 当前 IP 已解锁 Netflix 香港"
    else
        MESSAGE="❌ 当前 IP 无法解锁 Netflix 香港"
        echo "❌ 当前 IP 无法解锁 Netflix 香港"
    fi

    # 发送 Telegram 通知
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$MESSAGE" > /dev/null

    echo "📨 已发送 Telegram 通知: $MESSAGE"

    # 更新状态文件
    echo "$CURRENT_STATE" > "$STATE_FILE"
else
    if [[ "$CURRENT_STATE" == "unlocked" ]]; then
        echo "✅ 当前 IP 已解锁 Netflix 香港，但状态未变化，不发送通知"
    else
        echo "❌ 当前 IP 无法解锁 Netflix 香港，但状态未变化，不发送通知"
    fi
fi

# 脚本结束
#crontab -e
#0 * * * * /root/check_netflix_unlock_notify.sh >> /var/log/netflix_check.log 2>&1
exit 0
