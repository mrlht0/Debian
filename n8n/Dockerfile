# ==============================================================
# Cloud Dev: ttyd + tmux + NODE.JS http-proxy (Thay thế Caddy)
# ==============================================================
# ⚠️  Dùng Node.js http-proxy-middleware (đã có sẵn Node trong image)
#     Ưu điểm: không cần cài thêm gì, logic tùy biến hoàn toàn bằng JS
#     Phù hợp khi đã có Node.js và muốn proxy động (thêm/xóa route lúc runtime)
#     Nhược điểm: hiệu năng thấp hơn Nginx/HAProxy với tải cao
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── 1. Cài đặt các gói cơ bản ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
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

# ─── 6. Tạo Node.js proxy server ─────────────────────────────
# Cài http-proxy (nhẹ, hỗ trợ WebSocket tốt)
RUN mkdir -p /proxy && cd /proxy && \
    npm init -y && \
    npm install http-proxy

# Viết proxy.js hoàn chỉnh
RUN cat > /proxy/proxy.js << 'PROXYEOF'
/**
 * Node.js Reverse Proxy
 * Thay thế Caddy - route theo path prefix
 * Hỗ trợ HTTP + WebSocket upgrade
 */
const http = require('http');
const httpProxy = require('http-proxy');

const proxy = httpProxy.createProxyServer({
  ws: true,          // Bật WebSocket
  xfwd: true,        // Thêm X-Forwarded-* headers
});

// Bảng route: path prefix → target port
//
// ⚠️  QUAN TRỌNG - ttyd và strip prefix:
//     ttyd dùng -b /tmux để inject đúng prefix vào HTML (asset links, token URL, ws URL)
//     Nên proxy KHÔNG được strip prefix → ttyd nhận /tmux/ws và tự xử lý đúng
//     Nếu strip → ttyd nhận /ws, HTML vẫn link tới /tmux/ws → browser gọi /tmux/ws
//     → proxy forward tới ttyd thành /ws → OK... nhưng token endpoint lại link sai
//     Kết luận: strip: false cho mọi ttyd route
//
// strip: false → giữ nguyên path (ttyd tự handle nhờ -b flag)
const routes = [
  { prefix: '/terminal',  target: 'http://127.0.0.1:8082', strip: false },
  { prefix: '/ttyd',      target: 'http://127.0.0.1:7681', strip: false },
  { prefix: '/tmux',      target: 'http://127.0.0.1:8081', strip: false },
  { prefix: '/openclaw',  target: 'http://127.0.0.1:18789',strip: false },
  { prefix: '/meiai',     target: 'http://127.0.0.1:5001', strip: false },
  { prefix: '/10000',     target: 'http://127.0.0.1:10000',strip: false },
  { prefix: '/8083',      target: 'http://127.0.0.1:8083', strip: false },
  { prefix: '/8084',      target: 'http://127.0.0.1:8084', strip: false },
  { prefix: '/8085',      target: 'http://127.0.0.1:8085', strip: false },
  { prefix: '/8086',      target: 'http://127.0.0.1:8086', strip: false },
  { prefix: '/8087',      target: 'http://127.0.0.1:8087', strip: false },
  { prefix: '/8088',      target: 'http://127.0.0.1:8088', strip: false },
  { prefix: '/8089',      target: 'http://127.0.0.1:8089', strip: false },
  { prefix: '/10001',     target: 'http://127.0.0.1:10001',strip: false },
  { prefix: '/10002',     target: 'http://127.0.0.1:10002',strip: false },
  { prefix: '/10003',     target: 'http://127.0.0.1:10003',strip: false },
  // Catch-all: mặc định forward tới 10000
  { prefix: '/',          target: 'http://127.0.0.1:10000',strip: false },
];

function findRoute(url) {
  for (const route of routes) {
    if (url.startsWith(route.prefix)) return route;
  }
  return { target: 'http://127.0.0.1:10000', strip: false, prefix: '/' };
}

// Rewrite URL: strip prefix nếu cần
// /tmux/ws?arg=1  →  /ws?arg=1
// /tmux           →  /
function rewriteUrl(url, route) {
  if (!route.strip) return url;
  const stripped = url.slice(route.prefix.length) || '/';
  // Đảm bảo luôn bắt đầu bằng /
  return stripped.startsWith('/') ? stripped : '/' + stripped;
}

proxy.on('error', (err, req, res) => {
  console.error(`[PROXY ERROR] ${req.url}: ${err.message}`);
  if (res && !res.headersSent) {
    res.writeHead(502, { 'Content-Type': 'text/plain' });
    res.end(`Proxy error: ${err.message}`);
  }
});

// HTTP server
const server = http.createServer((req, res) => {
  const route = findRoute(req.url || '/');
  const originalUrl = req.url;
  req.url = rewriteUrl(req.url, route);
  console.log(`[HTTP] ${req.method} ${originalUrl} → ${route.target}${req.url}`);
  proxy.web(req, res, { target: route.target });
});

// WebSocket upgrade — quan trọng: cũng phải rewrite URL
server.on('upgrade', (req, socket, head) => {
  const route = findRoute(req.url || '/');
  const originalUrl = req.url;
  req.url = rewriteUrl(req.url, route);
  console.log(`[WS]   UPGRADE ${originalUrl} → ${route.target}${req.url}`);
  proxy.ws(req, socket, head, { target: route.target });
});

server.listen(8080, '0.0.0.0', () => {
  console.log('Node.js Proxy đang chạy tại http://0.0.0.0:8080');
  console.log('Routes:');
  routes.forEach(r => console.log(`  ${r.prefix.padEnd(12)} → ${r.target}`));
});

// Graceful shutdown
process.on('SIGTERM', () => { server.close(); process.exit(0); });
process.on('SIGINT',  () => { server.close(); process.exit(0); });
PROXYEOF

# ─── 7. Script khởi chạy ─────────────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev (Node.js Proxy)..."\n\
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
# ttyd PHẢI dùng -b để inject đúng prefix vào HTML\n\
# Proxy giữ nguyên path, ttyd tự xử lý /tmux/ws, /tmux/token, ...\n\
ttyd -p 8081 -W -b /tmux /start.sh &\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
sleep 1\n\
echo "Node.js Proxy đang chạy..."\n\
exec node /proxy/proxy.js\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080
CMD ["/run.sh"]

# Thêm route động lúc runtime: sửa /proxy/proxy.js rồi restart node
# pm2 start /proxy/proxy.js --watch   # nếu muốn auto-reload khi sửa file
