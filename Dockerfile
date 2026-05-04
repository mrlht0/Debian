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
# ttyd + tmux (lightweight, mouse off, port 8080)
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

# ─── Install cực nhẹ ───────────────────────
RUN apt-get update && apt-get install -y \
    bash curl wget git nano \
    procps htop \
    tmux \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── ttyd ─────────────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── workspace ────────────────────────────
WORKDIR /workspace

# ─── prompt ───────────────────────────────
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# ─── tmux config ──────────────────────────
RUN printf "set -g mouse off\n\
unbind -n MouseDown3Pane\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n\
bind r source-file ~/.tmux.conf \\; display \"Reloaded!\"\n\
" > /root/.tmux.conf

# ─── auto tmux ────────────────────────────
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

# ─── run ttyd ─────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Starting ttyd + tmux on port $PORT"\n\
exec ttyd -p 8080 -W /start.sh\n\
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
