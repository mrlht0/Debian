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

# ===== ttyd (static, không phụ thuộc OS) =====
RUN wget -qO /usr/local/bin/ttyd \
https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
&& chmod +x /usr/local/bin/ttyd

# ===== caddy (stable binary) =====
RUN wget -qO /usr/local/bin/caddy \
https://github.com/caddyserver/caddy/releases/latest/download/caddy_linux_amd64 \
&& chmod +x /usr/local/bin/caddy

# ===== Caddy config =====
RUN mkdir -p /etc/caddy && printf '\
:8080 {\n\
  reverse_proxy localhost:20128\n\
}\n' > /etc/caddy/Caddyfile

# ===== start =====
CMD sh -c "\
bun server.js & \
ttyd -p 8081 -W bash & \
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile"
