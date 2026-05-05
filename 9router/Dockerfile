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

# Cài đặt công cụ cần thiết
RUN apk update && apk add --no-cache wget ca-certificates bash tar

# 1. Tải ttyd & Caddy chuẩn
RUN wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && chmod +x /usr/local/bin/ttyd
RUN wget -qO /tmp/caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_amd64.tar.gz" \
    && tar -zxvf /tmp/caddy.tar.gz -C /usr/local/bin caddy && chmod +x /usr/local/bin/caddy

# 2. Cấu hình Caddyfile (Dùng 127.0.0.1 để tránh lỗi Connection Refused)
RUN mkdir -p /etc/caddy && printf "{\n\
    admin off\n\
}\n\
:8080 {\n\
    handle /terminal* {\n\
        uri strip_prefix /terminal\n\
        reverse_proxy 127.0.0.1:8082\n\
    }\n\
\n\
    handle /ds2api* {\n\
#        uri strip_prefix /10000\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
\n\
    handle {\n\
        uri strip_prefix /10000\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
}" > /etc/caddy/Caddyfile

# 3. Script khởi chạy run.sh (Cập nhật tên 9router và Fix path)
RUN printf '#!/bin/bash\n\
echo "--- Hệ thống 9router đang khởi động ---"\n\
\n\
cd /app 2>/dev/null || cd /root\n\
\n\
echo "9router App đang chạy tại $(pwd)..."\n\
PORT=10000 node server.js &\n\
\n\
echo "9router Terminal đang chạy..."\n\
ttyd -p 8082 -W -b /terminal bash -c "cd $(pwd) && bash" &\n\

echo "Caddy (Gateway 9router) đang điều phối cổng 8080..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

# Xóa bỏ entrypoint cũ
ENTRYPOINT []
ENV PORT=8080
EXPOSE 8080

CMD ["/bin/bash", "/run.sh"]
