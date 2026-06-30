#!/bin/bash

if [ -z "$UUID" ]; then
  export UUID=$(/usr/bin/xray uuid)
  echo "⚠️ 未检测到自定义 UUID 变量，系统已自动生成随机安全密钥: $UUID"
else
  echo "🔑 当前节点正在使用自定义 UUID: $UUID"
fi

sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/config.json
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/www/index.html

busybox httpd -f -p 8081 -h /app/www &
echo "🌐 轻量静态网页后台已在本地 8081 端口拉起"

/usr/bin/xray -config /app/config.json &
echo "🚀 Xray 核心组件已在本地 8080 端口拉起"

if [ -z "$TUNNEL_TOKEN" ]; then
  echo "❌ 【错误】未检测到 TUNNEL_TOKEN 环境变量，Cloudflare Tunnel 无法建立！"
  exit 1
fi

echo "🚇 正在通过 QUIC (UDP) 协议向 Cloudflare 边缘网络建立加密大桥..."
/usr/local/bin/cloudflared tunnel --protocol quic --no-autoupdate run --token "$TUNNEL_TOKEN" &

while true; do
  sleep 10
  pidof xray > /dev/null
  XRAY_STATUS=$?
  pidof cloudflared > /dev/null
  CF_STATUS=$?

  if [ $XRAY_STATUS -ne 0 ] || [ $CF_STATUS -ne 0 ]; then
    echo "🚨 【警告】检测到内部核心进程异常崩溃！正在终止容器以触发 Railway 自动拉起新实例..."
    exit 1
  fi
done
