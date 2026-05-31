# syntax=docker/dockerfile:1.7

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production
ENV MEIAI_LITE_MODE=0
ENV MEIAI_ADMIN_KEY=admin
ENV PORT=5001
ENV PATH="/usr/local/go/bin:${PATH}"

# =========================
# 1. Cài package
# =========================
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    tar net-tools \
    openssh-client \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# =========================
# 2. Cài ttyd
# =========================
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# =========================
# 3. Clone MeiAI bằng SSH mount
# Không nhúng key vào image
# =========================
WORKDIR /

RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN --mount=type=ssh \
    git clone git@github.com:mrlht0/MeiAI.git /MeiAI

WORKDIR /MeiAI

# =========================
# 4. Cài Go
# =========================
RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz && \
    rm go1.24.3.linux-amd64.tar.gz

RUN go version

# =========================
# 5. Build MeiAI
# =========================
RUN npm install
RUN cp config.example.json config.json
RUN npm ci --prefix webui --no-audit
RUN npm run build --prefix webui
RUN go build -o meiai ./cmd/meiai
RUN chmod +x meiai

# =========================
# 6. Cài proxy server
# /      -> MeiAI
# /tmux  -> ttyd
# =========================
WORKDIR /proxy

RUN npm init -y && \
    npm install express http-proxy-middleware

RUN cat > /proxy/server.js << 'EOF'
const express = require("express");
const { createProxyMiddleware } = require("http-proxy-middleware");

const app = express();

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

app.use(
  "/",
  createProxyMiddleware({
    target: "http://127.0.0.1:5001",
    changeOrigin: true,
    ws: true
  })
);

app.listen(8080, () => {
  console.log("Proxy running at http://0.0.0.0:8080");
  console.log("/      -> MeiAI");
  console.log("/tmux  -> ttyd tmux");
});
EOF

# =========================
# 7. MeiAI restart script
# =========================
RUN cat > /MeiAI/start-meiai.sh << 'EOF'
#!/bin/bash

cd /MeiAI

LOG=/MeiAI/meiai.log
touch $LOG

while true
do
    echo "==========================" >> $LOG
    echo "[START] $(date)" >> $LOG

    ./meiai >> $LOG 2>&1
    CODE=$?

    echo "[EXIT $CODE] restarting in 5s..." >> $LOG
    sleep 5
done
EOF

RUN chmod +x /MeiAI/start-meiai.sh

# =========================
# 8. Tmux config
# =========================
RUN cat > /root/.tmux.conf << 'EOF'
set -g mouse on
set -g history-limit 10000
setw -g mode-keys vi
EOF

RUN cat > /start-tmux.sh << 'EOF'
#!/bin/bash

SESSION=main

tmux has-session -t $SESSION 2>/dev/null

if [ $? != 0 ]; then
  tmux new-session -d -s $SESSION -n MeiAI

  tmux send-keys -t $SESSION:0.0 "cd /MeiAI && tail -f meiai.log" C-m

  tmux split-window -h -t $SESSION:0.0
  tmux send-keys -t $SESSION:0.1 "htop" C-m

  tmux split-window -v -t $SESSION:0.1
  tmux send-keys -t $SESSION:0.2 "cd /MeiAI && bash" C-m

  tmux select-layout -t $SESSION tiled
fi

exec tmux attach -t $SESSION
EOF

RUN chmod +x /start-tmux.sh

# =========================
# 9. mem_guard
# =========================
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# =========================
# 10. Run all
# =========================
RUN cat > /run.sh << 'EOF'
#!/bin/bash

echo "Starting Cloud Dev MeiAI..."

nohup /usr/local/bin/mem_guard.sh > /tmp/mem_guard.log 2>&1 &

nohup /MeiAI/start-meiai.sh > /tmp/meiai-watchdog.log 2>&1 &

ttyd -i 127.0.0.1 -p 7681 -W /start-tmux.sh &

sleep 2

cd /proxy
exec node server.js
EOF

RUN chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
