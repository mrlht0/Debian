
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

ENV PATH="/usr/local/go/bin:${PATH}"

# ─── 2. Cài đặt ttyd (bản mới nhất) ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 3. Cấu hình thư mục làm việc ────────────────────────────
# # 1. Đảm bảo có thư mục làm việc
WORKDIR /

RUN git clone --recursive https://github.com/mrlht0/MeiAI.git
WORKDIR /MeiAI

# Cài go
RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz \
    && rm go1.24.3.linux-amd64.tar.gz

# # 3. Cài đặt dependencies và build
RUN npm install
RUN cp config.example.json config.json
RUN npm ci --prefix webui --no-audit
RUN npm run build --prefix webui
# RUN find . -type f -name "*.go" | head -50
RUN go build -o meiai ./app

ENV MEIAI_LITE_MODE=0
ENV MEIAI_ADMIN_KEY=admin
ENV PORT=5001
# ./meiai

# ─── 4. Cấu hình Bash Prompt & Tmux ──────────────────────────────
WORKDIR /
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
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

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
        uri strip_prefix /5001\n\
        reverse_proxy 127.0.0.1:20128 127.0.0.1:5001 {\n\
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
# \n\
# ⏳ đợi service lên
sleep 1\n\

echo "Caddy đang chạy..."\n\
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile\n\
echo "⏳ run 9router" \n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]

# Chạy lại (reload) caddy
# caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
# watch -n 1 cat /opt/mem.log
