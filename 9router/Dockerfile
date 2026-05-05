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
RUN apk update && apk add --no-cache wget ca-certificates bash

# 1. Tải ttyd (Binary chuẩn)
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && chmod +x /usr/local/bin/ttyd

# 2. Tải Caddy (Dùng link trực tiếp từ GitHub để tránh file lỗi "Contact")
# Bản v2.8.4 dành cho Linux amd64
RUN wget -qO /tmp/caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz" \
    && tar -zxvf /tmp/caddy.tar.gz -C /usr/local/bin caddy \
    && chmod +x /usr/local/bin/caddy \
    && rm /tmp/caddy.tar.gz

# 3. Cấu hình Caddyfile
RUN mkdir -p /etc/caddy && printf ":8080 {\n\
    handle /terminal* {\n\
        reverse_proxy localhost:8082\n\
    }\n\
    handle {\n\
        reverse_proxy localhost:8081\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 4. Script khởi chạy (Thêm dấu gạch chéo cuối để tránh lỗi 404)
RUN printf '#!/bin/bash\n\
echo "--- Khởi chạy Cloud Dev v2026 ---"\n\
\n\
# ttyd 1 làm trang chủ\n\
ttyd -p 8081 -W bash &\n\
\n\
# ttyd 2 cho path /terminal\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
echo "Caddy đang chạy tại port 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

# Xóa bỏ Entrypoint cũ của image gốc
ENTRYPOINT []

ENV PORT=8080
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
