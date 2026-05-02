FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

# ─── Install base + dev tools ─────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git bash nano \
    ca-certificates \
    build-essential \
    python3 python3-pip \
    nodejs npm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── Install code-server (VS Code web) ────────────────────
RUN curl -fsSL https://code-server.dev/install.sh | sh

# ─── Install ttyd ─────────────────────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── Workspace ────────────────────────────────────────────
RUN mkdir -p /workspace
WORKDIR /workspace

# ─── Password (đổi nếu muốn) ─────────────────────────────
ENV PASSWORD=123456

# ─── Start script ─────────────────────────────────────────
RUN printf '#!/bin/bash\n\
# start ttyd (terminal web)\n\
ttyd -p 7681 -c admin:$PASSWORD -W bash &\n\
\n\
# start VS Code web\n\
code-server \
  --bind-addr 0.0.0.0:$PORT \
  --auth password \
  --password $PASSWORD \
  /workspace\n\
' > /start.sh && chmod +x /start.sh

EXPOSE 8080 7681

CMD ["/start.sh"]
