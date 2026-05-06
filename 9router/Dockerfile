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
        reverse_proxy 0.0.0.0:10000\n\
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
sleep 2\n\
\n\
# 🔥 FIX 1: lấy IP container an toàn\n\
IP=$(hostname -i | awk '\''{print $1}'\'')\n\
PORT=10000\n\
\n\
echo "🔥 detected $IP:$PORT"\n\
\n\
# 🔥 FIX 2: chỉ bridge nếu IP tồn tại\n\
if [ -n "$IP" ]; then\n\
    echo "🌉 bridging $IP:$PORT -> 127.0.0.1:10000"\n\
    socat TCP-LISTEN:10000,fork,reuseaddr TCP:$IP:$PORT &\n\
else\n\
    echo "⚠️ Cannot detect IP, skip socat"\n\
fi\n\
\n\
export APP_PORT=10000\n\
\n\
echo "=============================="\n\
echo " APP:       /"\n\
echo " TERMINAL:  /terminal"\n\
echo "=============================="\n\
\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

ENTRYPOINT []
EXPOSE 8080
CMD ["/bin/bash", "/run.sh"]
