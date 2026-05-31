FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production
ENV MEIAI_LITE_MODE=0
ENV MEIAI_ADMIN_KEY=admin
ENV PORT=5001
ENV PATH="/usr/local/go/bin:${PATH}"

# ==============================================================
# 1. Cài package cơ bản
# ==============================================================
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    tar net-tools \
    openssh-client \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ==============================================================
# 2. Cài ttyd
# ==============================================================
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ==============================================================
# 3. Tạo SSH key để clone MeiAI
# Lưu ý: key này vẫn có thể nằm trong image layer
# ==============================================================
WORKDIR /

RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /root/.ssh/id_ed25519 && \
    echo "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW" >> /root/.ssh/id_ed25519 && \
    echo "QyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+QAAAJCe7Zalnu2W" >> /root/.ssh/id_ed25519 && \
    echo "pQAAAAtzc2gtZWQyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+Q" >> /root/.ssh/id_ed25519 && \
    echo "AAAECu5uyGvQNoDwFalwDHbBQswmv31282a9dUGLoEnkLiIqVC9mYZaFP7edHr6L+/QjZF" >> /root/.ssh/id_ed25519 && \
    echo "AU6/Lg9Fyehi2v9QGTP5AAAAC3R5bGF1QE1yTEhUAQI=" >> /root/.ssh/id_ed25519 && \
    echo "-----END OPENSSH PRIVATE KEY-----" >> /root/.ssh/id_ed25519

RUN chmod 600 /root/.ssh/id_ed25519

# ==============================================================
# 4. Clone MeiAI
# ==============================================================
RUN git clone git@github.com:mrlht0/MeiAI.git /MeiAI

# Xóa key khỏi filesystem cuối cùng
RUN rm -f /root/.ssh/id_ed25519

# ==============================================================
# 5. Cài Go
# ==============================================================
WORKDIR /MeiAI

RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz && \
    rm go1.24.3.linux-amd64.tar.gz

RUN go version

# ==============================================================
# 6. Build MeiAI
# ==============================================================
RUN npm install

RUN cp config.example.json config.json

RUN npm ci --prefix webui --no-audit

RUN npm run build --prefix webui

RUN go build -o meiai ./cmd/meiai

RUN chmod +x /MeiAI/meiai

# ==============================================================
# 7. Tạo script chạy MeiAI + ghi log
# ==============================================================
RUN cat > /MeiAI/start-meiai.sh << 'EOF'
#!/bin/bash

cd /MeiAI

LOG=/MeiAI/meiai.log
touch "$LOG"

while true
do
    echo "==========================" >> "$LOG"
    echo "[START] $(date)" >> "$LOG"

    ./meiai >> "$LOG" 2>&1
    CODE=$?

    echo "[EXIT $CODE] MeiAI stopped, restarting in 5s..." >> "$LOG"
    sleep 5
done
EOF

RUN chmod +x /MeiAI/start-meiai.sh

# ==============================================================
# 8. Cài proxy NodeJS
# /      -> MeiAI port 5001
# /tmux  -> ttyd port 7681
# ==============================================================
WORKDIR /proxy

RUN npm init -y && \
    npm install express http-proxy-middleware

RUN cat > /proxy/server.js << 'EOF'
const express = require("express");
const { createProxyMiddleware } = require("http-proxy-middleware");

const app = express();

const PORT = 8080;

/**
 * /tmux -> ttyd
 */
app.use(
  "/tmux",
  createProxyMiddleware({
    target: "http://127.0.0.1:7681",
    changeOrigin: true,
    ws: true,
    pathRewrite: {
      "^/tmux": ""
    }
  })
);

/**
 * / -> MeiAI
 */
app.use(
  "/",
  createProxyMiddleware({
    target: "http://127.0.0.1:5001",
    changeOrigin: true,
    ws: true
  })
);

app.listen(PORT, "0.0.0.0", () => {
  console.log("==================================");
  console.log("Cloud Dev MeiAI Proxy");
  console.log("http://0.0.0.0:8080/      -> MeiAI");
  console.log("http://0.0.0.0:8080/tmux  -> ttyd tmux");
  console.log("==================================");
});
EOF

# ==============================================================
# 9. Cấu hình tmux
# ==============================================================
RUN cat > /root/.tmux.conf << 'EOF'
set -g mouse on
set -g history-limit 10000
setw -g mode-keys vi
unbind -n MouseDown3Pane
EOF

RUN cat > /start-tmux.sh << 'EOF'
#!/bin/bash

SESSION=main

tmux has-session -t "$SESSION" 2>/dev/null

if [ $? != 0 ]; then
    tmux new-session -d -s "$SESSION" -n cloud

    # Pane 1: log MeiAI
    tmux send-keys -t "$SESSION":0.0 "cd /MeiAI && tail -f meiai.log" C-m

    # Pane 2: RAM monitor
    tmux split-window -h -t "$SESSION":0.0
    tmux send-keys -t "$SESSION":0.1 "htop" C-m

    # Pane 3: shell tay
    tmux split-window -v -t "$SESSION":0.1
    tmux send-keys -t "$SESSION":0.2 "cd /MeiAI && bash" C-m

    tmux select-layout -t "$SESSION" tiled
fi

exec tmux attach -t "$SESSION"
EOF

RUN chmod +x /start-tmux.sh

# ==============================================================
# 10. Cài mem_guard
# ==============================================================
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# ==============================================================
# 11. Script chạy toàn bộ
# ==============================================================
RUN cat > /run.sh << 'EOF'
#!/bin/bash

echo "Starting Cloud Dev MeiAI..."

# Chạy mem_guard nền
if [ -f /usr/local/bin/mem_guard.sh ]; then
    nohup /usr/local/bin/mem_guard.sh > /tmp/mem_guard.log 2>&1 &
fi

# Chạy MeiAI nền
nohup /MeiAI/start-meiai.sh > /tmp/meiai-watchdog.log 2>&1 &

# Chạy ttyd nội bộ, chỉ bind 127.0.0.1
ttyd -i 127.0.0.1 -p 7681 -W /start-tmux.sh &

sleep 2

# Chạy proxy chính ở port 8080
cd /proxy
exec node server.js
EOF

RUN chmod +x /run.sh

# ==============================================================
# 12. Chỉ expose 8080
# ==============================================================
EXPOSE 8080

CMD ["/run.sh"]
