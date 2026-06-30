FROM teddysun/xray:latest AS xray-source
FROM cloudflare/cloudflared:latest AS cf-source

FROM alpine:latest
# 核心修复：安装 busybox-extras 以补全被 Alpine 阉割掉的 httpd 网页服务器组件
RUN apk add --no-cache bash curl busybox-extras

COPY --from=xray-source /usr/bin/xray /usr/bin/xray
COPY --from=cf-source /usr/local/bin/cloudflared /usr/local/bin/cloudflared

WORKDIR /app
COPY . .

RUN sed -i 's/\r$//' /app/start.sh
RUN chmod +x /app/start.sh
ENTRYPOINT ["/app/start.sh"]
