# syntax=docker/dockerfile:1.7

FROM node:26-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    PORT=5001 \
    MEIAI_LITE_MODE=0 \
    MEIAI_ADMIN_KEY=admin

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget git openssh-client procps tmux ca-certificates \
    build-essential python3 make g++ tar net-tools \
    && rm -rf /var/lib/apt/lists/*

RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

WORKDIR /app

RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts && \
    echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /root/.ssh/id_ed25519 && \
    echo "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW" >> /root/.ssh/id_ed25519 && \
    echo "QyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+QAAAJCe7Zalnu2W" >> /root/.ssh/id_ed25519 && \
    echo "pQAAAAtzc2gtZWQyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+Q" >> /root/.ssh/id_ed25519 && \
    echo "AAAECu5uyGvQNoDwFalwDHbBQswmv31282a9dUGLoEnkLiIqVC9mYZaFP7edHr6L+/QjZF" >> /root/.ssh/id_ed25519 && \
    echo "AU6/Lg9Fyehi2v9QGTP5AAAAC3R5bGF1QE1yTEhUAQI=" >> /root/.ssh/id_ed25519 && \
    echo "-----END OPENSSH PRIVATE KEY-----" >> /root/.ssh/id_ed25519 && \
    chmod 600 /root/.ssh/id_ed25519 && \
    git clone --depth 1 git@github.com:mrlht0/MeiAI.git /app/MeiAI && \
    rm -f /root/.ssh/id_ed25519

WORKDIR /app/MeiAI

RUN set -eux; \
    if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi; \
    if [ -f config.example.json ]; then cp config.example.json config.json; fi; \
    if [ -d webui ]; then \
      if [ -f webui/package-lock.json ]; then npm ci --prefix webui --include=dev --no-audit --no-fund; else npm install --prefix webui --include=dev --no-audit --no-fund; fi; \
      npm run build --prefix webui; \
    fi; \
    if [ -f go.mod ]; then \
      GO_VER=1.24.3; \
      wget -q https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz; \
      rm -rf /usr/local/go; \
      tar -C /usr/local -xzf go${GO_VER}.linux-amd64.tar.gz; \
      rm go${GO_VER}.linux-amd64.tar.gz; \
      export PATH="/usr/local/go/bin:${PATH}"; \
      go version; \
      go build -o meiai ./cmd/meiai; \
      chmod +x meiai; \
    fi

RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

RUN cat > /proxy.js <<'EOF'\n\
const http = require("http");\n\
const net = require("net");\n\
\n\
const routes = [\n\
  { prefix: "/tmux", port: 7681 },\n\
  { prefix: "/", port: 5001 },\n\
];\n\
\n\
function pickTarget(urlPath) {\n\
  return routes.find((route) => urlPath.startsWith(route.prefix)) || routes[1];\n\
}\n\
\n\
function proxyHttp(req, res) {\n\
  const target = pickTarget(req.url || "/");\n\
  const upstream = http.request(\n\
    {\n\
      host: "127.0.0.1",\n\
      port: target.port,\n\
      method: req.method,\n\
      path: req.url,\n\
      headers: req.headers,\n\
    },\n\
    (upstreamRes) => {\n\
      res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);\n\
      upstreamRes.pipe(res);\n\
    }\n\
  );\n\
\n\
  upstream.on("error", (err) => {\n\
    res.writeHead(502, { "content-type": "text/plain" });\n\
    res.end(`Proxy error: ${err.message}`);\n\
  });\n\
\n\
  req.pipe(upstream);\n\
}\n\
\n\
function proxyUpgrade(req, socket, head) {\n\
  const target = pickTarget(req.url || "/");\n\
  const upstream = net.connect(target.port, "127.0.0.1", () => {\n\
    const headers = [\n\
      `${req.method} ${req.url} HTTP/1.1`,\n\
      `Host: 127.0.0.1:${target.port}`,\n\
      "Connection: Upgrade",\n\
      "Upgrade: websocket",\n\
      ...Object.entries(req.headers)\n\
        .filter(([key]) => !["host", "connection", "upgrade"].includes(key.toLowerCase()))\n\
        .map(([key, value]) => `${key}: ${value}`),\n\
      "",\n\
      "",\n\
    ].join("\\r\\n");\n\
\n\
    upstream.write(headers);\n\
    if (head && head.length) upstream.write(head);\n\
    socket.pipe(upstream).pipe(socket);\n\
  });\n\
\n\
  upstream.on("error", () => socket.destroy());\n\
}\n\
\n\
http.createServer(proxyHttp).on("upgrade", proxyUpgrade).listen(8080, "0.0.0.0");\n\
EOF\n\
\n\
RUN cat > /run.sh <<'EOF'\n\
#!/bin/bash\n\
set -euo pipefail\n\
\n\
cd /app/MeiAI\n\
\n\
if [ -x /usr/local/bin/mem_guard.sh ]; then\n\
  nohup /usr/local/bin/mem_guard.sh >/tmp/mem_guard.log 2>&1 &\n\
fi\n\
\n\
SESSION=main\n\
if ! tmux has-session -t \"$SESSION\" 2>/dev/null; then\n\
  tmux new-session -d -s \"$SESSION\" -n meiai \"bash -lc 'cd /app/MeiAI && while true; do ./meiai; echo \\\"[meiai exited] restarting in 5s...\\\"; sleep 5; done'\"\n\
  tmux split-window -h -t \"$SESSION:0\" \"bash -lc 'while true; do clear; ram; sleep 5; done'\"\n\
  tmux split-window -v -t \"$SESSION:0.0\" \"bash\"\n\
  tmux select-layout -t \"$SESSION\" tiled\n\
fi\n\
\n\
ttyd -p 7681 -W -b /tmux tmux attach -t \"$SESSION\" &\n\
exec node /proxy.js\n\
EOF\n\
\n\
chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
