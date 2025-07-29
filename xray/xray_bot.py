import os
import json
import subprocess
import psutil
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, filters, ContextTypes

# ✅ 修改为你的 Token 和 Chat ID
BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
AUTHORIZED_CHAT_ID = 123456789

XRAY_SERVICE = "xray"
XRAY_CONFIG_PATH = "/etc/xray/config.json"
XRAY_SCRIPT_PATH = "/usr/local/bin/xray-traffic-limit.sh"

def is_authorized(update: Update) -> bool:
    if update.effective_chat.id != AUTHORIZED_CHAT_ID:
        update.message.reply_text("❌ 未授权")
        return False
    return True

# 启动、停止、重启 Xray 服务
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

# 状态查询
async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return

    # 检查进程状态
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

# 执行流量限额脚本
async def manual_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    subprocess.Popen(["bash", XRAY_SCRIPT_PATH, "manual"])
    await update.message.reply_text("⚙️ 已执行手动限额脚本")

async def limit_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    subprocess.Popen(["bash", XRAY_SCRIPT_PATH])
    await update.message.reply_text("📦 已执行自动限额脚本")

# 切换 netflix 出站 tag
AVAILABLE_TAGS = ["alice", "AMD", "rs", "NiiHost", "local", "NG", "ARM"]

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
            await update.message.reply_text(f"✅ Netflix 出站已切换为 `{chosen}`，并已重启 Xray")
        else:
            await update.message.reply_text("⚠️ 未找到 geosite:netflix 相关配置，未修改")

    except Exception as e:
        await update.message.reply_text(f"❌ 配置修改失败: {e}")

# 帮助信息
async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update): return
    await update.message.reply_text(
        "📖 可用指令：\n"
        "/start - 启动 Xray\n"
        "/stop - 停止 Xray\n"
        "/restart - 重启 Xray\n"
        "/status - 查看状态\n"
        "/manual - 手动流量限额\n"
        "/limit - 自动流量限额\n"
        "/tag - 更换 Netflix 出站\n"
        "/help - 显示帮助"
    )

# 初始化 bot
if __name__ == "__main__":
    app = ApplicationBuilder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("stop", stop_command))
    app.add_handler(CommandHandler("restart", restart_command))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(CommandHandler("manual", manual_command))
    app.add_handler(CommandHandler("limit", limit_command))
    app.add_handler(CommandHandler("tag", tag_command))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, tag_switcher))

    app.run_polling()
