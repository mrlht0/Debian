# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69

USER root

# Sử dụng apk cho Alpine Linux
RUN apk update && apk add --no-cache wget ca-certificates bash

# 1. Cài ttyd
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# 2. Cài Caddy (Tải bản dành cho Linux x86_64)
RUN wget -qO /usr/local/bin/caddy "https://caddyserver.com/api/download?os=linux&arch=amd64" \
    && chmod +x /usr/local/bin/caddy

# 3. Cấu hình Caddyfile
RUN mkdir -p /etc/caddy && echo ":$PORT { \n\
    handle /terminal* { \n\
        reverse_proxy localhost:7681 \n\
    } \n\
    handle { \n\
        reverse_proxy localhost:20128 \n\
    } \n\
}" > /etc/caddy/Caddyfile

# 4. Thiết lập Port (Render thường dùng biến môi trường $PORT)
ENV PORT=8080
EXPOSE 8080

# 5. Lệnh khởi chạy song song
CMD ttyd -p 7681 -W bash & caddy run --config /etc/caddy/Caddyfile --adapter caddyfile & bun server.js
