# Debian
# Chạy lại (reload) caddy
caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

# RAM
watch -n 1 cat /workspace/mem.log
### hoặc
tmux new -s mem
/usr/local/bin/mem_guard.sh

# cài đặt nhẹ
npm install --no-audit --no-fund --prefer-offline --maxsockets=1

# các phím tắt tmux
## 🧠 ⚡ Prefix (phím mở đầu)
tmux set -g mouse off
Mặc định:

Ctrl + b

👉 mọi lệnh tmux đều bắt đầu bằng cái này

## 🪟 📦 QUẢN LÝ PANEL (chia màn hình)
➜ chia ngang
Ctrl + b  "
➜ chia dọc
Ctrl + b  %
➜ di chuyển giữa pane
Ctrl + b  ← ↑ ↓ →

👉 hoặc:

Ctrl + b  o
➜ phóng to pane hiện tại
Ctrl + b  z
➜ đóng pane
Ctrl + b  x
## 🧱 🪟 WINDOW (tab)
➜ tạo tab mới
Ctrl + b  c
➜ chuyển tab
Ctrl + b  n   # next
Ctrl + b  p   # previous
➜ chọn tab theo số
Ctrl + b  0 → 9
➜ rename tab
Ctrl + b  ,
## 🔁 🔄 SESSION (rất quan trọng)
➜ detach (thoát mà không tắt)
Ctrl + b  d
➜ attach lại
tmux attach
➜ list session
tmux ls
## 🖱️ 🧲 COPY / SCROLL (quan trọng với bạn)
➜ vào chế độ scroll
Ctrl + b  [

👉 sau đó:

cuộn: ↑ ↓
thoát: q
➜ copy (không dùng chuột)
Ctrl + b  [

rồi:

Space → chọn
Enter → copy
➜ paste
Ctrl + b  ]
