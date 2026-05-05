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
        reverse_proxy 127.0.0.1:7681\n\
    }\n\
    handle {\n\
        reverse_proxy 127.0.0.1:20128\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 3. Script khởi chạy
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev..."\n\
\n\
# 1. ttyd chính (Giao diện điều khiển - Cổng 8081)\n\
# Giả sử bạn muốn cái này làm trang chủ\n\
ttyd -p 8081 -W bash &\n\
\n\
# 2. ttyd phụ (Cổng 8082 cho đường dẫn /terminal)\n\
# Dùng -b /terminal để ttyd tự xử lý định tuyến bên trong nó\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
echo "Caddy đang lắng nghe tại port 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

# Render sẽ nhận diện port này
ENV PORT=8080
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
