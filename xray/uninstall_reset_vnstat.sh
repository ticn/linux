#!/bin/bash

INSTALL_SCRIPT="/usr/local/bin/reset_vnstat.sh"
LOG_FILE="/var/log/vnstat_reset.log"

echo "🧹 开始卸载 vnstat 每月重置任务..."

# 删除定时任务
crontab -l 2>/dev/null | grep -v "$INSTALL_SCRIPT" | crontab -

# 删除脚本文件
if [ -f "$INSTALL_SCRIPT" ]; then
  sudo rm -f "$INSTALL_SCRIPT"
  echo "✅ 已删除脚本 $INSTALL_SCRIPT"
else
  echo "⚠️ 未找到脚本 $INSTALL_SCRIPT，可能已删除"
fi

echo "✅ 已从 crontab 中移除定时任务。"
echo "📄 日志文件 $LOG_FILE 保留，如需可手动删除。"
