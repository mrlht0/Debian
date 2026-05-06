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

# Cài tool
RUN apk update && apk add --no-cache wget ca-certificates bash tar net-tools

# Cài ttyd
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# Cài Caddy
RUN wget -qO /tmp/caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz" \
    && tar -zxvf /tmp/caddy.tar.gz -C /usr/local/bin caddy \
    && chmod +x /usr/local/bin/caddy

# Caddyfile
RUN mkdir -p /etc/caddy && printf '{
    admin off
}

:8080 {
    handle /terminal* {
        uri strip_prefix /terminal
        reverse_proxy 127.0.0.1:8082
    }

    handle {
        reverse_proxy 127.0.0.1:{env.PORT_DETECT}
    }
}
' > /etc/caddy/Caddyfile

# Copy script chạy
COPY run.sh /run.sh
RUN chmod +x /run.sh

ENTRYPOINT []
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
