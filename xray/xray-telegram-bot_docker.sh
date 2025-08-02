#!/bin/bash

# === 📌 设置参数 ===
BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
AUTHORIZED_CHAT_ID=123456789

# === 📁 路径配置 ===
VENV_PATH="/usr/local/bin/telegram-venv"
BOT_PATH="/usr/local/bin/xray_bot.py"
SERVICE_PATH="/etc/systemd/system/xray-telegram-bot.service"

echo "🚀 安装 Python3、pip 和 venv..."
apt update && apt install -y python3 python3-pip python3-venv git

echo "🛠️ 创建虚拟环境..."
python3 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"
pip install python-telegram-bot==20.7 psutil
deactivate

echo "📦 写入 Bot 脚本..."
cat > "$BOT_PATH" <<EOF
import os
import json
import subprocess
import psutil
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, filters, ContextTypes

BOT_TOKEN = "${BOT_TOKEN}"
AUTHORIZED_CHAT_ID = ${AUTHORIZED_CHAT_ID}

XRAY_SERVICE = "xray"
XRAY_CONFIG_PATH = "/etc/xray/config.json"

def is_authorized(update: Update) -> bool:
    if update.effective_chat.id != AUTHORIZED_CHAT_ID:
        update.message.reply_text("❌ 未授权")
        return False
    return True

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    subprocess.run(["systemctl", "start", XRAY_SERVICE])
    await update.message.reply_text("✅ Xray 已启动")

async def stop_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    subprocess.run(["systemctl", "stop", XRAY_SERVICE])
    await update.message.reply_text("🛑 Xray 已停止")

async def restart_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    subprocess.run(["systemctl", "restart", XRAY_SERVICE])
    await update.message.reply_text("🔄 Xray 已重启")

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    status = subprocess.run(["systemctl", "is-active", XRAY_SERVICE], capture_output=True, text=True).stdout.strip()
    pid = None
    for proc in psutil.process_iter(['pid', 'name']):
        if 'xray' in proc.info['name']:
            pid = proc.info['pid']
            break
    if pid:
        p = psutil.Process(pid)
        uptime = int(psutil.boot_time() - p.create_time())
        cpu = p.cpu_percent(interval=1.0)
        ram = p.memory_info().rss / 1024 / 1024
        await update.message.reply_text(
            f"📊 Xray 状态: {status}\n"
            f"🆔 PID: {pid}\n"
            f"⏱️ 运行时间: {uptime} 秒\n"
            f"🧠 RAM: {ram:.2f} MB\n"
            f"⚙️ CPU: {cpu:.2f}%"
        )
    else:
        await update.message.reply_text(f"📊 Xray 状态: {status}（未找到进程）")

AVAILABLE_TAGS = [
    "x-v4", "sg-v4", "hkt-v4", "hinet-v4", "vn-v4", "biglobe-v4", "IPv6_out"
]

async def tag_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    keyboard = [[tag] for tag in AVAILABLE_TAGS]
    reply_markup = ReplyKeyboardMarkup(keyboard, one_time_keyboard=True, resize_keyboard=True)
    await update.message.reply_text("请选择出站 Tag（geosite:netflix）使用：", reply_markup=reply_markup)

async def tag_switcher(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    chosen = update.message.text.strip()
    if chosen not in AVAILABLE_TAGS:
        await update.message.reply_text("❌ 无效的 Tag，请使用 /tag 再试")
        return
    try:
        with open(XRAY_CONFIG_PATH, 'r') as f:
            config = json.load(f)
        modified = False
        for rule in config.get("routing", {}).get("rules", []):
            if rule.get("type") == "field" and rule.get("domain") == ["geosite:netflix"]:
                rule["outboundTag"] = chosen
                modified = True
        if modified:
            with open(XRAY_CONFIG_PATH, 'w') as f:
                json.dump(config, f, indent=2)
            subprocess.run(["systemctl", "restart", XRAY_SERVICE])
            await update.message.reply_text(f"✅ Netflix 出站已切换为 \`{chosen}\`，并已重启 Xray")
        else:
            await update.message.reply_text("⚠️ 未找到 geosite:netflix 相关配置，未修改")
    except Exception as e:
        await update.message.reply_text(f"❌ 配置修改失败: {e}")

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    await update.message.reply_text(
        "📖 可用指令：\n"
        "/start - 启动 Xray\n"
        "/stop - 停止 Xray\n"
        "/restart - 重启 Xray\n"
        "/status - 查看状态\n"
        "/tag - 更换 Netflix 出站\n"
        "/help - 显示帮助"
    )

if __name__ == "__main__":
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("stop", stop_command))
    app.add_handler(CommandHandler("restart", restart_command))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(CommandHandler("tag", tag_command))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, tag_switcher))
    app.run_polling()
EOF

chmod +x "$BOT_PATH"

echo "🧷 写入 systemd 服务..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Xray Telegram Bot
After=network.target

[Service]
Type=simple
ExecStart=${VENV_PATH}/bin/python ${BOT_PATH}
Restart=on-failure
User=root
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

echo "📡 启动并设置开机自启..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray-telegram-bot
systemctl start xray-telegram-bot

echo "✅ 安装完成！你现在可以通过 Telegram 控制你的 Xray Bot 了。"
