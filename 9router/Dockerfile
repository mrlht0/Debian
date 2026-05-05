# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69
USER root
ENV APP_NAME=9router

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
        uri strip_prefix /terminal\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
    handle {\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 3. Script khởi chạy run.sh (Cập nhật tên 9router và Fix path)
RUN printf '#!/bin/bash\n\
echo "--- Hệ thống 9router đang khởi động ---"\n\
\n\
# Tìm đường dẫn Bun một cách tuyệt đối\n\
BUN_BIN=$(find / -name bun -type f -executable 2>/dev/null | head -n 1)\n\
if [ -z "$BUN_BIN" ]; then BUN_BIN="bun"; fi\n\
\n\
# Tìm file server.js và cd vào thư mục đó\n\
SERVER_FILE=$(find / -name server.js 2>/dev/null | head -n 1)\n\
cd $(dirname "$SERVER_FILE")\n\
\n\
echo "9router App đang chạy tại $(pwd)..."\n\
$BUN_BIN server.js --port 10000 &\n\
\n\
echo "9router Terminal đang chạy trên cổng 8082..."\n\
APP_NAME=${APP_NAME:-9router}\n\
ttyd -p 8082 -W -b /terminal bash -c "cd $(pwd) && bash" &\n\
"echo '🚀 Welcome to $APP_NAME' && bash"\n\
\n\
echo "Caddy (Gateway 9router) đang điều phối cổng 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

# Xóa bỏ entrypoint cũ
ENTRYPOINT []
ENV PORT=8080
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
