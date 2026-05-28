# syntax=docker/dockerfile:1.7

FROM node:26-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    PORT=5001 \
    MEIAI_LITE_MODE=0 \
    MEIAI_ADMIN_KEY=admin

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget git openssh-client procps tmux ca-certificates \
    build-essential python3 make g++ tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN --mount=type=ssh \
    mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts && \
    git clone --depth 1 git@github.com:mrlht0/MeiAI.git /app/MeiAI

WORKDIR /app/MeiAI

RUN set -eux; \
    if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi; \
    if [ -f config.example.json ]; then cp config.example.json config.json; fi; \
    if [ -d webui ]; then \
      if [ -f webui/package-lock.json ]; then npm ci --prefix webui --no-audit --no-fund; else npm install --prefix webui --no-audit --no-fund; fi; \
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

RUN printf '#!/bin/bash\n\
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
  tmux new-session -d -s \"$SESSION\" -n app \"bash -lc '\''cd /app/MeiAI && while true; do ./meiai; echo \\\"[meiai exited] restarting in 5s...\\\"; sleep 5; done'\''\"\n\
  tmux split-window -h -t \"$SESSION:0\" \"bash -lc 'while true; do clear; ram; sleep 5; done'\"\n\
  tmux split-window -v -t \"$SESSION:0.0\" \"bash\"\n\
  tmux select-layout -t \"$SESSION\" tiled\n\
fi\n\
\n\
echo \"tmux session: $SESSION\"\n\
echo \"use: tmux attach -t $SESSION\"\n\
echo \"monitor RAM with: ram\"\n\
\n\
exec tail -f /dev/null\n\
' > /start.sh && chmod +x /start.sh

CMD ["/start.sh"]
