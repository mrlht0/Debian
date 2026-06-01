# ==============================================================
# Cloud Dev: ttyd + tmux + NGINX (Thay thế Caddy)
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── 1. Cài đặt các gói cơ bản ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    nginx \
    tar net-tools \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── 2. Cài đặt ttyd ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 3. Cấu hình SSH & Clone repo ────────────────────────────
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

# ─── 4. Cài Go & Build MeiAI ─────────────────────────────────
RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz \
    && echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
ENV PATH="/usr/local/go/bin:${PATH}"
RUN go version

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

# ─── 5. Script auto-restart MeiAI ────────────────────────────
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

# ─── 6. Cấu hình Bash & Tmux ─────────────────────────────────
WORKDIR /
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

RUN printf "set -g mouse on\n\
unbind -n MouseDown3Pane\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n" > /root/.tmux.conf

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

# ─── 7. Cài mem_guard ────────────────────────────────────────
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# ─── 8. Cấu hình Nginx ───────────────────────────────────────
# Nginx dùng map + location để route nhiều path
# Khác Caddy: phải define từng upstream block riêng
# Ưu điểm: hiệu năng cực cao, kiểm soát chi tiết header
RUN rm -f /etc/nginx/sites-enabled/default && \
printf '# ── Map để xử lý WebSocket upgrade đúng cách ──\n\
# Nếu client gửi Upgrade header → set "upgrade", ngược lại → ""\n\
# Dùng $connection_upgrade thay vì hardcode "upgrade" để HTTP thường không bị lỗi\n\
map $http_upgrade $connection_upgrade {\n\
    default   "";\n\
    "websocket" "Upgrade";\n\
}\n\
\n\
server {\n\
    listen 8080;\n\
\n\
    # ── Terminal (ttyd phụ, bash thuần) ──\n\
    # Dùng location /terminal/ (có trailing slash) để match đúng /terminal/ws\n\
    # proxy_pass giữ nguyên path nhờ KHÔNG có URI sau địa chỉ upstream\n\
    location /terminal {\n\
        proxy_pass http://127.0.0.1:8082;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection $connection_upgrade;\n\
        proxy_set_header Host $host;\n\
        proxy_set_header X-Real-IP $remote_addr;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
\n\
    # ── ttyd gốc (port 7681) ──\n\
    location /ttyd {\n\
        proxy_pass http://127.0.0.1:7681;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection $connection_upgrade;\n\
        proxy_set_header Host $host;\n\
        proxy_set_header X-Real-IP $remote_addr;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
\n\
    # ── Tmux session ──\n\
    location /tmux {\n\
        proxy_pass http://127.0.0.1:8081;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection $connection_upgrade;\n\
        proxy_set_header Host $host;\n\
        proxy_set_header X-Real-IP $remote_addr;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
\n\
    # ── OpenClaw ──\n\
    location /openclaw {\n\
        proxy_pass http://127.0.0.1:18789;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
\n\
    # ── MeiAI ──\n\
    location /meiai {\n\
        proxy_pass http://127.0.0.1:5001;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
\n\
    # ── Port 10000 (vừa prefix vừa mặc định) ──\n\
    location /10000 {\n\
        proxy_pass http://127.0.0.1:10000;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
\n\
    # ── Các port hàng loạt 8083-8089 ──\n\
    location /8083 { proxy_pass http://127.0.0.1:8083; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /8084 { proxy_pass http://127.0.0.1:8084; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /8085 { proxy_pass http://127.0.0.1:8085; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /8086 { proxy_pass http://127.0.0.1:8086; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /8087 { proxy_pass http://127.0.0.1:8087; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /8088 { proxy_pass http://127.0.0.1:8088; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /8089 { proxy_pass http://127.0.0.1:8089; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
\n\
    # ── Port 10001-10003 ──\n\
    location /10001 { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /10002 { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
    location /10003 { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }\n\
\n\
    # ── Mặc định: forward tới 10000 (strip prefix) ──\n\
    location / {\n\
        proxy_pass http://127.0.0.1:10000;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
}\n' > /etc/nginx/conf.d/clouddev.conf

# ─── 9. Script khởi chạy ─────────────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev (Nginx)..."\n\
\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
# Watchdog MeiAI\n\
(\n\
while true; do\n\
    pgrep -f start-meiai.sh >/dev/null || nohup /MeiAI/start-meiai.sh > /dev/null 2>&1 &\n\
    sleep 60\n\
done\n\
) &\n\
\n\
ttyd -p 8081 -W -b /tmux /start.sh &\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
sleep 1\n\
echo "Nginx đang chạy..."\n\
# Nginx chạy foreground (-g "daemon off;")\n\
exec nginx -g "daemon off;"\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080
CMD ["/run.sh"]

# Reload nginx khi cần:
# nginx -s reload
