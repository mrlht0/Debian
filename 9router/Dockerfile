# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

# ==============================================================
# 9router + ttyd + Caddy (Clean Render Version)
# ==============================================================

FROM antiantiops/9router:0.3.69

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

# ─── 1. Cài Caddy + ttyd ─────────────────────────
RUN apt update && apt install -y \
    caddy \
    curl \
    wget \
    ca-certificates \
    && apt clean && rm -rf /var/lib/apt/lists/*

# ttyd binary
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 2. Caddy config (1 port public) ─────────────────────────
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

# ─── 3. Start script (IMPORTANT: 1 PID pattern correct) ───────
RUN printf '#!/bin/bash\n\
echo "Starting 9router stack..."\n\
\n\
# 9router main app (port 20128)\n\
bun server.js &\n\
\n\
# ttyd shell (port 8081)\n\
ttyd -p 8081 -W bash &\n\
\n\
# optional ttyd terminal (port 8082)\n\
ttyd -p 8082 -W bash &\n\
\n\
# caddy reverse proxy (MAIN PROCESS)\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /start.sh && chmod +x /start.sh

# ─── 4. Port expose ─────────────────────────
EXPOSE 8080

CMD ["/start.sh"]
