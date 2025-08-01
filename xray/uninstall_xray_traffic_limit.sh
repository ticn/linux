#!/bin/bash

echo "🧹 正在卸载 Xray 流量限制脚本..."

# 删除主脚本
rm -f /usr/local/bin/xray_traffic_limit.sh

# 删除配置文件与状态日志
rm -f /etc/xray_traffic_config.conf
rm -f /var/log/xray_traffic_limit_state.txt
rm -f /var/log/xray_traffic_history.log

# 删除 systemd 自动恢复服务（如果有）
rm -f /etc/systemd/system/xray-auto-restore.service
rm -f /etc/systemd/system/xray-auto-restore.timer
systemctl daemon-reexec 2>/dev/null
systemctl daemon-reload 2>/dev/null

# 删除定时任务
crontab -l | grep -v 'xray_traffic_limit.sh' | grep -v 'reboot' | grep -v 'limit_notify_once.sh' | crontab -

# 删除每周通知脚本（如果有）
rm -f /usr/local/bin/limit_notify_once.sh

echo "✅ 卸载完成！已删除脚本、配置文件、日志和相关定时任务。"
