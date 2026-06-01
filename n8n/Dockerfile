# ==============================================================
# Cloud Dev: ttyd + tmux + TRAEFIK (Thay thế Caddy)
# ==============================================================
# ⚠️  Traefik thường dùng với Docker labels hoặc dynamic config files
#     Ở đây dùng static + dynamic config file (phù hợp trong container)
#     Ưu điểm: dashboard đẹp, hot-reload config, middleware phong phú
#     Nhược điểm: nặng hơn (binary ~100MB), config phức tạp hơn Caddy
# ==============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ─── 1. Cài đặt các gói cơ bản ─────────────────────────
RUN apt update && apt install -y \
    bash curl wget git nano \
    procps htop tmux \
    ca-certificates \
    tar net-tools \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── 2. Cài đặt Traefik ──────────────────────────────────────
# Tải binary Traefik trực tiếp (không cần package manager)
RUN wget -qO /tmp/traefik.tar.gz \
    https://github.com/traefik/traefik/releases/download/v3.3.4/traefik_v3.3.4_linux_amd64.tar.gz && \
    tar -xzf /tmp/traefik.tar.gz -C /usr/local/bin traefik && \
    chmod +x /usr/local/bin/traefik && \
    rm /tmp/traefik.tar.gz

# ─── 3. Cài đặt ttyd ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 4. Cấu hình SSH & Clone repo ────────────────────────────
WORKDIR /
RUN apt-get update && apt-get install -y git openssh-client

RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /root/.ssh/id_ed25519 && \
    echo "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW" >> /root/.ssh/id_ed25519 && \
    echo "QyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+QAAAJCe7Zalnu2W" >> /root/.ssh/id_ed25519 && \
    echo "pQAAAAtzc2gtZWQyNTUxOQAAACClQvZmGWhT+3nR6+i/v0I2RQFOvy4PRcnoYtr/UBkz+Q" >> /root/.ssh/id_ed25519 && \
    echo "AAAECu5uyGvQNoDwFalwDHbBQswmv31282a9dUGLoEnkLiIqVC9mYZaFP7edHr6L+/QjZF" >> /root/.ssh/id_ed25519 && \
    echo "AU6/Lg9Fyehi2v9QGTP5AAAAC3R5bGF1QE1yTEhUAQI=" >> /root/.ssh/id_ed25519 && \
    echo "-----END OPENSSH PRIVATE KEY-----" >> /root/.ssh/id_ed25519 && \
    chmod 600 /root/.ssh/id_ed25519 && \
    git clone git@github.com:mrlht0/MeiAI.git && \
    rm /root/.ssh/id_ed25519

WORKDIR /MeiAI

# ─── 5. Cài Go & Build MeiAI ─────────────────────────────────
RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz \
    && echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
ENV PATH="/usr/local/go/bin:${PATH}"
RUN go version

RUN npm install
RUN cp config.example.json config.json
RUN npm ci --prefix webui --no-audit
RUN npm run build --prefix webui
RUN go build -o meiai ./cmd/meiai
RUN chmod +x meiai

ENV NODE_ENV=production \
    MEIAI_LITE_MODE=0 \
    MEIAI_ADMIN_KEY=admin \
    PORT=5001

RUN printf '#!/bin/bash\n\
cd /MeiAI\n\
LOG=/MeiAI/meiai.log\n\
touch $LOG\n\
while true; do\n\
    echo "==========================" >> $LOG\n\
    echo "[START] $(date)" >> $LOG\n\
    ./meiai >> $LOG 2>&1 &\n\
    PID=$!\n\
    while kill -0 $PID 2>/dev/null; do\n\
        tail -n 2000 $LOG > ${LOG}.tmp && mv ${LOG}.tmp $LOG\n\
        sleep 30\n\
    done\n\
    echo "[CRASH] restarting in 5s..." >> $LOG\n\
    sleep 5\n\
done\n\
' > /MeiAI/start-meiai.sh && chmod +x /MeiAI/start-meiai.sh

# ─── 6. Cấu hình Bash & Tmux ─────────────────────────────────
WORKDIR /
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

RUN printf "set -g mouse on\n\
unbind -n MouseDown3Pane\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n" > /root/.tmux.conf

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

RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# ─── 7. Cấu hình Traefik ─────────────────────────────────────
# Traefik chia làm 2 file:
#   - traefik.yml: static config (entrypoints, providers, dashboard)
#   - dynamic.yml: dynamic config (routers, services) — hot-reload được

RUN mkdir -p /etc/traefik

# Static config
RUN printf 'api:\n\
  dashboard: true    # Dashboard tại http://host:8090/dashboard/\n\
  insecure: true\n\
\n\
entryPoints:\n\
  web:\n\
    address: ":8080"\n\
\n\
providers:\n\
  file:\n\
    filename: /etc/traefik/dynamic.yml\n\
    watch: true      # Tự reload khi file thay đổi (hot-reload)\n\
\n\
log:\n\
  level: INFO\n\
\n\
# Traefik lắng nghe dashboard tại port 8090\n\
# Truy cập: http://host:8090/dashboard/\n\
' > /etc/traefik/traefik.yml

