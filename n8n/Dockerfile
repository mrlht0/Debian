FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV MEIAI_LITE_MODE=0
ENV MEIAI_ADMIN_KEY=admin
ENV PATH="/usr/local/go/bin:${PATH}"

RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates tar net-tools \
    openssh-client \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

WORKDIR /

RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /root/.ssh/id_ed25519 && \
    echo "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW" >> /root/.ssh/id_ed25519 && \
    echo "QyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+QAAAJCe7Zalnu2W" >> /root/.ssh/id_ed25519 && \
    echo "pQAAAAtzc2gtZWQyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+Q" >> /root/.ssh/id_ed25519 && \
    echo "AAAECu5uyGvQNoDwFalwDHbBQswmv31282a9dUGLoEnkLiIqVC9mYZaFP7edHr6L+/QjZF" >> /root/.ssh/id_ed25519 && \
    echo "AU6/Lg9Fyehi2v9QGTP5AAAAC3R5bGF1QE1yTEhUAQI=" >> /root/.ssh/id_ed25519 && \
    echo "-----END OPENSSH PRIVATE KEY-----" >> /root/.ssh/id_ed25519 && \
    chmod 600 /root/.ssh/id_ed25519

RUN git clone git@github.com:mrlht0/MeiAI.git /MeiAI

RUN rm -f /root/.ssh/id_ed25519

WORKDIR /MeiAI

RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz && \
    rm go1.24.3.linux-amd64.tar.gz

RUN go version

ENV NODE_ENV=development

RUN npm install

RUN cp config.example.json config.json

RUN cd webui && npm install --include=dev --no-audit

RUN cd webui && npm run build

RUN go build -o meiai ./cmd/meiai

RUN chmod +x /MeiAI/meiai

ENV NODE_ENV=production

RUN cat > /MeiAI/start-meiai.sh << 'EOF'
#!/bin/bash

cd /MeiAI

LOG=/MeiAI/meiai.log
touch "$LOG"

while true
do
    echo "==========================" >> "$LOG"
    echo "[START] $(date)" >> "$LOG"

    PORT=${MEIAI_PORT:-5001} ./meiai >> "$LOG" 2>&1
    CODE=$?

    echo "[EXIT $CODE] MeiAI stopped, restarting in 5s..." >> "$LOG"
    sleep 5
done
EOF

RUN chmod +x /MeiAI/start-meiai.sh

WORKDIR /proxy

RUN npm init -y && \
    npm install express http-proxy-middleware

RUN cat > /proxy/server.js << 'EOF'
const express = require("express");
const http = require("http");
const { createProxyMiddleware } = require("http-proxy-middleware");

const app = express();
const PUBLIC_PORT = process.env.PORT || 8080;

app.get("/healthz", (req, res) => {
  res.status(200).send("ok");
});

app.get(/^\/tmux$/, (req, res) => {
  res.redirect(301, "/tmux/");
});

const tmuxProxy = createProxyMiddleware({
  target: "http://127.0.0.1:7681",
  changeOrigin: true,
  ws: true,
  xfwd: true
});

const meiaiProxy = createProxyMiddleware({
  target: "http://127.0.0.1:5001",
  changeOrigin: true,
  ws: true,
  xfwd: true
});

app.use((req, res, next) => {
  if (req.url.startsWith("/tmux")) {
    return tmuxProxy(req, res, next);
  }
  return meiaiProxy(req, res, next);
});

const server = http.createServer(app);

server.on("upgrade", (req, socket, head) => {
  if (req.url.startsWith("/tmux")) {
    tmuxProxy.upgrade(req, socket, head);
  } else {
    meiaiProxy.upgrade(req, socket, head);
  }
});

server.listen(PUBLIC_PORT, "0.0.0.0", () => {
  console.log("==================================");
  console.log(`Proxy running on ${PUBLIC_PORT}`);
  console.log("/       -> MeiAI 5001");
  console.log("/tmux/  -> ttyd 7681");
  console.log("==================================");
});
EOF

RUN cat > /start-tmux.sh << 'EOF'
#!/bin/bash

SESSION=main

tmux has-session -t "$SESSION" 2>/dev/null

if [ $? != 0 ]; then
    tmux new-session -d -s "$SESSION" -n cloud

    tmux send-keys -t "$SESSION":0.0 "cd /MeiAI && tail -f meiai.log" C-m

    tmux split-window -h -t "$SESSION":0.0
    tmux send-keys -t "$SESSION":0.1 "htop" C-m

    tmux split-window -v -t "$SESSION":0.1
    tmux send-keys -t "$SESSION":0.2 "cd /MeiAI && bash" C-m

    tmux select-layout -t "$SESSION" tiled
fi

exec tmux attach -t "$SESSION"
EOF

RUN chmod +x /start-tmux.sh

RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

RUN cat > /run.sh << 'EOF'
#!/bin/bash

echo "Starting MeiAI Cloud Dev..."

if [ -f /usr/local/bin/mem_guard.sh ]; then
    nohup /usr/local/bin/mem_guard.sh > /tmp/mem_guard.log 2>&1 &
fi

MEIAI_PORT=5001 nohup /MeiAI/start-meiai.sh > /tmp/meiai-watchdog.log 2>&1 &

SESSION=main

tmux has-session -t "$SESSION" 2>/dev/null
if [ $? != 0 ]; then
    tmux new-session -d -s "$SESSION" -n cloud

    tmux send-keys -t "$SESSION":0.0 "cd /MeiAI && tail -f meiai.log" C-m

    tmux split-window -h -t "$SESSION":0.0
    tmux send-keys -t "$SESSION":0.1 "htop" C-m

    tmux split-window -v -t "$SESSION":0.1
    tmux send-keys -t "$SESSION":0.2 "cd /MeiAI && bash" C-m

    tmux select-layout -t "$SESSION" tiled
fi

ttyd -i 127.0.0.1 -p 7681 -W -b /tmux tmux attach-session -t "$SESSION" &

sleep 2

cd /proxy
exec node server.js
EOF

RUN chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
