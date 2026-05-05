# FROM antiantiops/9router:0.3.69

# # Render sẽ dùng port này
# ENV PORT=20128

# # đảm bảo bind ra ngoài
# EXPOSE 20128

# # nếu image chưa có CMD rõ ràng thì fallback
# CMD ["bun", "server.js"]

# Sử dụng image gốc bạn đã chọn
FROM antiantiops/9router:0.3.69

ENV PORT=8080
WORKDIR /workspace

# 1. Cài đặt ttyd (Terminal qua Web)
RUN wget -qO /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# 2. Cài đặt Caddy (Gateway để gộp cổng)
RUN wget -qO /usr/local/bin/caddy \
    https://github.com/caddyserver/caddy/releases/latest/download/caddy_2.8.4_linux_amd64 \
    && chmod +x /usr/local/bin/caddy

# 3. Tạo cấu hình Caddyfile để sửa lỗi Redirect và API
RUN mkdir -p /etc/caddy && cat <<EOF > /etc/caddy/Caddyfile
:8080 {
    # Cấu hình cho Web Terminal
    handle /terminal* {
        reverse_proxy localhost:7681
    }

    # Cấu hình cho ứng dụng chính và API
    handle /* {
        reverse_proxy localhost:20128 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            # Sửa lỗi redirect mất tiền tố /9router nếu có
            header_down Location ^/ /9router/
        }
    }
}
EOF

# 4. Tạo file start.sh tối ưu RAM 512MB
RUN cat <<'EOF' > /start.sh
#!/bin/sh

echo "--- Đang khởi động các dịch vụ (Giới hạn RAM 512MB) ---"

# Giới hạn bộ nhớ cho tiến trình JavaScript để tránh bị hệ thống Kill (OOM)
export NODE_OPTIONS="--max-old-space-size=256"

# Khởi động ứng dụng chính (Dùng bun hoặc node tùy thuộc image gốc)
# Chúng ta chạy ngầm bằng dấu &
bun server.js &

# Khởi động Terminal (Chỉ chạy 1 cái để tiết kiệm RAM)
ttyd -p 7681 -W bash &

echo "--- Gateway Caddy đang chạy tại cổng 8080 ---"
# Caddy chạy ở tiến trình chính (foreground) để giữ container không bị tắt
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
EOF

RUN chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
