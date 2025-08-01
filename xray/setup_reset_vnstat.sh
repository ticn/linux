#!/bin/bash

INSTALL_SCRIPT="/usr/local/bin/reset_vnstat.sh"
LOG_FILE="/var/log/vnstat_reset.log"
INTERFACE="ens5"

echo "🔧 安装 vnstat 每月重置任务..."

# 写入脚本
cat <<EOF | sudo tee "$INSTALL_SCRIPT" > /dev/null
#!/bin/bash

# 每月重置 vnstat 流量统计
INTERFACE="$INTERFACE"

sudo vnstat -i "\$INTERFACE" --remove --force
sudo vnstat -i "\$INTERFACE" --add
sudo systemctl restart vnstat
sudo vnstat -i "\$INTERFACE"
EOF

# 添加执行权限
sudo chmod +x "$INSTALL_SCRIPT"

# 添加 crontab 任务（先检查是否已存在）
CRON_JOB="0 0 1 * * $INSTALL_SCRIPT >> $LOG_FILE 2>&1"
( crontab -l 2>/dev/null | grep -v "$INSTALL_SCRIPT" ; echo "$CRON_JOB" ) | crontab -

echo "✅ 安装完成。每月 1 日 00:00 将自动重置 vnstat 接口 $INTERFACE。"
echo "📄 日志输出：$LOG_FILE"
