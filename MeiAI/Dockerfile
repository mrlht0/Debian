# ==============================================================
# Cloud Dev: ttyd + tmux + Nginx (Full Fixed Multi-Route)
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── 1. Cài đặt các gói cơ bản (Thay caddy bằng nginx) ─────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    nginx \
    tar net-tools \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── 2. Cài đặt ttyd (bản mới nhất) ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 3. Cấu hình thư mục làm việc & Clone Repo ─────────────────
WORKDIR /
RUN apt-get update && apt-get install -y git openssh-client

RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /root/.ssh/id_ed25519 && \
    echo "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW" >> /root/.ssh/id_ed25519 && \
    echo "QyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+QAAAJCe7Zalnu2W" >> /root/.ssh/id_ed25519 && \
    echo "pQAAAAtzc2gtZWQyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+Q" >> /root/.ssh/id_ed25519 && \
    echo "AAAECu5uyGvQNoDwFalwDHbBQswmv31282a9dUGLoEnkLiIqVC9mYZaFP7edHr6L+/QjZF" >> /root/.ssh/id_ed25519 && \
    echo "AU6/Lg9Fyehi2v9QGTP5AAAAC3R5bGF1QE1yTEhUAQI=" >> /root/.ssh/id_ed25519 && \
    echo "-----END OPENSSH PRIVATE KEY-----" >> /root/.ssh/id_ed25519 && \
    chmod 600 /root/.ssh/id_ed25519 && \
    git clone git@github.com:mrlht0/MeiAI.git && \
    rm /root/.ssh/id_ed25519

WORKDIR /MeiAI

# Cài Go
RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz \
    && echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
ENV PATH="/usr/local/go/bin:${PATH}"

# Build Ứng dụng
RUN npm install
RUN cp config.example.json config.json
RUN npm ci --prefix webui --no-audit
RUN npm run build --prefix webui
RUN go build -o meiai ./cmd/meiai
RUN chmod +x meiai

ENV NODE_ENV=production \
    MEIAI_LITE_MODE=0 \
    MEIAI_ADMIN_KEY=admin \
    PORT=5001

# Watchdog Script cho MeiAI
RUN printf '#!/bin/bash\n\
cd /MeiAI\n\
LOG=/MeiAI/meiai.log\n\
touch $LOG\n\
while true; do\n\
    echo "==========================" >> $LOG\n\
    echo "[START] $(date)" >> $LOG\n\
    ./meiai >> $LOG 2>&1 &\n\
    PID=$!\n\
    while kill -0 $PID 2>/dev/null; do\n\
        tail -n 2000 $LOG > ${LOG}.tmp && mv ${LOG}.tmp $LOG\n\
        sleep 30\n\
    done\n\
    echo "[CRASH] restarting in 5s..." >> $LOG\n\
    sleep 5\n\
done\n\
' > /MeiAI/start-meiai.sh && chmod +x /MeiAI/start-meiai.sh

# ─── 4. Cấu hình Bash Prompt & Tmux ──────────────────────────────
WORKDIR /
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc
RUN printf "set -g mouse on\n\
unbind -n MouseDown3Pane\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n\
" > /root/.tmux.conf

# Script Khởi tạo Tmux
RUN printf '#!/bin/bash\n\
SESSION=main\n\
tmux has-session -t $SESSION 2>/dev/null\n\
if [ $? != 0 ]; then\n\
  tmux new-session -d -s $SESSION\n\
  tmux split-window -h\n\
  tmux split-window -v\n\
  tmux select-layout tiled\n\
fi\n\
exec tmux attach -t $SESSION\n\
' > /start.sh && chmod +x /start.sh

# ─── 5. Mem Guard ─────────────────────────────────────────────
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# ─── 6. Cấu hình NGINX thay thế cho Caddyfile (Đã sửa lỗi 404 & Trailing Slash) ───
RUN rm -f /etc/nginx/sites-enabled/default && \
printf 'server {\n\
    listen 8080 default_server;\n\
    server_name _;\n\
\n\
    # Header cấu hình chung tối ưu cho kết nối thời gian thực WebSocket (ttyd)\n\
    proxy_http_version 1.1;\n\
    proxy_set_header Upgrade $http_upgrade;\n\
    proxy_set_header Connection "Upgrade";\n\
    proxy_set_header Host $host;\n\
    proxy_set_header X-Real-IP $remote_addr;\n\
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\
    proxy_read_timeout 3600s;\n\
\n\
    # Sửa lỗi 404 bằng cách nhận diện cả có hoặc không có dấu gạch chéo cuối\n\
    location ~ ^/terminal(?<suffix>.*)$ {\n\
        proxy_pass http://127.0.0.1:8082$suffix$is_args$args;\n\
    }\n\
\n\
    location ~ ^/ttyd(?<suffix>.*)$ {\n\
        proxy_pass http://127.0.0.1:7681$suffix$is_args$args;\n\
    }\n\
\n\
    location ~ ^/tmux(?<suffix>.*)$ {\n\
        proxy_pass http://127.0.0.1:8081$suffix$is_args$args;\n\
    }\n\
\n\
    location ~ ^/openclaw(?<suffix>.*)$ {\n\
        proxy_pass http://127.0.0.1:18789$suffix$is_args$args;\n\
    }\n\
\n\
    location ~ ^/meiai(?<suffix>.*)$ {\n\
        proxy_pass http://127.0.0.1:5001$suffix$is_args$args;\n\
    }\n\
\n\
    # Xử lý dải cổng động hàng loạt (8083-8089 và 10001-10003)\n\
    location ~ ^/(808[3-9]|1000[1-3])(?<suffix>.*)$ {\n\
        proxy_pass http://127.0.0.1:$1$suffix$is_args$args;\n\
    }\n\
\n\
    # Tuyến mặc định tương đương khối handle cuối cùng của Caddy\n\
    location / {\n\
        rewrite ^/10000(.*)$ $1 break;\n\
        proxy_pass http://127.0.0.1:10000;\n\
    }\n\
}\n' > /etc/nginx/sites-available/clouddev && \
ln -s /etc/nginx/sites-available/clouddev /etc/nginx/sites-enabled/

# ─── 7. Script khởi chạy toàn bộ dịch vụ ─────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev với Nginx..."\n\
\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
(\n\
while true\n\
do\n\
    pgrep -f start-meiai.sh >/dev/null || nohup /MeiAI/start-meiai.sh > /dev/null 2>&1 &\n\
    sleep 60\n\
done\n\
) &\n\
\n\
ttyd -p 8081 -W -b /tmux /start.sh &\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
sleep 1\n\
\n\
echo "Nginx đang chạy..."\n\
exec nginx -g "daemon off;"\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080
CMD ["/run.sh"]
