#!/bin/bash

# 更新apt源并升级系统软件
apt update -y && apt dist-upgrade -y

# 安装必要的软件包
apt-get install -y xz-utils openssl gawk file wget screen

# 创建并进入一个新的screen会话
screen -S os

# 下载并运行NewReinstall.sh脚本
wget --no-check-certificate -O NewReinstall.sh https://git.io/newbetags
chmod a+x NewReinstall.sh
bash NewReinstall.sh
