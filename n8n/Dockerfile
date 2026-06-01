# ==============================================================
# Cloud Dev: ttyd + tmux + HAPROXY (Thay thế Caddy)
# ==============================================================
# ⚠️  HAProxy route theo PATH thì cần ACL + use_backend
#     Ưu điểm: cực nhanh, health-check tích hợp, stats dashboard
#     Nhược điểm: WebSocket cần cấu hình thêm "option http-server-close"
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── 1. Cài đặt các gói cơ bản ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    haproxy \
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

# ─── 5. Cấu hình Bash & Tmux ─────────────────────────────────
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

RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# ─── 6. Cấu hình HAProxy ─────────────────────────────────────
# HAProxy dùng ACL (Access Control List) để match path
# Khác Caddy/Nginx: cần khai báo frontend + backend tách biệt
# Stats dashboard tại /haproxy-stats (port 8080)
RUN printf 'global\n\
    log stdout format raw local0\n\
    maxconn 4096\n\
    daemon\n\
\n\
defaults\n\
    log     global\n\
    mode    http\n\
    option  httplog\n\
    option  forwardfor\n\
    # Bắt buộc để WebSocket hoạt động đúng\n\
    option  http-server-close\n\
    timeout connect 5s\n\
    timeout client  86400s\n\
    timeout tunnel  86400s\n\
    timeout server  86400s\n\
\n\
# ── Stats dashboard tích hợp của HAProxy ──\n\
listen stats\n\
    bind *:8090\n\
    stats enable\n\
    stats uri /\n\
    stats refresh 10s\n\
    stats admin if TRUE\n\
\n\
frontend http_front\n\
    bind *:8080\n\
\n\
    # ── Khai báo ACL match theo path prefix ──\n\
    acl path_terminal  path_beg /terminal\n\
    acl path_ttyd      path_beg /ttyd\n\
    acl path_tmux      path_beg /tmux\n\
    acl path_openclaw  path_beg /openclaw\n\
    acl path_meiai     path_beg /meiai\n\
    acl path_10000     path_beg /10000\n\
    acl path_8083      path_beg /8083\n\
    acl path_8084      path_beg /8084\n\
    acl path_8085      path_beg /8085\n\
    acl path_8086      path_beg /8086\n\
    acl path_8087      path_beg /8087\n\
    acl path_8088      path_beg /8088\n\
    acl path_8089      path_beg /8089\n\
    acl path_10001     path_beg /10001\n\
    acl path_10002     path_beg /10002\n\
    acl path_10003     path_beg /10003\n\
\n\
    # ── Upgrade WebSocket ──\n\
    acl is_websocket hdr(Upgrade) -i websocket\n\
\n\
    # ── Route đến backend tương ứng ──\n\
    # ── Strip prefix cho các service dùng ttyd (chúng expect path = /)\n\
    # HAProxy dùng regex: ^/PREFIX(/.*)? → \\1 (hoặc / nếu không có phần sau)\n\
    http-request replace-path ^/terminal(/.*)?$  \\1         if path_terminal\n\
    http-request replace-path ^/ttyd(/.*)?$      \\1         if path_ttyd\n\
    http-request replace-path ^/tmux(/.*)?$      \\1         if path_tmux\n\
    http-request replace-path ^/openclaw(/.*)?$  \\1         if path_openclaw\n\
    # meiai và các port số: giữ nguyên path (upstream tự xử lý)\n\
\n\
    # ── Route đến backend tương ứng ──\n\
    use_backend backend_terminal  if path_terminal\n\
    use_backend backend_ttyd      if path_ttyd\n\
    use_backend backend_tmux      if path_tmux\n\
    use_backend backend_openclaw  if path_openclaw\n\
    use_backend backend_meiai     if path_meiai\n\
    use_backend backend_10000     if path_10000\n\
    use_backend backend_8083      if path_8083\n\
    use_backend backend_8084      if path_8084\n\
    use_backend backend_8085      if path_8085\n\
    use_backend backend_8086      if path_8086\n\
    use_backend backend_8087      if path_8087\n\
    use_backend backend_8088      if path_8088\n\
    use_backend backend_8089      if path_8089\n\
    use_backend backend_10001     if path_10001\n\
    use_backend backend_10002     if path_10002\n\
    use_backend backend_10003     if path_10003\n\
    # Mặc định: forward tới 10000\n\
    default_backend backend_10000\n\
\n\
# ── Backend definitions ──\n\
backend backend_terminal\n\
    server s1 127.0.0.1:8082 check\n\
\n\
backend backend_ttyd\n\
    server s1 127.0.0.1:7681 check\n\
\n\
backend backend_tmux\n\
    server s1 127.0.0.1:8081 check\n\
\n\
backend backend_openclaw\n\
    server s1 127.0.0.1:18789 check\n\
\n\
backend backend_meiai\n\
    server s1 127.0.0.1:5001 check\n\
\n\
backend backend_10000\n\
    server s1 127.0.0.1:10000 check\n\
\n\
backend backend_8083\n\
    server s1 127.0.0.1:8083 check\n\
\n\
backend backend_8084\n\
    server s1 127.0.0.1:8084 check\n\
\n\
backend backend_8085\n\
    server s1 127.0.0.1:8085 check\n\
\n\
backend backend_8086\n\
    server s1 127.0.0.1:8086 check\n\
\n\
backend backend_8087\n\
    server s1 127.0.0.1:8087 check\n\
\n\
backend backend_8088\n\
    server s1 127.0.0.1:8088 check\n\
\n\
backend backend_8089\n\
    server s1 127.0.0.1:8089 check\n\
\n\
backend backend_10001\n\
    server s1 127.0.0.1:10001 check\n\
\n\
backend backend_10002\n\
    server s1 127.0.0.1:10002 check\n\
\n\
backend backend_10003\n\
    server s1 127.0.0.1:10003 check\n\
' > /etc/haproxy/haproxy.cfg

# ─── 7. Script khởi chạy ─────────────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev (HAProxy)..."\n\
\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
(\n\
while true; do\n\
    pgrep -f start-meiai.sh >/dev/null || nohup /MeiAI/start-meiai.sh > /dev/null 2>&1 &\n\
    sleep 60\n\
done\n\
) &\n\
\n\
# Không cần -b vì HAProxy đã strip prefix\n\
ttyd -p 8081 -W /start.sh &\n\
ttyd -p 8082 -W bash &\n\
\n\
sleep 1\n\
echo "HAProxy đang chạy... Stats dashboard: http://host:8090"\n\
# HAProxy cần file PID và chạy foreground với -db\n\
exec haproxy -f /etc/haproxy/haproxy.cfg -db\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080 8090
CMD ["/run.sh"]

# Reload HAProxy không restart:
# haproxy -f /etc/haproxy/haproxy.cfg -sf $(cat /var/run/haproxy.pid)
# Xem stats: curl http://localhost:8090/
