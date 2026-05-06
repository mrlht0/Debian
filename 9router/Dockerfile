# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=10000

# # đảm bảo bind ra ngoài
# EXPOSE 10000

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69
USER root

ENV APP_NAME=9router
ENV PORT=8080

# Cài tool cần thiết
RUN apk update && apk add --no-cache wget ca-certificates bash tar socat net-tools

# Cài ttyd
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# Cài Caddy
RUN wget -qO /tmp/caddy.tar.gz https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz \
    && tar -zxvf /tmp/caddy.tar.gz -C /usr/local/bin caddy \
    && chmod +x /usr/local/bin/caddy

# Caddyfile
RUN mkdir -p /etc/caddy && printf '{\n\
    admin off\n\
}\n\
\n\
:8080 {\n\
\n\
    handle_path /terminal* {\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
\n\
    handle_path /openclaw* {\n\
        reverse_proxy 127.0.0.1:18789\n\
    }\n\
\n\
    handle_path /app* {\n\
        reverse_proxy 127.0.0.1:{env.APP_PORT}\n\
    }\n\
\n\
    handle {\n\
        reverse_proxy 127.0.0.1:{env.APP_PORT}\n\
    }\n\
}\n\
' > /etc/caddy/Caddyfile

# 🔥 run.sh inline (KHÔNG lỗi escape)
RUN printf '#!/bin/bash\n\
#!/bin/bash
echo "🚀 Starting $APP_NAME..."

cd /root
export PS1="9router:\w# "

echo "🖥 Starting ttyd..."
ttyd -p 8082 -W -b /terminal bash &

sleep 3

# 🔥 detect 9router thật
TARGET=$(netstat -tulnp | grep 10000 | head -n 1 | awk '{print $4}')

IP=$(echo $TARGET | cut -d: -f1)
PORT=$(echo $TARGET | cut -d: -f2)

echo "🔥 9router detected at $IP:$PORT"

# 🔥 bridge network
echo "🌉 Bridging $IP:$PORT -> 127.0.0.1:10000"
socat TCP-LISTEN:10000,fork TCP:$IP:$PORT &

export APP_PORT=10000

echo "=============================="
echo " APP:       /"
echo " TERMINAL:  /terminal"
echo "=============================="

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
' > /run.sh && chmod +x /run.sh

ENTRYPOINT []
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
