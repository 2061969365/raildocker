#!/bin/bash

# 1. 动态安全初始化 UUID
if [ -z "$UUID" ]; then
  export UUID=$(/usr/bin/xray uuid)
  echo "⚠️ 未检测到自定义 UUID 变量，系统已自动生成随机安全密钥: $UUID"
else
  echo "🔑 当前节点正在使用自定义 UUID: $UUID"
fi

# 动态将真实的 UUID 注入到配置文件和前端页面中
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/config.json
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/www/index.html

# 2. 启动 Alpine 自带的 Busybox 网页服务器（让其自然后台化）
busybox httpd -p 8081 -h /app/www &
echo "🌐 轻量静态网页后台已在本地 8081 端口拉起"

# 3. 启动 Xray 核心组件
/usr/bin/xray -config /app/config.json &
echo "🚀 Xray 核心组件已在本地 8080 端口拉起"

# 4. 验证并运行 Cloudflare Tunnel 隧道
if [ -z "$TUNNEL_TOKEN" ]; then
  echo "❌ 【错误】未检测到 TUNNEL_TOKEN 环境变量，Cloudflare Tunnel 无法建立！"
  exit 1
fi

echo "🚇 正在通过 QUIC (UDP) 协议向 Cloudflare 边缘网络建立加密大桥..."
/usr/local/bin/cloudflared tunnel --protocol quic --no-autoupdate run --token "$TUNNEL_TOKEN" &

# 5. 高级端口与进程级真随时监控（用端口检查替代不稳定的PID名字检查，彻底断绝友军误伤）
while true; do
  sleep 10

  # 探测 Xray 的 8080 监听端口是否正常在线
  netstat -tln | grep -q :8080
  XRAY_PORT_STATUS=$?

  # 探测 网页后台 的 8081 监听端口是否正常在线
  netstat -tln | grep -q :8081
  HTTPD_PORT_STATUS=$?

  # 探测 隧道 容器进程是否活着
  pidof cloudflared > /dev/null
  CF_PROCESS_STATUS=$?

  # 只要有任何一个端口不响应或者隧道挂了，才真正触发自愈重启
  if [ $XRAY_PORT_STATUS -ne 0 ] || [ $HTTPD_PORT_STATUS -ne 0 ] || [ $CF_PROCESS_STATUS -ne 0 ]; then
    echo "🚨 【真实警报】检测到核心服务断流！(Xray端口:$XRAY_PORT_STATUS, 网页端口:$HTTPD_PORT_STATUS, 隧道进程:$CF_PROCESS_STATUS)"
    echo "正在强制关闭容器以触发自动重启..."
    exit 1
  fi
done
