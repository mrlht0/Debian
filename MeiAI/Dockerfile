# ─── 6. Cấu hình NODE.JS PROXY (Sửa lỗi 404 Sub-path & WebSocket) ───
WORKDIR /app-proxy
# Cài đặt thư mục proxy biệt lập để tránh xung đột node_modules
RUN npm init -y && npm install http-proxy

RUN printf 'const http = require("http");\n\
const HttpProxy = require("http-proxy");\n\
\n\
const proxy = HttpProxy.createProxyServer({\n\
    target: "http://127.0.0.1:10000",\n\
    ws: true,\n\
    changeOrigin: true\n\
});\n\
\n\
// Định nghĩa danh sách các cổng cố định (Bắt theo tiền tố đường dẫn)\n\
const routes = {\n\
    "/terminal": 8082,\n\
    "/ttyd": 7681,\n\
    "/tmux": 8081,\n\
    "/openclaw": 18789,\n\
    "/meiai": 5001,\n\
    "/10000": 10000\n\
};\n\
\n\
// Hàm tìm kiếm cổng phù hợp dựa trên URL\n\
function getTargetPort(url) {\n\
    // Kiểm tra các định tuyến tĩnh\n\
    for (const prefix in routes) {\n\
        if (url.startsWith(prefix + "/") || url === prefix) {\n\
            return { port: routes[prefix], prefix: prefix };\n\
        }\n\
    }\n\
    // Kiểm tra dải cổng động: /8083 đến /8089 và /10001 đến /10003\n\
    const dynamicMatch = url.match(/^\\/((?:808[3-9])|(?:1000[1-3]))(?:\\/|$)/);\n\
    if (dynamicMatch) {\n\
        const port = parseInt(dynamicMatch[1]);\n\
        return { port: port, prefix: "/" + port };\n\
    }\n\
    return null;\n\
}\n\
\n\
// 1. Xử lý Request HTTP thường (Sửa lỗi 404 file tĩnh)\n\
const server = http.createServer((req, res) => {\n\
    const targetInfo = getTargetPort(req.url);\n\
    \n\
    if (targetInfo) {\n\
        // Nếu là route đặc biệt /10000 thì cần strip_prefix giống Caddy\n\
        if (targetInfo.prefix === "/10000") {\n\
            req.url = req.url.substring(6) || "/";\n\
        }\n\
        proxy.web(req, res, { target: `http://127.0.0.1:${targetInfo.port}` });\n\
    } else {\n\
        // Mặc định đẩy về cổng 10000 và xóa tiền tố /10000 nếu có gõ nhầm\n\
        if (req.url.startsWith("/10000")) {\n\
            req.url = req.url.substring(6) || "/";\n\
        }\n\
        proxy.web(req, res, { target: "http://127.0.0.1:10000" });\n\
    }\n\
});\n\
\n\
// 2. Xử lý nâng cấp giao thức WebSocket (Sửa lỗi ttyd/tmux kết nối)\n\
server.on("upgrade", (req, socket, head) => {\n\
    const targetInfo = getTargetPort(req.url);\n\
    if (targetInfo) {\n\
        if (targetInfo.prefix === "/10000") {\n\
            req.url = req.url.substring(6) || "/";\n\
        }\n\
        proxy.ws(req, socket, head, { target: `http://127.0.0.1:${targetInfo.port}` });\n\
    } else {\n\
        proxy.ws(req, socket, head, { target: "http://127.0.0.1:10000" });\n\
    }\n\
});\n\
\n\
// Bắt lỗi tránh crash proxy\n\
proxy.on("error", (err, req, res) => {\n\
    if (res && !res.headersSent) {\n\
        res.writeHead(502, { "Content-Type": "text/plain" });\n\
        res.end("Bad Gateway: Connection Refused");\n\
    }\n\
});\n\
\n\
server.listen(8080, "0.0.0.0", () => {\n\
    console.log("🚀 Node.js Smart Proxy đang chạy tại port 8080");\n\
});\n' > proxy.js

# ─── 7. Script khởi chạy toàn bộ hệ thống (/run.sh) ─────────────────────
WORKDIR /
RUN printf '#!/bin/bash\n\
echo "Đang khởi động dịch vụ Cloud Dev..."\n\
\n\
nohup /usr/local/bin/mem_guard.sh > /dev/null 2>&1 &\n\
\n\
(\n\
while true\n\
do\n\
    pgrep -f start-meiai.sh >/dev/null || nohup /MeiAI/start-meiai.sh > /dev/null 2>&1 &\n\
    sleep 60\n\
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
