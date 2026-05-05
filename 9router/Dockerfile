# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69

USER root

# Cài đặt công cụ
RUN apk update && apk add --no-cache wget ca-certificates bash

# 1. Cài ttyd & Caddy
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && chmod +x /usr/local/bin/ttyd
RUN wget -qO /usr/local/bin/caddy "https://caddyserver.com/api/download?os=linux&arch=amd64" && chmod +x /usr/local/bin/caddy

# 2. Cấu hình Caddyfile (Dùng handle_path để sạch path hơn)
RUN mkdir -p /etc/caddy && printf ":8080 {\n\
    handle_path /terminal* {\n\
        reverse_proxy localhost:7681\n\
    }\n\
    handle {\n\
        reverse_proxy localhost:20128\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 3. Tạo Script khởi chạy (Fix lỗi 404 bằng cách bỏ -b vì đã dùng handle_path)
RUN printf '#!/bin/bash\n\
echo "Khởi động ttyd..."\n\
ttyd -p 7681 -W bash &\n\
\n\
echo "Khởi động Bun Server..."\n\
bun server.js &\n\
\n\
echo "Khởi động Caddy..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

# 4. Render Port
ENV PORT=8080
EXPOSE 8080

# Chạy bằng script
CMD ["/bin/bash", "/run.sh"]
