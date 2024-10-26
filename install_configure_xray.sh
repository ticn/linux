#!/bin/bash

# Prompt the user to enter the password for the Shadowsocks configuration
read -p "Enter the password for Shadowsocks (default: 123456): " shadowsocks_password

# If the user does not provide a password, use the default value
shadowsocks_password=${shadowsocks_password:-123456}

# Update package list
apt-get update

# Install required packages
apt-get -y install lsb-release ca-certificates curl gnupg

# Download and add the GPG key for the Shadowsocks repository
curl -fsSL https://dl.lamp.sh/shadowsocks/DEB-GPG-KEY-Teddysun | gpg --dearmor --yes -o /usr/share/keyrings/deb-gpg-key-teddysun.gpg

# Ensure the GPG key file is readable
chmod a+r /usr/share/keyrings/deb-gpg-key-teddysun.gpg

# Add the Shadowsocks repository to the sources list
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/deb-gpg-key-teddysun.gpg] https://dl.lamp.sh/shadowsocks/debian/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/teddysun.list

# Update package list again to include the new repository
apt-get update

# Install the xray and vim packages
apt-get install -y xray vim

# Clear the existing /etc/xray/config.json file and add the new configuration
cat >/etc/xray/config.json <<EOL
{
  "log": {
    "access": "/etc/xray/access.log",
    "error": "/etc/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 50025,
      "protocol": "shadowsocks",
      "settings": {
        "method": "chacha20-poly1305",
        "password": "$shadowsocks_password",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "block"
    },
    {
      "tag": "warp",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 40000
          }
        ]
      }
    },
    {
      "tag": "WARP-socks5-v4",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "proxySettings": {
        "tag": "warp"
      }
    },
    {
      "tag": "WARP-socks5-v6",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv6"
      },
      "proxySettings": {
        "tag": "warp"
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "WARP-socks5-v4"
        // "outboundTag": "WARP-socks5-v6"
      }
    ]
  }
}
EOL

# Enable and restart the Xray service, then check its status
systemctl enable xray
systemctl restart xray
systemctl status xray

# Display the public IP address
curl ip.sb

echo "Xray configuration has been updated successfully with the password: $shadowsocks_password"

