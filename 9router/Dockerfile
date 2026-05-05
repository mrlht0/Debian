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

# 3. Cấu hình Caddyfile sử dụng snippet như ý bạn
RUN mkdir -p /etc/caddy && printf "(proxy_port) {\n\
    handle /{args.0}* {\n\
        reverse_proxy localhost:{args.0}\n\
    }\n\
}\n\
\n\
:8080 {\n\
    # Ưu tiên handle cho terminal trước
    handle /terminal* {\n\
        reverse_proxy localhost:7681\n\
    }\n\
\n\
    # Tất cả các path khác đẩy về Bun server
    handle {\n\
        reverse_proxy localhost:20128\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 4. Thiết lập Port
ENV PORT=8080
EXPOSE 8080

# 5. Khởi chạy
# LƯU Ý: Thêm -b /terminal để ttyd biết nó đang nằm ở path đó
CMD ttyd -p 7681 -W -b /terminal bash & \
    bun server.js & \
    caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
