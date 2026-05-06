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
    handle {\n\
        reverse_proxy 127.0.0.1:{env.APP_PORT}\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# run.sh (QUAN TRỌNG: chỉ tạo file)
RUN printf '#!/bin/bash\n\
echo "🚀 Starting 9router..."\n\
\n\
cd /root\n\
export PS1="9router:\\w# "\n\
\n\
echo "🖥 ttyd starting..."\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
sleep 3\n\
\n\
TARGET=$(netstat -tulnp | grep 10000 | head -n 1 | awk \"{print $4}\")\n\
IP=$(echo $TARGET | cut -d: -f1)\n\
PORT=$(echo $TARGET | cut -d: -f2)\n\
\n\
echo \"🔥 detected $IP:$PORT\"\n\
\n\
echo \"🌉 bridging...\"\n\
socat TCP-LISTEN:10000,fork TCP:$IP:$PORT &\n\
\n\
export APP_PORT=10000\n\
\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

ENTRYPOINT []
EXPOSE 8080
CMD ["/bin/bash", "/run.sh"]
