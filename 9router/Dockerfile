# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69

ENV PORT=8080

# Cài thêm Caddy để làm reverse proxy nội bộ
RUN apt update && apt install -y caddy && apt clean

# Caddy config (gom nhiều port → 1 port 8080)
RUN mkdir -p /etc/caddy && printf '\
:8080 {\n\
    handle / {\n\
        reverse_proxy localhost:20128\n\
    }\n\
\n\
    handle /terminal* {\n\
        reverse_proxy localhost:8082\n\
    }\n\
\n\
    handle /ttyd* {\n\
        reverse_proxy localhost:8081\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# Start script
RUN printf '#!/bin/bash\n\
echo "Starting services..."\n\
\n\
# app chính\n\
bun server.js &\n\
\n\
# caddy reverse proxy\n\
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /start.sh && chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
