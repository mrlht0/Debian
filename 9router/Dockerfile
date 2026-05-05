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

# 1. Tải ttyd & Caddy (đảm bảo file binary sạch)
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && chmod +x /usr/local/bin/ttyd
RUN wget -qO /usr/local/bin/caddy "https://caddyserver.com/api/download?os=linux&arch=amd64" && chmod +x /usr/local/bin/caddy

# 2. Cấu hình Caddyfile
RUN mkdir -p /etc/caddy && printf ":8080 {\n\
    handle /terminal* {\n\
        reverse_proxy localhost:8082\n\
    }\n\
    handle {\n\
        reverse_proxy localhost:8081\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 3. Tạo script khởi chạy độc lập
RUN printf '#!/bin/bash\n\
echo "--- Đang khởi chạy hệ thống tùy chỉnh ---"\n\
\n\
# Chạy ttyd cổng 8081 (Trang chủ)\n\
ttyd -p 8081 -W bash &\n\
\n\
# Chạy ttyd cổng 8082 (Cho path /terminal)\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
echo "Caddy đang điều phối tại port 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

# --- BƯỚC QUAN TRỌNG NHẤT ---
# Xóa bỏ Entrypoint mặc định của image gốc để nó không chạy cái Menu kia nữa
ENTRYPOINT []

# Thiết lập Port và chạy script của mình
ENV PORT=8080
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
