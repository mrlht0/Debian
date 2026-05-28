# syntax=docker/dockerfile:1.7

FROM node:26-bookworm-slim

# Runtime defaults for MeiAI inside the container.
ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    PORT=5001 \
    MEIAI_LITE_MODE=0 \
    MEIAI_ADMIN_KEY=admin

# Base tools for cloning, building, running tmux, and serving the web UI.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget git openssh-client procps tmux ca-certificates \
    build-essential python3 make g++ tar net-tools \
    && rm -rf /var/lib/apt/lists/*

# Install ttyd so the tmux session can be opened from the browser at /tmux/.
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

WORKDIR /app

# Temporary SSH key material for cloning the private MeiAI repository during build.
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

# Install app dependencies, prepare config, build the web UI, and compile the Go binary if present.
RUN set -eux; \
    if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi; \
    if [ -f config.example.json ]; then cp config.example.json config.json; fi; \
    if [ -d webui ]; then \
      if [ -f webui/package-lock.json ]; then npm ci --prefix webui --include=dev --no-audit --no-fund; else npm install --prefix webui --include=dev --no-audit --no-fund; fi; \
      npm run build --prefix webui; \
    fi; \
    if [ -f go.mod ]; then \
      wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz && \
      rm -rf /usr/local/go; \
      tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz; \
      echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc; \
      rm go1.24.3.linux-amd64.tar.gz; \
      export PATH="/usr/local/go/bin:${PATH}"; \
      go version; \
      go build -o meiai ./cmd/meiai; \
      chmod +x meiai; \
    fi

# Install the RAM helper script. It provides the `ram` command used in tmux.
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# Small Node proxy that keeps one public port:
# - /tmux -> ttyd
# - everything else -> MeiAI on the internal app port
RUN cat > /proxy.js <<'EOF'
const http = require("http");
const net = require("net");

const routes = [
  { prefix: "/tmux", port: 7681 },
  { prefix: "/", port: 5001 },
];

function pickTarget(urlPath) {
  return routes.find((route) => urlPath.startsWith(route.prefix)) || routes[1];
}

function proxyHttp(req, res) {
  const requestUrl = new URL(req.url || "/", "http://127.0.0.1");
  if (requestUrl.pathname === "/tmux") {
    res.writeHead(302, { Location: "/tmux/" });
    res.end();
    return;
  }

  const target = pickTarget(requestUrl.pathname);
  const upstream = http.request(
    {
      host: "127.0.0.1",
      port: target.port,
      method: req.method,
      path: req.url,
      headers: req.headers,
    },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);
      upstreamRes.pipe(res);
    }
  );

  upstream.on("error", (err) => {
    res.writeHead(502, { "content-type": "text/plain" });
    res.end(`Proxy error: ${err.message}`);
  });

  req.pipe(upstream);
}

function proxyUpgrade(req, socket, head) {
  const requestUrl = new URL(req.url || "/", "http://127.0.0.1");
  const target = pickTarget(requestUrl.pathname);
  const upstream = net.connect(target.port, "127.0.0.1", () => {
    const headers = [
      `${req.method} ${req.url} HTTP/1.1`,
      `Host: 127.0.0.1:${target.port}`,
      "Connection: Upgrade",
      "Upgrade: websocket",
      ...Object.entries(req.headers)
        .filter(([key]) => !["host", "connection", "upgrade"].includes(key.toLowerCase()))
        .map(([key, value]) => `${key}: ${value}`),
      "",
      "",
    ].join("\r\n");

    upstream.write(headers);
    if (head && head.length) upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });

  upstream.on("error", () => socket.destroy());
}

http.createServer(proxyHttp).on("upgrade", proxyUpgrade).listen(8080, "0.0.0.0");
EOF

# Entry script:
# - starts mem_guard if present
# - creates a fixed tmux session with app / RAM monitor / shell panes
# - starts ttyd for browser access to tmux
# - runs the proxy on port 8080
RUN cat > /run.sh <<'EOF'
#!/bin/bash
set -euo pipefail

cd /app/MeiAI

if [ -x /usr/local/bin/mem_guard.sh ]; then
  nohup /usr/local/bin/mem_guard.sh >/tmp/mem_guard.log 2>&1 &
fi

SESSION=main
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" -n meiai "bash -lc 'cd /app/MeiAI && while true; do ./meiai; echo \"[meiai exited] restarting in 5s...\"; sleep 5; done'"
  tmux split-window -h -t "$SESSION:0" "bash -lc 'while true; do clear; ram; sleep 5; done'"
  tmux split-window -v -t "$SESSION:0.0" "bash"
  tmux select-layout -t "$SESSION" tiled
fi

ttyd -p 7681 -W -b /tmux tmux attach -t "$SESSION" &
exec node /proxy.js
EOF

# Make the entry script executable.
RUN chmod +x /run.sh

# Only one public port is exposed to the host.
EXPOSE 8080

# Start the container through the launcher script.
CMD ["/run.sh"]
