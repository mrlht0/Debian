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

# 3. Script khởi chạy (Sử dụng đường dẫn tuyệt đối để fix lỗi "command not found")
RUN printf '#!/bin/bash\n\
echo "--- System Status ---"\n\
\n\
# Tìm đường dẫn bun thực tế nếu /usr/local/bin/bun không tồn tại\n\
BUN_BIN=$(which bun || echo "/usr/local/bin/bun")\n\
\n\
echo "Starting Bun App with $BUN_BIN..."\n\
$BUN_BIN server.js &\n\
\n\
echo "Starting Terminal on 8082..."\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
echo "Caddy is proxying on 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

# Đảm bảo lệnh ENTRYPOINT được xóa bỏ
ENTRYPOINT []

# Thiết lập môi trường
WORKDIR /app
ENV PORT=8080
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
