# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69
USER root

# Cài đặt công cụ cần thiết
RUN apk update && apk add --no-cache wget ca-certificates bash tar

# 1. Tải ttyd & Caddy chuẩn
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && chmod +x /usr/local/bin/ttyd
RUN wget -qO /tmp/caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz" \
    && tar -zxvf /tmp/caddy.tar.gz -C /usr/local/bin caddy && chmod +x /usr/local/bin/caddy

# 2. Cấu hình Caddyfile (Dùng 127.0.0.1 để tránh lỗi Connection Refused)
RUN mkdir -p /etc/caddy && printf "{\n\
    admin off\n\
}\n\
:8080 {\n\
    handle /terminal* {\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
    handle {\n\
        reverse_proxy 127.0.0.1:20128\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 3. Script khởi chạy (Cần tìm đúng thư mục chứa server.js)
RUN printf '#!/bin/bash\n\
echo "--- Khởi động hệ thống ---"\n\
\n\
# Tìm thư mục chứa server.js (Thường là /app hoặc /)\n\
APP_DIR="/app"\n\
if [ ! -d "$APP_DIR" ]; then APP_DIR="/"; fi\n\
cd $APP_DIR\n\
\n\
# Lấy đường dẫn Bun chuẩn\n\
BUN_BIN=$(which bun || echo "/usr/local/bin/bun")\n\
\n\
echo "Đang chạy Bun từ thư mục: $(pwd)"\n\
$BUN_BIN server.js & \n\
\n\
echo "Khởi động Terminal trên 8082..."\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
echo "Caddy xuất kích cổng 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

ENTRYPOINT []
# Quan trọng: Set WORKDIR về đúng nơi chứa code
WORKDIR /app
ENV PORT=8080
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
