#!/bin/bash

# 1. 动态安全初始化密钥
if [ -z "$UUID" ]; then
  export UUID=$(/usr/bin/xray uuid)
  echo "⚠️ 未检测到自定义 UUID，系统已自动生成随机密钥: $UUID"
else
  echo "🔑 当前节点正在使用自定义密钥: $UUID"
fi

# ================= 动态公网 IP 与位置抓取组件 =================
echo "🔍 正在打捞当前 Railway 容器的真实公网 IP 与物理归属地..."
REAL_IP=$(curl -s --max-time 3 ifconfig.me)
REAL_COUNTRY=$(curl -s --max-time 3 ipinfo.io/country)

if [ -z "$REAL_IP" ]; then REAL_IP="DynamicIP"; fi
if [ -z "$REAL_COUNTRY" ]; then REAL_COUNTRY="Cloud"; fi

NODE_REMARK="${REAL_COUNTRY}_${REAL_IP}"
echo "📍 探测成功！当前容器真实出口位置: $NODE_REMARK"
# =====================================================================

# 动态注入密钥、以及动态节点名字到内核配置文件和前端页面
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/config.json
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/www/index.html
sed -i "s/NODE_REMARK_PLACEHOLDER/$NODE_REMARK/g" /app/www/index.html

# 2. 启动 Alpine 增强网页服务器（监听 8081 端口）
httpd -p 8081 -h /app/www &
echo "🌐 静态网页后台已在本地 8081 端口拉起"

# 3. 启动 Xray 核心组件（监听 8080 端口）
/usr/bin/xray -config /app/config.json &
echo "🚀 Xray 核心组件已在本地 8080 端口拉起"

# 4. 运行 Cloudflare Tunnel 隧道
if [ -z "$TUNNEL_TOKEN" ]; then
  echo "❌ 【错误】未检测到 TUNNEL_TOKEN 环境变量，隧道无法建立！"
  exit 1
fi

echo "🚇 正在通过 QUIC (UDP) 协议向 Cloudflare 边缘网络建立加密大桥..."
/usr/local/bin/cloudflared tunnel --protocol quic --no-autoupdate run --token "$TUNNEL_TOKEN" &

# 5. 纯净版双端口雷达监控循环（无计算负载，仅拦截死锁）
while true; do
  sleep 15

  netstat -tln | grep -q :8080
  VLESS_PORT=$?
  netstat -tln | grep -q :8081
  HTTP_PORT=$?
  pidof cloudflared > /dev/null
  CF_PROCESS=$?

  if [ $VLESS_PORT -ne 0 ] || [ $HTTP_PORT -ne 0 ] || [ $CF_PROCESS -ne 0 ]; then
    echo "🚨 【断流警报】检测到服务硬断流！(VLESS:$VLESS_PORT, 网页:$HTTP_PORT, 隧道:$CF_PROCESS)"
    exit 1
  fi
done
