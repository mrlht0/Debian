# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69
USER root

RUN apk update && apk add --no-cache wget ca-certificates bash

# Tải ttyd & Caddy chuẩn
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && chmod +x /usr/local/bin/ttyd
RUN wget -qO /tmp/caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz" \
    && tar -zxvf /tmp/caddy.tar.gz -C /usr/local/bin caddy && chmod +x /usr/local/bin/caddy

# Caddyfile fix lỗi 403
RUN mkdir -p /etc/caddy && printf "{\n    admin off\n}\n:8080 {\n    handle /terminal* {\n        reverse_proxy localhost:8082\n    }\n    handle {\n        reverse_proxy localhost:20128\n    }\n}" > /etc/caddy/Caddyfile

# Script chạy song song cả App Bun và Terminal
RUN printf '#!/bin/bash\n\
echo "Khởi động Bun App trên 20128..."\n\
bun server.js &\n\
\n\
echo "Khởi động Terminal trên 8082..."\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
echo "Caddy xuất kích trên 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

ENTRYPOINT []
ENV PORT=8080
EXPOSE 8080
CMD ["/bin/bash", "/run.sh"]
