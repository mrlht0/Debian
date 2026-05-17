
# ==============================================================
# Cloud Dev: ttyd + tmux + Caddy (Full Fixed Multi-Route)
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── 1. Cài đặt các gói cơ bản ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    caddy \
    tar net-tools \
    # python3 python3-pip \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── 2. Cài đặt ttyd (bản mới nhất) ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 3. Cấu hình thư mục làm việc ────────────────────────────
WORKDIR /

# 1. Cài đặt git và openssh-client (nếu chưa có)
RUN apt-get update && apt-get install -y git openssh-client

# 2. Tạo thư mục .ssh và thêm github.com vào known_hosts
RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

# 3. Ghi trực tiếp khóa bí mật vào file id_ed25519
RUN echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /root/.ssh/id_ed25519 && \
    echo "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW" >> /root/.ssh/id_ed25519 && \
    echo "QyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+QAAAJCe7Zalnu2W" >> /root/.ssh/id_ed25519 && \
    echo "pQAAAAtzc2gtZWQyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+Q" >> /root/.ssh/id_ed25519 && \
    echo "AAAECu5uyGvQNoDwFalwDHbBQswmv31282a9dUGLoEnkLiIqVC9mYZaFP7edHr6L+/QjZF" >> /root/.ssh/id_ed25519 && \
    echo "AU6/Lg9Fyehi2v9QGTP5AAAAC3R5bGF1QE1yTEhUAQI=" >> /root/.ssh/id_ed25519 && \
    echo "-----END OPENSSH PRIVATE KEY-----" >> /root/.ssh/id_ed25519 && \
    chmod 600 /root/.ssh/id_ed25519 && \
# 4. Thực hiện clone repo bằng địa chỉ SSH clone toàn bộ
    git clone git@github.com:mrlht0/MeiAI.git && \
# 4. Thực hiện clone repo bằng địa chỉ SSH (chỉ clone 1 commit sâu)
    # git clone --depth 1 git@github.com:mrlht0/MeiAI.git && \
    # cd MeiAI && \
    # git fetch --depth 1 origin a35e70c && \
    # git checkout a35e70c && \
# 5. Xóa khóa bí mật ngay lập tức để bảo mật layer
    rm /root/.ssh/id_ed25519

WORKDIR /MeiAI

# Cài go
RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz \
    && echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
ENV PATH="/usr/local/go/bin:${PATH}"
RUN go version

# # 3. Cài đặt dependencies và build
RUN npm install
RUN cp config.example.json config.json
RUN npm ci --prefix webui --no-audit
RUN npm run build --prefix webui
# RUN find . -type f -name "*.go" | head -50
RUN go build -o meiai ./cmd/meiai
RUN chmod +x meiai

# export PORT=5001
# ./meiai

ENV NODE_ENV=production \
    MEIAI_LITE_MODE=0 \
    MEIAI_ADMIN_KEY=admin \
    PORT=5001
# ./meiai

# Cấu hình chạy tự động & ghi 2000 dòng log mới nhất
RUN printf '#!/bin/bash\n\
\n\
cd /MeiAI\n\
\n\
LOG=/MeiAI/meiai.log\n\
touch $LOG\n\
\n\
while true\n\
do\n\
    echo "==========================" >> $LOG\n\
    echo "[START] $(date)" >> $LOG\n\
\n\
    ./meiai >> $LOG 2>&1 &\n\
    PID=$!\n\
\n\
    while kill -0 $PID 2>/dev/null\n\
    do\n\
        tail -n 2000 $LOG > ${LOG}.tmp && mv ${LOG}.tmp $LOG\n\
        sleep 30\n\
    done\n\
\n\
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

# ─── 5. Script tự động khởi tạo Tmux session ───────────────────────────
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

