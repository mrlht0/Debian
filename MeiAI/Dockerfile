# ==============================================================
# Cloud Dev: ttyd + tmux + Node.js Proxy (Fixed 404 Final)
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

# ─── 2. Cài đặt ttyd (bản mới nhất) ─────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── 3. Cấu hình thư mục làm việc & SSH Key bảo mật ───────────
WORKDIR /
RUN apt-get update && apt-get install -y git openssh-client

RUN git clone https://github.com/mrlht0/ds2api.git

WORKDIR /ds2api

# Cài đặt môi trường Golang mới nhất (1.24.3)
RUN wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz \
    && echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
ENV PATH="/usr/local/go/bin:${PATH}"

# Cài đặt dependencies Node và thực hiện Build 
WORKDIR /ds2api

RUN cp config.example.json config.json

RUN npm ci --prefix webui
RUN npm run build --prefix webui

RUN go mod download

RUN CGO_ENABLED=0 \
    go build \
    -buildvcs=false \
    -ldflags="-s -w" \
    -o ds2api \
    ./cmd/ds2api

RUN chmod +x ds2api

# Watchdog Script tự động theo dõi, ghi log tối đa 2000 dòng và hồi sinh ứng dụng khi crash
# RUN printf '#!/bin/bash\n\
# cd /ds2api\n\
# LOG=/ds2api/meiai.log\n\
# touch $LOG\n\
# while true\n\
# do\n\
#     echo "==========================" >> $LOG\n\
#     echo "[START] $(date)" >> $LOG\n\
#     ./meiai >> $LOG 2>&1 &\n\
#     PID=$!\n\
#     while kill -0 $PID 2>/dev/null\n\
#     do\n\
#         tail -n 2000 $LOG > ${LOG}.tmp && mv ${LOG}.tmp $LOG\n\
#         sleep 30\n\
#     done\n\
#     echo "[CRASH] restarting in 5s..." >> $LOG\n\
#     sleep 5\n\
# done\n\
# ' > /MeiAI/start-meiai.sh && chmod +x /MeiAI/start-meiai.sh

# ─── 4. Cấu hình Bash Prompt & Tmux ──────────────────────────────
WORKDIR /
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

RUN printf "set -g mouse on\n\
unbind -n MouseDown3Pane\n\
set -g history-limit 10000\n\
setw -g mode-keys vi\n\
" > /root/.tmux.conf

# Script tự động tạo và gán layout cho phiên Tmux nền
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

# ─── 5. Thêm công cụ mem_guard (Giới hạn và quản trị RAM tối ưu) ───
RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

# ─── 6. Cấu hình NODE.JS SMART PROXY (Khắc phục triệt để lỗi 404 Trailing Slash) ───
WORKDIR /app-proxy
RUN npm init -y && npm install http-proxy

RUN printf 'const http = require("http");\n\
const HttpProxy = require("http-proxy");\n\
\n\
const proxy = HttpProxy.createProxyServer({\n\
    ws: true,\n\
    changeOrigin: true\n\
});\n\
\n\
const routes = {\n\
    "/terminal": 8082,\n\
    "/ttyd": 7681,\n\
    "/tmux": 8081,\n\
    "/openclaw": 18789,\n\
    "/meiai": 5001\n\
};\n\
\n\
function handleProxy(req, res, isWs = false, socket = null, head = null) {\n\
    let url = req.url;\n\
    \n\
    // Tự động chuẩn hóa: Nếu người dùng truy cập /terminal đổi thành /terminal/\n\
    for (const prefix in routes) {\n\
        if (url === prefix) {\n\
            if (!isWs) {\n\
                res.writeHead(301, { "Location": prefix + "/" });\n\
                res.end();\n\
                return;\n\
            }\n\
            url = prefix + "/";\n\
        }\n\
        \n\
        if (url.startsWith(prefix + "/")) {\n\
            const target = `http://127.0.0.1:${routes[prefix]}`;\n\
            if (isWs) {\n\
                proxy.ws(req, socket, head, { target });\n\
            } else {\n\
                proxy.web(req, res, { target });\n\
            }\n\
            return;\n\
        }\n\
    }\n\
\n\
    // Kiểm tra dải cổng động: /8083 đến /8089 và /10001 đến /10003\n\
    const dynamicMatch = url.match(/^\\/((?:808[3-9])|(?:1000[1-3]))(?:\\/|$)/);\n\
    if (dynamicMatch) {\n\
        const port = dynamicMatch[1];\n\
        const target = `http://127.0.0.1:${port}`;\n\
        if (isWs) {\n\
            proxy.ws(req, socket, head, { target });\n\
        } else {\n\
            proxy.web(req, res, { target });\n\
        }\n\
        return;\n\
    }\n\
\n\
    // Tuyến mặc định: Xóa tiền tố /10000 nếu có và chuyển tới cổng 10000\n\
    if (url.startsWith("/10000/")) {\n\
        req.url = url.substring(6);\n\
    } else if (url === "/10000") {\n\
        req.url = "/";\n\
    }\n\
    \n\
    const defaultTarget = "http://127.0.0.1:10000";\n\
    if (isWs) {\n\
        proxy.ws(req, socket, head, { target: defaultTarget });\n\
    } else {\n\
        proxy.web(req, res, { target: defaultTarget });\n\
    }\n}\n\
\n\
const server = http.createServer((req, res) => {\n\
    handleProxy(req, res, false);\n\
});\n\
\n\
server.on("upgrade", (req, socket, head) => {\n\
    handleProxy(req, null, true, socket, head);\n\
});\n\
\n\
proxy.on("error", (err, req, res) => {\n\
    if (res && !res.headersSent) {\n\
        res.writeHead(502, { "Content-Type": "text/plain" });\n\
        res.end("Bad Gateway: Connection Refused");\n\
    }\n\
});\n\
\n\
server.listen(8080, "0.0.0.0", () => {\n\
    console.log("🚀 Node.js Smart Proxy đã khắc phục lỗi 404 đang chạy tại port 8080");\n\
});\n' > proxy.js

# ─── 7. Script khởi chạy toàn bộ dịch vụ mạng hệ thống ─────────────────
WORKDIR /
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev..."\n\
\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
(\n\
cd /ds2api \n\

LOG=/ds2api/ds2api.log \n\
touch "$LOG" \n\

while true \n\
do \n\
    echo "==========================" >> "$LOG" \n\
    echo "[START] $(date)" >> "$LOG" \n\

    printf "1\n" | node start.mjs >> "$LOG" 2>&1 \n\

    echo "[CRASH] restarting in 5s..." >> "$LOG" \n\

    tail -n 2000 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG" \n\

    sleep 5 \n\
done\n\
) &\n\
\n\
ttyd -p 8081 -W -b /tmux /start.sh &\n\
ttyd -p 8082 -W -b /terminal bash &\n\
\n\
sleep 2\n\
\n\
echo "Khởi động Node.js Smart Proxy..."\n\
exec node /app-proxy/proxy.js\n\
' > /run.sh && chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
