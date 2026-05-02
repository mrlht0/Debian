# FROM debian:bookworm-slim

# ENV DEBIAN_FRONTEND=noninteractive
# ENV PORT=8080
# ENV PASSWORD=123456

# # ─── Install base ─────────────────────────────────────────
# RUN apt-get update && apt-get install -y \
#     curl wget git bash nano \
#     procps htop \
#     ca-certificates \
#     build-essential \
#     python3 python3-pip \
#     && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
#     && apt-get install -y nodejs \
#     && apt-get clean && rm -rf /var/lib/apt/lists/*

# # ─── Install ttyd ─────────────────────────────────────────
# RUN wget -O /usr/local/bin/ttyd \
#     https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
#     chmod +x /usr/local/bin/ttyd

# # ─── Workspace ────────────────────────────────────────────
# WORKDIR /workspace

# # ─── Đổi user ────────────────────────────────────────────
# RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# # ─── Start script ─────────────────────────────────────────
# RUN printf '#!/bin/bash\n\
# echo "Starting ttyd on port $PORT"\n\
# exec ttyd -p $PORT -c :$PASSWORD -W bash\n\
# ' > /start.sh && chmod +x /start.sh

# EXPOSE 8080

# CMD ["/start.sh"]

# =============================================================
# Hai user 1 port
# ============================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

RUN apt-get update && apt-get install -y \
    nginx curl wget git bash \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ttyd
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# users
RUN useradd -m admin && echo "admin:admin123" | chpasswd
RUN useradd -m test && echo "test:123" | chpasswd

RUN mkdir -p /workspace/test && chown -R test:test /workspace/test

# hạn chế test
RUN printf 'cd /workspace/test\nexport TMOUT=900\nalias cd="echo blocked"\n' > /home/test/.bashrc

# nginx config
RUN printf 'server {\n\
    listen %s;\n\
\n\
    location /admin/ {\n\
        proxy_pass http://localhost:7681/;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "upgrade";\n\
    }\n\
\n\
    location /test/ {\n\
        proxy_pass http://localhost:7682/;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "upgrade";\n\
    }\n\
}\n' "$PORT" > /etc/nginx/sites-enabled/default

# start
RUN printf '#!/bin/bash\n\
ttyd -p 7681 -c admin:admin123 bash &\n\
ttyd -p 7682 -c test:123 su - test &\n\
nginx -g "daemon off;"\n\
' > /start.sh && chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
