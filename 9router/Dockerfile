# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]


FROM antiantiops/9router:0.3.69

ENV PORT=8080
WORKDIR /workspace

# =========================
# 1. ttyd (static binary)
# =========================
RUN wget -qO /usr/local/bin/ttyd \
https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
&& chmod +x /usr/local/bin/ttyd

# =========================
# 2. caddy (static binary)
# =========================
RUN wget -qO /usr/local/bin/caddy \
https://github.com/caddyserver/caddy/releases/latest/download/caddy_2.8.4_linux_amd64 \
&& chmod +x /usr/local/bin/caddy

# =========================
# 3. Caddy config (gateway 1 port)
# =========================
RUN mkdir -p /etc/caddy && cat <<EOF > /etc/caddy/Caddyfile
:8080 {

    handle /terminal* {
        reverse_proxy localhost:7681
    }

    handle /ttyd* {
        reverse_proxy localhost:8081
    }

    handle / {
        reverse_proxy localhost:20128
    }
}
EOF

# =========================
# 4. Start script (QUAN TRỌNG)
# =========================
RUN cat <<'EOF' > /start.sh
#!/bin/sh

echo "Starting services..."

# 9router (app chính)
bun server.js &

# ttyd web terminal
ttyd -p 7681 -W bash &

# fallback ttyd
ttyd -p 8081 -W bash &

# Caddy MUST be foreground process (Render yêu cầu)
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
EOF

RUN chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
