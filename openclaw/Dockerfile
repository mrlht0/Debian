
FROM alpine/openclaw:2026.5.6
USER root

ENV APP_NAME=9router
ENV PORT=8080

RUN apk add --no-cache bash wget ca-certificates tar net-tools

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
    handle /terminal* {\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
\n\
    handle /9router* {\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
\n\
    handle {\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# ================= RUN SCRIPT =================
RUN cat > /run.sh <<'EOF'
#!/bin/bash

echo "🚀 Khởi động hệ thống 9router Custom..."
# 1. Tên máy
cd /root
export PS1="9router:\w# "

# 2. Khởi chạy Terminal (ttyd)
echo "🖥 Đang khởi động Terminal..."
# Dùng bash login để nạp đủ biến môi trường
ttyd -p 8082 -W -b /terminal bash &

echo "--- Bước 4: Kích hoạt App chính ---"
# cd /usr/local/lib/node_modules/9router/app

# export HOST=0.0.0.0
# export HOSTNAME=0.0.0.0
# export PORT=10000

# Chạy node server.js làm tiến trình chính của Container
echo "Đang thực thi: node server.js tại $(pwd)"
# exec node server.js &

# Dùng >/dev/null 2>&1 để vứt bỏ toàn bộ log xuất ra
# Khởi chạy App chính trong một vòng lặp chạy ngầm
# (
#   while true; do
#       echo "Đang khởi động App..."
#       node server.js >/dev/null 2>&1
#       # Vòng lặp sẽ DỪNG LẠI ở đây cho đến khi node server.js bị sập
#       echo "App sập, đang khởi động lại sau 2 giây..."
#       sleep 2
#   done
# ) &

sleep 5

echo "=============================================="
echo " ✅ Hệ thống đã sẵn sàng tại Port 8080"
echo " 🌐 APP:      /"
echo " 📟 TERMINAL: /terminal/"
echo "=============================================="

# 4. Khởi chạy Caddy (Tiến trình chính)
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
EOF

# Cấp quyền thực thi cho script
RUN chmod +x /run.sh

# ================= QUAN TRỌNG: PHÁ KHÓA ENTRYPOINT =================
ENTRYPOINT []

# Render Dashboard cần được set Port 8080 thủ công
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
