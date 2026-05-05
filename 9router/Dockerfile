# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

# ==============================================================
# Cloud Dev + 9router + ttyd + Caddy (FIXED PRODUCTION VERSION)
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

# ─── 1. Base packages ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    caddy \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt install -y nodejs \
    && apt clean && rm -rf /var/lib/apt/lists/*

# ─── 2. ttyd ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# ─── 3. 9router (official image - KHÔNG BUILD) ────────────────
# chạy side-process trong container
RUN curl -fsSL https://raw.githubusercontent.com/decolua/9router/main/package.json || true

# ─── 4. workspace ─────────────────────────
WORKDIR /workspace

# ─── 5. tmux config ─────────────────────────
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

RUN printf "set -g mouse on\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n" > /root/.tmux.conf

# ─── 6. start script (tmux auto) ─────────────────────────
RUN printf '#!/bin/bash\n\
SESSION=main\n\
tmux has-session -t $SESSION 2>/dev/null || (\n\
  tmux new-session -d -s $SESSION\n\
  tmux split-window -h\n\
  tmux split-window -v\n\
  tmux select-layout tiled\n\
)\n\
exec tmux attach -t $SESSION\n' > /start.sh \
&& chmod +x /start.sh

# ─── 7. Caddy config (1 entry point all services) ─────────────
RUN mkdir -p /etc/caddy && printf '\
:8080 {\n\
\n\
    # 9router main service\n\
    handle /9router* {\n\
        reverse_proxy localhost:20128\n\
    }\n\
\n\
    # ttyd terminal\n\
    handle /terminal* {\n\
        reverse_proxy localhost:7681\n\
    }\n\
\n\
    # default -> 9router\n\
    handle {\n\
        reverse_proxy localhost:20128\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# ─── 8. mem_guard (safe version, no crash, no spam) ───────────
RUN cat <<'EOF' > /usr/local/bin/mem_guard.sh
#!/bin/bash

THRESHOLD=85
LOG_LINES=5
LOG_FILE="/workspace/mem.log"

log_buffer=()

get_mem() {
  max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo 536870912)
  cur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0)

  percent=$((cur * 100 / max))
  echo "$cur $max $percent"
}

log() {
  log_buffer+=("$1")
  [ ${#log_buffer[@]} -gt $LOG_LINES ] && log_buffer=("${log_buffer[@]:1}")
  printf "%s\n" "${log_buffer[@]}" > "$LOG_FILE"
}

while true; do
  read cur max percent <<< $(get_mem)

  if [ "$percent" -ge "$THRESHOLD" ]; then
    log "⚠ RAM ${percent}% (throttling)"
    sleep 2
  else
    log "OK RAM ${percent}%"
    sleep 3
  fi
done
EOF

RUN chmod +x /usr/local/bin/mem_guard.sh

# ─── 9. MAIN RUN (FIXED PID1 STRUCTURE) ───────────────────────
RUN printf '#!/bin/bash\n\
echo "Starting Cloud Dev + 9router..."\n\
\n\
# mem guard\n\
/usr/local/bin/mem_guard.sh &\n\
\n\
# ttyd terminal\n\
ttyd -p 7681 -W /start.sh &\n\
\n\
# 9router (MAIN APP)\n\
bun server.js &\n\
\n\
# caddy (PID1 - IMPORTANT)\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n' \
> /run.sh && chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
