# FROM debian:bookworm-slim

# ENV DEBIAN_FRONTEND=noninteractive
# ENV PORT=8080
# ENV PASSWORD=123456

# # ─── Install base ─────────────────────────────────────────
# RUN apt-get update && apt-get install -y \
#     curl wget git bash nano \
#     procps htop \
#     ca-certificates \
#     build-essential \
#     python3 python3-pip \
#     && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
#     && apt-get install -y nodejs \
#     && apt-get clean && rm -rf /var/lib/apt/lists/*

# # ─── Install ttyd ─────────────────────────────────────────
# RUN wget -O /usr/local/bin/ttyd \
#     https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
#     chmod +x /usr/local/bin/ttyd

# # ─── Workspace ────────────────────────────────────────────
# WORKDIR /workspace

# # ─── Đổi user ────────────────────────────────────────────
# RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# # ─── Start script ─────────────────────────────────────────
# RUN printf '#!/bin/bash\n\
# echo "Starting ttyd on port $PORT"\n\
# exec ttyd -p $PORT -c :$PASSWORD -W bash\n\
# ' > /start.sh && chmod +x /start.sh

# EXPOSE 8080

# CMD ["/start.sh"]

# ==============================================================
# Cloud Dev: ttyd + tmux + Caddy (multi route FIXED)
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── Install base ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    caddy \
    && apt clean && rm -rf /var/lib/apt/lists/*

# ─── Install ttyd ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── Workspace ────────────────────────────
WORKDIR /workspace

# ─── Prompt ──────────────────────────────
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# ─── tmux config ─────────────────────────
RUN printf "set -g mouse off\n\
unbind -n MouseDown3Pane\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n\
" > /root/.tmux.conf

# ─── tmux auto ───────────────────────────
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

# ─── Caddy config (FIXED) ─────────────────
RUN mkdir -p /etc/caddy && \
printf ':8080 {\n\
\n\
    # terminal phụ\n\
    handle_path /terminal* {\n\
        reverse_proxy localhost:8082\n\
    }\n\
\n\
    # reserved ports\n\
    handle_path /8083* {\n\
        reverse_proxy localhost:8083\n\
    }\n\
    handle_path /8084* {\n\
        reverse_proxy localhost:8084\n\
    }\n\
    handle_path /8085* {\n\
        reverse_proxy localhost:8085\n\
    }\n\
    handle_path /8086* {\n\
        reverse_proxy localhost:8086\n\
    }\n\
    handle_path /8087* {\n\
        reverse_proxy localhost:8087\n\
    }\n\
    handle_path /8088* {\n\
        reverse_proxy localhost:8088\n\
    }\n\
    handle_path /8089* {\n\
        reverse_proxy localhost:8089\n\
    }\n\
\n\
    # default → ttyd tmux\n\
    handle {\n\
        reverse_proxy localhost:8081\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# ─── Run all ─────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Starting services..."\n\
\n\
# ttyd chính (tmux)\n\
ttyd -p 8081 -W /start.sh &\n\
\n\
# ttyd phụ\n\
ttyd -p 8082 -b /terminal bash &\n\
\n\
# chạy caddy\n\
# exec caddy run --config /etc/caddy/Caddyfile\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]


# # =============================================================
# # Hai user 1 port
# # ============================================================
# FROM debian:bookworm-slim

# ENV DEBIAN_FRONTEND=noninteractive

# # ─── Install nhẹ ─────────────────────────────
# RUN apt-get update && apt-get install -y \
#     bash curl wget git nano \
#     procps htop \
#     ca-certificates \
#     && apt-get clean && rm -rf /var/lib/apt/lists/*

# # ─── ttyd ───────────────────────────────────
# RUN wget -O /usr/local/bin/ttyd \
#     https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
#     chmod +x /usr/local/bin/ttyd

# # ─── tạo user test sandbox ──────────────────
# RUN useradd -m test && \
#     echo "test:123" | chpasswd && \
#     mkdir -p /home/test/work && \
#     chown -R test:test /home/test

# # ─── prompt đẹp ─────────────────────────────
# RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# # ─── start script ───────────────────────────
# RUN printf '#!/bin/bash\n\
# echo "Starting ttyd on port $PORT"\n\
# exec ttyd -p $PORT \\\n\
#   -c admin:admin123 \\\n\
#   -c test:123 \\\n\
#   -W bash\n\
# ' > /start.sh && chmod +x /start.sh

# EXPOSE 8080

# CMD ["/start.sh"]