# Dynamic config (routers + services + middlewares)
# Traefik dùng PathPrefix rule, khác Caddy dùng handle
RUN printf 'http:\n\
  middlewares:\n\
    # Middleware strip prefix cho từng path\n\
    strip-terminal:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/terminal"\n\
    strip-ttyd:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/ttyd"\n\
    strip-tmux:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/tmux"\n\
    strip-openclaw:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/openclaw"\n\
    strip-meiai:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/meiai"\n\
    strip-10000:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/10000"\n\
    strip-8083:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/8083"\n\
    strip-8084:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/8084"\n\
    strip-8085:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/8085"\n\
    strip-8086:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/8086"\n\
    strip-8087:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/8087"\n\
    strip-8088:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/8088"\n\
    strip-8089:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/8089"\n\
    strip-10001:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/10001"\n\
    strip-10002:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/10002"\n\
    strip-10003:\n\
      stripPrefix:\n\
        prefixes:\n\
          - "/10003"\n\
\n\
  routers:\n\
    terminal:\n\
      rule: "PathPrefix(`/terminal`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-terminal]\n\
      service: svc-terminal\n\
      priority: 100\n\
\n\
    ttyd:\n\
      rule: "PathPrefix(`/ttyd`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-ttyd]\n\
      service: svc-ttyd\n\
      priority: 100\n\
\n\
    tmux:\n\
      rule: "PathPrefix(`/tmux`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-tmux]\n\
      service: svc-tmux\n\
      priority: 100\n\
\n\
    openclaw:\n\
      rule: "PathPrefix(`/openclaw`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-openclaw]\n\
      service: svc-openclaw\n\
      priority: 100\n\
\n\
    meiai:\n\
      rule: "PathPrefix(`/meiai`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-meiai]\n\
      service: svc-meiai\n\
      priority: 100\n\
\n\
    route-10000:\n\
      rule: "PathPrefix(`/10000`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-10000]\n\
      service: svc-10000\n\
      priority: 100\n\
\n\
    route-8083:\n\
      rule: "PathPrefix(`/8083`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-8083]\n\
      service: svc-8083\n\
      priority: 100\n\
\n\
    route-8084:\n\
      rule: "PathPrefix(`/8084`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-8084]\n\
      service: svc-8084\n\
      priority: 100\n\
\n\
    route-8085:\n\
      rule: "PathPrefix(`/8085`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-8085]\n\
      service: svc-8085\n\
      priority: 100\n\
\n\
    route-8086:\n\
      rule: "PathPrefix(`/8086`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-8086]\n\
      service: svc-8086\n\
      priority: 100\n\
\n\
    route-8087:\n\
      rule: "PathPrefix(`/8087`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-8087]\n\
      service: svc-8087\n\
      priority: 100\n\
\n\
    route-8088:\n\
      rule: "PathPrefix(`/8088`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-8088]\n\
      service: svc-8088\n\
      priority: 100\n\
\n\
    route-8089:\n\
      rule: "PathPrefix(`/8089`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-8089]\n\
      service: svc-8089\n\
      priority: 100\n\
\n\
    route-10001:\n\
      rule: "PathPrefix(`/10001`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-10001]\n\
      service: svc-10001\n\
      priority: 100\n\
\n\
    route-10002:\n\
      rule: "PathPrefix(`/10002`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-10002]\n\
      service: svc-10002\n\
      priority: 100\n\
\n\
    route-10003:\n\
      rule: "PathPrefix(`/10003`)"\n\
      entryPoints: [web]\n\
      middlewares: [strip-10003]\n\
      service: svc-10003\n\
      priority: 100\n\
\n\
    # Catch-all: forward tới 10000\n\
    catchall:\n\
      rule: "PathPrefix(`/`)"\n\
      entryPoints: [web]\n\
      service: svc-10000\n\
      priority: 1\n\
\n\
  services:\n\
    svc-terminal:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8082"\n\
    svc-ttyd:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:7681"\n\
    svc-tmux:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8081"\n\
    svc-openclaw:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:18789"\n\
    svc-meiai:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:5001"\n\
    svc-10000:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:10000"\n\
    svc-8083:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8083"\n\
    svc-8084:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8084"\n\
    svc-8085:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8085"\n\
    svc-8086:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8086"\n\
    svc-8087:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8087"\n\
    svc-8088:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8088"\n\
    svc-8089:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:8089"\n\
    svc-10001:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:10001"\n\
    svc-10002:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:10002"\n\
    svc-10003:\n\
      loadBalancer:\n\
        servers:\n\
          - url: "http://127.0.0.1:10003"\n\
' > /etc/traefik/dynamic.yml

# ─── 8. Script khởi chạy ─────────────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev (Traefik)..."\n\
\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
(\n\
while true; do\n\
    pgrep -f start-meiai.sh >/dev/null || nohup /MeiAI/start-meiai.sh > /dev/null 2>&1 &\n\
    sleep 60\n\
done\n\
) &\n\
\n\
ttyd -p 8081 -W -b /tmux /start.sh &\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
sleep 1\n\
echo "Traefik đang chạy..."\n\
echo "Dashboard: http://host:8090/dashboard/"\n\
# Traefik đọc static config từ file\n\
exec traefik --configFile=/etc/traefik/traefik.yml\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080 8090
CMD ["/run.sh"]

# Hot-reload: chỉ cần sửa /etc/traefik/dynamic.yml, Traefik tự reload
# Dashboard: http://host:8090/dashboard/
