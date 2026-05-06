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

RUN apk add --no-cache bash wget ca-certificates tar socat net-tools

RUN wget -qO /usr/local/bin/ttyd \
https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
&& chmod +x /usr/local/bin/ttyd

RUN wget -qO /tmp/caddy.tar.gz \
https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz \
&& tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy \
&& chmod +x /usr/local/bin/caddy

# Caddyfile
RUN mkdir -p /etc/caddy && printf '{\n\
    admin off\n\
}\n\
\n\
:8080 {\n\
    handle_path /terminal* {\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
\n\
    handle_path /9router* {\n\
        reverse_proxy 0.0.0.0:10000\n\
    }\n\
\n\
    handle {\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# ================= RUN =================
RUN cat > /run.sh <<'EOF'
#!/bin/bash

echo "🚀 Starting 9router..."

cd /root
export PS1="9router:\w# "

# ======================
# Terminal (ttyd)
# ======================
echo "🖥 ttyd starting..."
ttyd -p 8082 -W -b /terminal bash &

sleep 2

# ======================
# FIX QUAN TRỌNG: detect IP đúng môi trường container
# ======================
IP=$(hostname -i | awk '{print $1}')
PORT=10000

echo "🔥 detected container IP: $IP:$PORT"

# ======================
# Bridge giữa 2 môi trường
# ======================
if [ -n "$IP" ]; then
    echo "🌉 bridging $IP:$PORT -> 127.0.0.1:10000"
    socat TCP-LISTEN:10000,fork,reuseaddr TCP:$IP:$PORT &
else
    echo "⚠️ cannot detect IP, skip bridge"
fi

export APP_PORT=10000

echo "=============================="
echo " APP:       /"
echo " TERMINAL:  /terminal"
echo "=============================="

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
EOF

RUN chmod +x /run.sh

# ======================
# Runtime
# ======================
ENTRYPOINT []
EXPOSE 8080
CMD ["/bin/bash", "/run.sh"]


# FROM antiantiops/9router:0.3.69

# USER root

# ENV APP_NAME=9router
# ENV PORT=8080
# ENV NODE_ENV=production

# RUN apk add --no-cache bash wget ca-certificates tar net-tools

# # ttyd
# RUN wget -qO /usr/local/bin/ttyd \
# https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
# && chmod +x /usr/local/bin/ttyd

# # caddy
# RUN wget -qO /tmp/caddy.tar.gz \
# https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz \
# && tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy \
# && chmod +x /usr/local/bin/caddy

# # COPY FULL SOURCE (quan trọng)
# WORKDIR /opt/9router
# COPY . /opt/9router

# # Caddy config (CHỈ LOCALHOST)
# RUN mkdir -p /etc/caddy && cat > /etc/caddy/Caddyfile <<'EOF'
# {
#     admin off
# }

# :8080 {

#     handle_path /terminal* {
#         reverse_proxy 127.0.0.1:8082
#     }

#     handle_path /app* {
#         reverse_proxy 127.0.0.1:10000
#     }

#     handle {
#         reverse_proxy 127.0.0.1:10000
#     }
# }
# EOF

# # RUN SCRIPT (SẠCH, KHÔNG IP DETECT)
# RUN cat > /run.sh <<'EOF'
# #!/bin/bash

# echo "🚀 9router production mode"

# cd /opt/9router

# export PORT=10000
# export HOSTNAME=127.0.0.1

# # terminal
# ttyd -p 8082 -W -b /terminal bash &

# sleep 2

# echo "▶ Starting NEXT SERVER ONLY"

# # CHỈ chạy server.js (KHÔNG CLI)
# node node_modules/9router/app/server.js &

# echo "======================"
# echo "APP: /"
# echo "TERM: /terminal"
# echo "======================"

# exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
# EOF

# RUN chmod +x /run.sh

# EXPOSE 8080

# CMD ["/bin/bash", "/run.sh"]