# ─── 6. Thêm mem_guard (giới hạn RAM + log 5 dòng) ─────────────────────────────
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# ─── 7. Cấu hình Caddyfile (Xử lý đa đường dẫn) ─────────────────
RUN mkdir -p /etc/caddy && \
printf '(proxy_port) {\n\
    handle /{args.0}* {\n\
        reverse_proxy localhost:{args.0}\n\
    }\n\
}\n\
\n\
:8080 {\n\
    handle /terminal* {\n\
        uri strip_prefix /terminal\n\
        reverse_proxy localhost:8082\n\
    }\n\
# \n\
#     handle /8083* {\n\
#         reverse_proxy localhost:8083\n\
#     }\n\
# \n\
#     handle /8084* {\n\
#         reverse_proxy localhost:8084\n\
#     }\n\
# \n\
#     handle /8085* {\n\
#         reverse_proxy localhost:8085\n\
#     }\n\
# \n\
#     handle /8086* {\n\
#         reverse_proxy localhost:8086\n\
#     }\n\
# \n\
#     handle /8087* {\n\
#         reverse_proxy localhost:8087\n\
#     }\n\
# \n\
#     handle /8088* {\n\
#         reverse_proxy localhost:8088\n\
#     }\n\
# \n\
#     handle /8089* {\n\
#         reverse_proxy localhost:8089\n\
#     }\n\
\n\
    handle /ttyd* {\n\
        reverse_proxy localhost:7681\n\
    }\n\
\n\
    handle /tmux* {\n\
        uri strip_prefix /tmux\n\
        reverse_proxy localhost:8081\n\
    }\n\
\n\
    handle /openclaw* {\n\
        reverse_proxy 127.0.0.1:18789\n\
    }\n\
\n\
    handle /meiai* {\n\
        reverse_proxy 127.0.0.1:5001\n\
    }\n\
\n\
    handle /10000* {\n\
#        uri strip_prefix /10000\n\
        reverse_proxy 127.0.0.1:10000 \n\
    }\n\
\n\
    # Sử dụng Snippet cho các port hàng loạt\n\
    import proxy_port 8083\n\
    import proxy_port 8084\n\
    import proxy_port 8085\n\
    import proxy_port 8086\n\
    import proxy_port 8087\n\
    import proxy_port 8088\n\
    import proxy_port 8089\n\
    # import proxy_port 10000\n\
    import proxy_port 10001\n\
    import proxy_port 10002\n\
    import proxy_port 10003\n\
\n\
    # Mặc định 1 trong ba từ trái qua phải\n\
    handle {\n\
        uri strip_prefix /10000\n\
        reverse_proxy 127.0.0.1:10000 {\n\
            lb_policy first\n\
        }\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# # ─── 8. Script khởi chạy toàn bộ dịch vụ ─────────────────────────────
# # Quan trọng: Thêm tham số -W ghi, -b cho ttyd để khớp với đường dẫn của Caddy
# RUN printf '#!/bin/bash\n\
# echo "Đang khởi động dịch vụ Cloud Dev..."\n\
# \n\
# # chạy mem_guard nền\n\
# nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
# \n\

# # Chạy dịch vụ chính, tạm tắt nếu muốn dùng thêm teminal
# # nohup /MeiAI/start-meiai.sh > /dev/null 2>&1 &\n\
# # Rồi xem log riêng: tail -f /MeiAI/meiai.log
# # kill khi cần: pkill -f start-meiai.sh
# # pkill -f ./meiai

# # ttyd chính (Cổng 8081)\n\
# ttyd -p 8081 -W -b /tmux /start.sh &\n\
# \n\
# # ttyd phụ (Cổng 8082)\n\
# ttyd -p 8082 -W -b /terminal bash &\n\
# \n\
# # \n\
# # ⏳ đợi service lên
# sleep 1\n\

# echo "Caddy đang chạy..."\n\
# exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
# echo "⏳ run 9router" \n\
# ' > /run.sh && chmod +x /run.sh

# EXPOSE 8080

# CMD ["/run.sh"]

# Chạy lại (reload) caddy
# caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
# watch -n 1 cat /opt/mem.log


