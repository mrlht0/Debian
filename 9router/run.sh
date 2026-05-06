#!/bin/bash
echo "🚀 Starting $APP_NAME..."

cd /root

# 🖥 Terminal
echo "🖥 Starting ttyd..."
ttyd -p 8082 -W -b /terminal bash &

# ⏳ đợi service gốc boot
sleep 3

# 🔍 detect port thật (loại ttyd)
APP_PORT=$(netstat -tulnp 2>/dev/null \
  | grep LISTEN \
  | awk '{print $4}' \
  | awk -F: '{print $NF}' \
  | grep -v 8082 \
  | sort -n \
  | uniq \
  | head -n 1)

# fallback nếu không tìm được
APP_PORT=${APP_PORT:-8082}

echo "🔥 Detected APP_PORT=$APP_PORT"

export APP_PORT

# 🎨 log đẹp
echo "=============================="
echo " APP:       http://localhost:$APP_PORT"
echo " TERMINAL:  /terminal"
echo " OPENCLAW:  /openclaw (nếu có)"
echo "=============================="

# 🚀 start gateway
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
