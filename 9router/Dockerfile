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

# Cài tool cần thiết
RUN apk update && apk add --no-cache wget ca-certificates bash tar net-tools

# Cài ttyd
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# Cài Caddy
RUN wget -qO /tmp/caddy.tar.gz https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz \
    && tar -zxvf /tmp/caddy.tar.gz -C /usr/local/bin caddy \
    && chmod +x /usr/local/bin/caddy

# Caddyfile
RUN mkdir -p /etc/caddy && printf '{\n\
    admin off\n\
}\n\
\n\
:8080 {\n\
\n\
    handle_path /terminal* {\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
\n\
    handle_path /openclaw* {\n\
        reverse_proxy 127.0.0.1:18789\n\
    }\n\
\n\
    handle_path /app* {\n\
        reverse_proxy 127.0.0.1:{env.APP_PORT}\n\
    }\n\
\n\
    handle {\n\
        reverse_proxy 127.0.0.1:{env.APP_PORT}\n\
    }\n\
}\n\
' > /etc/caddy/Caddyfile

# 🔥 run.sh inline (KHÔNG lỗi escape)
RUN printf '#!/bin/bash\n\
echo "🚀 Starting $APP_NAME..."\n\
\n\
cd /root\n\
\n\
export PS1="9router:\\w# "\n\
\n\
echo "🖥 Starting ttyd..."\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
sleep 3\n\
\n\
# 🔥 detect port chuẩn\n\
if netstat -tuln | grep -q ":10000"; then\n\
    APP_PORT=10000\n\
else\n\
    APP_PORT=$(netstat -tuln \\\n\
      | grep LISTEN \\\n\
      | awk '\''{print $4}'\'' \\\n\
      | awk -F: '\''{print $NF}'\'' \\\n\
      | grep -v 8082 \\\n\
      | sort -n \\\n\
      | uniq \\\n\
      | head -n 1)\n\
fi\n\
\n\
APP_PORT=${APP_PORT:-8082}\n\
\n\
echo "🔥 Detected APP_PORT=$APP_PORT"\n\
\n\
export APP_PORT\n\
\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

ENTRYPOINT []
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
