# FROM debian:bookworm-slim

# ENV DEBIAN_FRONTEND=noninteractive
# ENV PORT=8080
# ENV PASSWORD=123456

# # ─── Install base ─────────────────────────────────────────
# RUN apt-get update && apt-get install -y \
#     curl wget git bash nano \
#     procps htop \
#     ca-certificates \
#     build-essential \
#     python3 python3-pip \
#     && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
#     && apt-get install -y nodejs \
#     && apt-get clean && rm -rf /var/lib/apt/lists/*

# # ─── Install ttyd ─────────────────────────────────────────
# RUN wget -O /usr/local/bin/ttyd \
#     https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
#     chmod +x /usr/local/bin/ttyd

# # ─── Workspace ────────────────────────────────────────────
# WORKDIR /workspace

# # ─── Đổi user ────────────────────────────────────────────
# RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# # ─── Start script ─────────────────────────────────────────
# RUN printf '#!/bin/bash\n\
# echo "Starting ttyd on port $PORT"\n\
# exec ttyd -p $PORT -c :$PASSWORD -W bash\n\
# ' > /start.sh && chmod +x /start.sh

# EXPOSE 8080

# CMD ["/start.sh"]

# =============================================================
# Hai user
# ============================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=8080

# ─── Install base ─────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git bash nano \
    procps htop \
    ca-certificates \
    build-essential \
    python3 python3-pip \
    && curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── Install ttyd ─────────────────────────────────────────
RUN wget -O /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd

# ─── Users ────────────────────────────────────────────────
RUN useradd -m admin && echo "admin:admin123" | chpasswd
RUN useradd -m test && echo "test:123" | chpasswd

# ─── Workspace ────────────────────────────────────────────
RUN mkdir -p /workspace/test && \
    chown -R test:test /workspace/test

WORKDIR /workspace

# ─── Prompt gọn ───────────────────────────────────────────
RUN echo 'export PS1="\u@debian:\w# "' >> /root/.bashrc

# ─── Giới hạn user test ───────────────────────────────────
RUN printf 'cd /workspace/test\n\
export TMOUT=900\n\
alias cd="echo blocked"\n\
alias rm="echo blocked"\n\
alias shutdown="echo blocked"\n\
alias reboot="echo blocked"\n\
' > /home/test/.bashrc && chown test:test /home/test/.bashrc

# ─── Start script ─────────────────────────────────────────
RUN printf '#!/bin/bash\n\
echo "Starting ttyd..."\n\
echo "Admin: /admin | Test: /test"\n\
\n\
# admin (full quyền)\n\
ttyd -p 8081 -c admin:admin123 -W bash &\n\
\n\
# test (bị giới hạn)\n\
ttyd -p 8082 -c test:123 -W su - test &\n\
\n\
# giữ container sống\n\
wait\n\
' > /start.sh && chmod +x /start.sh

EXPOSE 8081 8082

CMD ["/start.sh"]
