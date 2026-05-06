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
# Tên máy
cd /root
export PS1="9router:\w# "\n\

# 1. Khởi chạy App chính (Node.js)
echo "📦 Đang khởi động App chính tại cổng 10000..."
export PORT=10000
export HOSTNAME=0.0.0.0
cd /usr/local/lib/node_modules/9router/app && node server.js &

# 2. Khởi chạy Terminal (ttyd)
echo "🖥 Đang khởi động Terminal..."
# Dùng bash login để nạp đủ biến môi trường
ttyd -p 8082 -W -b /terminal bash &

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