# ─── 8. Script khởi chạy toàn bộ dịch vụ ─────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Starting Cloud Dev Services..."\n\
\n\
# Chạy mem_guard nền\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
# Chạy ttyd services\n\
ttyd -p 8081 -W /start.sh &\n\
ttyd -p 8082 -W bash &\n\
\n\
# Khởi động Caddy trong nền\n\
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &\n\
CADDY_PID=$!\n\
\n\
# Hàm kiểm tra Caddy đã sẵn sàng chưa\n\
wait_for_caddy() {\n\
    echo "Waiting for Caddy to be ready..."\n\
    local max_attempts=30\n\
    local attempt=0\n\
    \n\
    while [ $attempt -lt $max_attempts ]; do\n\
        if curl -s -o /dev/null -w "%%{http_code}" http://localhost:8080/health 2>/dev/null | grep -q "200\|404\|502"; then\n\
            # Chỉ cần Caddy respond là đủ (kể cả 404 cũng được)\n\
            echo "Caddy is ready! (attempt $((attempt+1))/$max_attempts)"\n\
            return 0\n\
        fi\n\
        \n\
        # Kiểm tra process Caddy vẫn chạy\n\
        if ! kill -0 $CADDY_PID 2>/dev/null; then\n\
            echo "ERROR: Caddy process died!"\n\
            return 1\n\
        fi\n\
        \n\
        attempt=$((attempt+1))\n\
        echo "Waiting for Caddy... ($attempt/$max_attempts)"\n\
        sleep 1\n\
    done\n\
    \n\
    echo "ERROR: Caddy did not become ready in time"\n\
    return 1\n\
}\n\
\n\
# Đợi Caddy ready\n\
if wait_for_caddy; then\n\
    echo "✅ Caddy is running successfully"\n\
    \n\
    # Chạy MeiAI sau khi Caddy đã sẵn sàng\n\
    if [ -f /MeiAI/start-meiai.sh ]; then\n\
        echo "Starting MeiAI..."\n\
        nohup /MeiAI/start-meiai.sh > /MeiAI/meiai.log 2>&1 &\n\
        echo "✅ MeiAI started. Log: /MeiAI/meiai.log"\n\
    else\n\
        echo "⚠️  WARNING: /MeiAI/start-meiai.sh not found"\n\
    fi\n\
else\n\
    echo "❌ Caddy failed to start. MeiAI will not be started."\n\
fi\n\
\n\
# Tạo script auto-run trong terminal\n\
cat > /root/.bashrc << "EOF"\n\
if [ ! -f /tmp/terminal_initialized ]; then\n\
    echo "========================================="\n\
    echo "🚀 Chào mừng! Đây là terminal của bạn"\n\
    echo "========================================="\n\
    echo ""\n\
    echo "📌 Các lệnh có sẵn:"\n\
    echo "   - mei-start  : Khởi động MeiAI service"\n\
    echo "   - mei-status : Kiểm tra trạng thái MeiAI"\n\
    echo "   - mei-logs   : Xem log của MeiAI"\n\
    echo "   - mei-stop   : Dừng MeiAI service"\n\
    echo ""\n\
    touch /tmp/terminal_initialized\n\
fi\n\
\n\
# Aliases tiện lợi\nalias mei-start="nohup /MeiAI/start-meiai.sh > /MeiAI/meiai.log 2>&1 &"\n\
alias mei-status="ps aux | grep -E "start-meiai|meiai" | grep -v grep"\n\
alias mei-logs="tail -f /MeiAI/meiai.log"\n\
alias mei-stop="pkill -f start-meiai.sh"\n\
\n\
export PS1="\\[\\033[38;5;2m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[38;5;6m\\]\\w\\[\\033[00m\\]\\$ "\n\
EOF\n\
\n\
cp /root/.bashrc /etc/skel/.bashrc 2>/dev/null || true\n\
\n\
# Giữ Caddy chạy foreground\n\
wait $CADDY_PID\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
