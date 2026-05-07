# ==============================================================
# Cloud Dev: ttyd + tmux + Caddy + OpenClaw (Build Sẵn)
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── 1. Cài đặt các gói cơ bản ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    caddy \
    tar net-tools \
    # python3 python3-pip \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── 2. Mượn Host để Build OpenClaw (Sửa lỗi thiếu Submodule) ───
WORKDIR /opt
RUN git clone --recursive https://github.com/OpenClaw/OpenClaw.git openclaw_src \
    && cd openclaw_src \
    # && mkdir build && cd build \
    # && cmake .. -DCMAKE_BUILD_TYPE=Release \
    # && make -j$(nproc) \
    # && make install \
    # && cd /opt && rm -rf openclaw_src

# ─── 3. Cài đặt ttyd (bản mới nhất) ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 4. Cấu hình thư mục làm việc ────────────────────────────
# WORKDIR /workspace

# ─── 5. Cấu hình Bash Prompt & Tmux ──────────────────────────────
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc \
    && printf "set -g mouse on\nunbind -n MouseDown3Pane\nset -g history-limit 10000\nsetw -g mode-keys vi\n" > /root/.tmux.conf

# ─── 6. Script tự động khởi tạo Tmux session ───────────────────────────
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

# ─── 7. Thêm mem_guard (giới hạn RAM) ─────────────────────────────
RUN printf '#!/bin/bash\n\
THRESHOLD=85\n\
LOG_FILE="/workspace/mem.log"\n\
while true; do\n\
  max=$(cat /sys/fs/cgroup/memory.max)\n\
  current=$(cat /sys/fs/cgroup/memory.current)\n\
  percent=$((current * 100 / max))\n\
  echo "RAM Usage: $percent%" > $LOG_FILE\n\
  sleep 5\n\
done\n' > /usr/local/bin/mem_guard.sh && chmod +x /usr/local/bin/mem_guard.sh

# ─── 8. Cấu hình Caddyfile ─────────────────
RUN mkdir -p /etc/caddy && printf ':8080 {\n\
    handle /terminal* { reverse_proxy localhost:8082 }\n\
    handle /ttyd* { reverse_proxy localhost:7681 }\n\
    handle /tmux* { reverse_proxy localhost:8081 }\n\
    handle /openclaw* { reverse_proxy 127.0.0.1:18789 }\n\
    handle /10000* { reverse_proxy 127.0.0.1:10000 }\n\
    handle { \n\
        uri strip_prefix /10000\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# ─── 9. Script khởi chạy (Entrypoint) ─────────────────────────────
RUN printf '#!/bin/bash\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
ttyd -p 8081 -W -b /tmux /start.sh &\n\
ttyd -p 8082 -W -b /terminal bash &\n\
sleep 1\n\
echo "Cloud Dev Ready at port 8080"\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080
CMD ["/run.sh"]
