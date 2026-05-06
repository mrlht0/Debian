# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=10000

# # đảm bảo bind ra ngoài
# EXPOSE 10000

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

FROM antiantiops/9router:0.3.69
USER root

ENV APP_NAME=9router
ENV PORT=8080

RUN apk add --no-cache bash wget ca-certificates tar socat net-tools

RUN wget -qO /usr/local/bin/ttyd \
https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
&& chmod +x /usr/local/bin/ttyd

RUN wget -qO /tmp/caddy.tar.gz \
https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz \
&& tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy \
&& chmod +x /usr/local/bin/caddy

# Caddyfile
RUN mkdir -p /etc/caddy && printf '{\n\
    admin off\n\
}\n\
\n\
:8080 {\n\
    handle_path /terminal* {\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
\n\
    handle_path /9router* {\n\
        reverse_proxy 0.0.0.0:10000\n\
    }\n\
\n\
    handle {\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# copy FULL 9router (quan trọng nhất)
COPY . /opt/9router
WORKDIR /opt/9router

# run.sh
RUN cat > /run.sh <<'EOF'
#!/bin/bash

echo "🚀 9router FULL MODE START"\n\

cd /opt/9router\n\

export PORT=10000\n\
export HOSTNAME=0.0.0.0\n\

# terminal
ttyd -p 8082 -W -b /terminal bash &\n\

sleep 2\n\

echo "▶ Starting 9router core..."\n\

# IMPORTANT: chạy ROOT CLI chứ không phải app/server.js\n\
node cli.js &\n\

echo "========================"
echo "APP: /"
echo "TERM: /terminal"
echo "========================"

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
EOF

RUN chmod +x /run.sh

ENTRYPOINT []
EXPOSE 8080
CMD ["/bin/bash", "/run.sh"]
