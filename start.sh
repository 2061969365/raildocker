#!/bin/bash

# 1. 动态安全初始化密钥
if [ -z "$UUID" ]; then
  export UUID=$(/usr/bin/xray uuid)
  echo "⚠️ 未检测到自定义 UUID，系统已自动生成随机密钥: $UUID"
else
  echo "🔑 当前节点正在使用自定义密钥: $UUID"
fi

# 动态注入密钥到内核配置文件和前端页面
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/config.json
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /app/www/index.html

# 2. 启动 Alpine 增强网页服务器（监听 8081 端口）
httpd -p 8081 -h /app/www &
echo "🌐 静态网页后台已在本地 8081 端口拉起"

# 3. 启动 Xray 核心组件（监听 8080 端口）
/usr/bin/xray -config /app/config.json &
echo "🚀 Xray 核心组件已在本地 8080 端口拉起"

# 4. 验证并运行 Cloudflare Tunnel 隧道
if [ -z "$TUNNEL_TOKEN" ]; then
  echo "❌ 【错误】未检测到 TUNNEL_TOKEN 环境变量，隧道无法建立！"
  exit 1
fi

echo "🚇 正在通过 QUIC (UDP) 协议向 Cloudflare 边缘网络建立加密大桥..."
/usr/local/bin/cloudflared tunnel --protocol quic --no-autoupdate run --token "$TUNNEL_TOKEN" &

# 5. 核心监控、系统硬核状态指标采集循环
while true; do
  sleep 10

  # --- 📊 仪表盘数据采集逻辑 ---
  # 采集 CPU 占用率
  IDLE=$(top -b -n 1 | grep "CPU:" | awk '{for(i=1;i<=NF;i++) if($i ~ /idle/) print $(i-1)}' | tr -d '%')
  CPU_PCT=$((100 - IDLE))

  # 采集内存占用率
  MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  MEM_FREE=$(awk '/MemFree/ {print $2}' /proc/meminfo)
  MEM_BUFFERS=$(awk '/Buffers/ {print $2}' /proc/meminfo)
  MEM_CACHED=$(awk '/Cached/ {print $2}' /proc/meminfo)
  MEM_USED=$((MEM_TOTAL - MEM_FREE - MEM_BUFFERS - MEM_CACHED))
  MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))

  # 采集累计消耗流量 (排除本地回环 lo)
  RX_BYTES=$(awk '!/lo|face/ {rx+=$2} END {print rx}' /proc/net/dev)
  TX_BYTES=$(awk '!/lo|face/ {tx+=$10} END {print tx}' /proc/net/dev)

  # 生成轻量级实时状态 JSON 供前端读取
  echo "{\"cpu\":$CPU_PCT,\"mem\":$MEM_PCT,\"rx\":$RX_BYTES,\"tx\":$TX_BYTES}" > /app/www/status.json

  # --- 📡 双端口雷达监控逻辑 ---
  netstat -tln | grep -q :8080
  VLESS_PORT=$?
  netstat -tln | grep -q :8081
  HTTP_PORT=$?
  pidof cloudflared > /dev/null
  CF_PROCESS=$?

  if [ $VLESS_PORT -ne 0 ] || [ $HTTP_PORT -ne 0 ] || [ $CF_PROCESS -ne 0 ]; then
    echo "🚨 【断流警报】检测到硬断流！(VLESS:$VLESS_PORT, 网页:$HTTP_PORT, 隧道:$CF_PROCESS)"
    exit 1
  fi
done
