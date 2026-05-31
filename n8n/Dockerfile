```dockerfile
# syntax=docker/dockerfile:1.7

FROM node:22-bookworm

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# Packages
# =========================================================
RUN apt-get update && apt-get install -y \
    git \
    openssh-client \
    tmux \
    ttyd \
    htop \
    curl \
    wget \
    procps \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# Clone MeiAI bằng SSH mount
# Không lưu key vào image
# =========================================================
WORKDIR /opt

RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN --mount=type=ssh \
    git clone git@github.com:YOUR_USER/MeiAI.git /opt/MeiAI

# =========================================================
# Install MeiAI
# =========================================================
WORKDIR /opt/MeiAI

RUN npm install

# =========================================================
# Install proxy middleware
# =========================================================
RUN npm install http-proxy-middleware

# =========================================================
# mem_guard
# =========================================================
RUN cat > /usr/local/bin/mem_guard.sh << 'EOF'
#!/bin/bash

LIMIT_MB=3500

while true; do
    USED=$(free -m | awk '/Mem:/ {print $3}')

    if [ "$USED" -gt "$LIMIT_MB" ]; then
        echo "[mem_guard] RAM vượt ngưỡng: ${USED}MB"

        pkill -f "node" || true

        sleep 3

        cd /opt/MeiAI
        tmux send-keys -t main:0.0 "npm start" C-m
    fi

    sleep 10
done
EOF

RUN chmod +x /usr/local/bin/mem_guard.sh

# =========================================================
# startup
# =========================================================
RUN cat > /usr/local/bin/start.sh << 'EOF'
#!/bin/bash

set -e

# ==========================================
# TMUX SESSION
# ==========================================
tmux new-session -d -s main

# Pane 1 - MeiAI
tmux send-keys -t main:0.0 "cd /opt/MeiAI && npm start" C-m

# Pane 2 - RAM monitor
tmux split-window -h -t main
tmux send-keys -t main:0.1 "htop" C-m

# Pane 3 - shell
tmux split-window -v -t main:0.1
tmux send-keys -t main:0.2 "bash" C-m

# Layout đẹp hơn
tmux select-layout -t main tiled

# ==========================================
# mem_guard
# ==========================================
nohup /usr/local/bin/mem_guard.sh >/tmp/mem_guard.log 2>&1 &

# ==========================================
# ttyd internal only
# ==========================================
ttyd -i 127.0.0.1 -p 7681 -W tmux attach -t main &

# ==========================================
# Start MeiAI proxy server
# ==========================================
cd /opt/MeiAI
node proxy.js
EOF

RUN chmod +x /usr/local/bin/start.sh

# =========================================================
# Proxy /tmux -> ttyd
# =========================================================
RUN cat > /opt/MeiAI/proxy.js << 'EOF'
import express from "express";
import { createProxyMiddleware } from "http-proxy-middleware";
import path from "path";

const app = express();

const PORT = 8080;

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

# =====================================================
# MeiAI frontend/backend
# chỉnh theo project thật của bạn
# =====================================================
app.use("/", express.static(path.join(process.cwd(), "public")));

app.listen(PORT, () => {
    console.log("MeiAI running at :8080");
});
EOF

# =========================================================
# Only expose 8080
# =========================================================
EXPOSE 8080

CMD ["/usr/local/bin/start.sh"]
```
