FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080
ENV PASSWORD=123456

# ─── Install base ─────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git bash nano \
    rocps htop \
    ca-certificates \
    build-essential \
    python3 python3-pip \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── Install ttyd ─────────────────────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── Workspace ────────────────────────────────────────────
WORKDIR /workspace

# ─── Đổi user ────────────────────────────────────────────
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# ─── Start script ─────────────────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Starting ttyd on port $PORT"\n\
exec ttyd -p $PORT -c :$PASSWORD -W bash\n\
' > /start.sh && chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
