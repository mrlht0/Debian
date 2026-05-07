# FROM alpine/openclaw:2026.5.6

# # Render sẽ dùng port này
# ENV PORT=18789

# # đảm bảo bind ra ngoài
# EXPOSE 18789

# ==============================================================
# Cloud Dev: ttyd + tmux + Caddy (Full Fixed Multi-Route)
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

# ─── 2. Cài đặt ttyd (bản mới nhất) ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 3. Cấu hình thư mục làm việc ────────────────────────────
# WORKDIR /workspace
WORKDIR /opt
RUN git clone --recursive https://github.com/OpenClaw/OpenClaw.git openclaw \
    && cd openclaw

# ─── 4. Cấu hình Bash Prompt & Tmux ──────────────────────────────
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

RUN printf "set -g mouse on\n\
unbind -n MouseDown3Pane\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n\
" > /root/.tmux.conf

# ─── 5. Script tự động khởi tạo Tmux session ───────────────────────────
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

# ─── 6. Thêm mem_guard (giới hạn RAM + log 5 dòng) ─────────────────────────────
RUN cat <<'EOF' > /usr/local/bin/mem_guard.sh
#!/bin/bash

THRESHOLD=85
LOG_LINES=5
LOG_FILE="/opt/mem.log"

log_buffer=()

get_mem_info() {
  max=$(cat /sys/fs/cgroup/memory.max)
  current=$(cat /sys/fs/cgroup/memory.current)

  used_mb=$((current / 1024 / 1024))
  max_mb=$((max / 1024 / 1024))
  percent=$((current * 100 / max))

  echo "$used_mb $max_mb $percent"
}

add_log() {
  log_buffer+=("$1")

  if [ "${#log_buffer[@]}" -gt "$LOG_LINES" ]; then
    log_buffer=("${log_buffer[@]:1}")
  fi

  printf "%s\n" "${log_buffer[@]}" > "$LOG_FILE"
}

wait_for_memory() {
  while true; do
    read used_mb max_mb percent <<< $(get_mem_info)

    if [ "$percent" -lt "$THRESHOLD" ]; then
      break
    fi

    add_log "⏸ RAM ${percent}% > ${THRESHOLD}%"
    sleep 1
  done
}

process_job() {
  job=$1
  read used_mb max_mb percent <<< $(get_mem_info)

  add_log "Job $job | ${used_mb}/${max_mb}MB (${percent}%)"

  sleep 0.3
}

main() {
  while true; do
    for i in $(seq 1 1000); do
      wait_for_memory
      process_job $i
    done
  done
}

main
EOF

RUN chmod +x /usr/local/bin/mem_guard.sh

RUN cat <<'EOF' > /usr/local/bin/ram
#!/bin/bash
watch -n 1 cat /opt/mem.log
EOF

RUN chmod +x /usr/local/bin/ram
# # watch -n 1 cat /opt/mem.log
# # Sau đó chỉ cần chạy: ram

RUN cat <<'EOF' > /usr/local/bin/ram.mem
#!/bin/bash
tail -f /opt/mem.log
EOF

RUN chmod +x /usr/local/bin/ram.mem

# chạy: ram.mem
# hoặc : tail -f /opt/mem.log

# ─── 7. Cấu hình Caddyfile (Xử lý đa đường dẫn) ─────────────────
RUN mkdir -p /etc/caddy && \
printf '(proxy_port) {\n\
    handle /{args.0}* {\n\
        reverse_proxy localhost:{args.0}\n\
    }\n\
}\n\
\n\
:8080 {\n\
    handle /terminal* {\n\
        reverse_proxy localhost:8082\n\
    }\n\
# \n\
#     handle /8083* {\n\
#         reverse_proxy localhost:8083\n\
#     }\n\
# \n\
#     handle /8084* {\n\
#         reverse_proxy localhost:8084\n\
#     }\n\
# \n\
#     handle /8085* {\n\
#         reverse_proxy localhost:8085\n\
#     }\n\
# \n\
#     handle /8086* {\n\
#         reverse_proxy localhost:8086\n\
#     }\n\
# \n\
#     handle /8087* {\n\
#         reverse_proxy localhost:8087\n\
#     }\n\
# \n\
#     handle /8088* {\n\
#         reverse_proxy localhost:8088\n\
#     }\n\
# \n\
#     handle /8089* {\n\
#         reverse_proxy localhost:8089\n\
#     }\n\
\n\
    handle /ttyd* {\n\
        reverse_proxy localhost:7681\n\
    }\n\
\n\
    handle /tmux* {\n\
        reverse_proxy localhost:8081\n\
    }\n\
\n\
    handle /openclaw* {\n\
        reverse_proxy 127.0.0.1:18789\n\
    }\n\
\n\
    handle /10000* {\n\
#        uri strip_prefix /10000\n\
        reverse_proxy 127.0.0.1:10000\n\
    }\n\
\n\
    # Sử dụng Snippet cho các port hàng loạt\n\
    import proxy_port 8083\n\
    import proxy_port 8084\n\
    import proxy_port 8085\n\
    import proxy_port 8086\n\
    import proxy_port 8087\n\
    import proxy_port 8088\n\
    import proxy_port 8089\n\
    # import proxy_port 10000\n\
    import proxy_port 10001\n\
    import proxy_port 10002\n\
    import proxy_port 10003\n\
\n\
    # Mặc định 1 trong ba từ trái qua phải\n\
    handle {\n\
        uri strip_prefix /18789\n\
        reverse_proxy 127.0.0.1:18789 127.0.0.1:8081 {\n\
            lb_policy first\n\
        }\n\
    }\n\
}\n' > /etc/caddy/Caddyfile

# ─── 8. Script khởi chạy toàn bộ dịch vụ ─────────────────────────────
# Quan trọng: Thêm tham số -W ghi, -b cho ttyd để khớp với đường dẫn của Caddy
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev..."\n\
\n\
# chạy mem_guard nền\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
# ttyd chính (Cổng 8081)\n\
ttyd -p 8081 -W -b /tmux /start.sh &\n\
\n\
# ttyd phụ (Cổng 8082)\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
# ttyd test (Cổng 8083)\n\
# ttyd -p 8083 -W -b /8083 bash &\n\
\n\
# ⏳ đợi service lên
sleep 1\n\

echo "Caddy đang chạy..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
# Chạy lại (reload) caddy
# caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
# watch -n 1 cat /opt/mem.log
