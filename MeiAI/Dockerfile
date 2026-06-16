FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# =====================================================

# Base Packages

# =====================================================

RUN apt-get update && apt-get install -y 
bash curl wget git nano 
procps htop tmux 
ca-certificates 
tar net-tools openssh-client 
&& rm -rf /var/lib/apt/lists/*

# =====================================================

# NodeJS 22 LTS

# =====================================================

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 
&& apt-get install -y nodejs

# =====================================================

# Go 1.26

# =====================================================

RUN wget -q https://go.dev/dl/go1.26.0.linux-amd64.tar.gz 
&& rm -rf /usr/local/go 
&& tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz 
&& rm go1.26.0.linux-amd64.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# =====================================================

# ttyd

# =====================================================

RUN wget -O /usr/local/bin/ttyd 
https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 
&& chmod +x /usr/local/bin/ttyd

# =====================================================

# Clone DS2API

# =====================================================

WORKDIR /

RUN git clone https://github.com/mrlht0/ds2api.git /ds2api

WORKDIR /ds2api

# =====================================================

# Build WebUI

# =====================================================

RUN npm ci --prefix webui
RUN npm run build --prefix webui

# =====================================================

# Config

# =====================================================

RUN cp config.example.json config.json

# =====================================================

# Build Backend

# =====================================================

RUN go mod download

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 
go build -ldflags="-s -w" 
-o ds2api ./cmd/ds2api

RUN chmod +x ds2api

ENV PORT=5001
ENV DS2API_ADMIN_KEY=admin

# =====================================================

# tmux

# =====================================================

RUN printf "set -g mouse on\n
set -g history-limit 10000\n
" > /root/.tmux.conf

RUN printf '#!/bin/bash\n
SESSION=main\n
tmux has-session -t $SESSION 2>/dev/null\n
if [ $? != 0 ]; then\n
tmux new-session -d -s $SESSION\n
fi\n
exec tmux attach -t $SESSION\n
' > /start.sh && chmod +x /start.sh

# =====================================================

# DS2API watchdog

# =====================================================

RUN printf '#!/bin/bash\n
cd /ds2api\n
while true\n
do\n
./ds2api\n
sleep 5\n
done\n
' > /ds2api/run-ds2api.sh 
&& chmod +x /ds2api/run-ds2api.sh

# =====================================================

# Node Proxy

# =====================================================

WORKDIR /proxy

RUN npm init -y
RUN npm install http-proxy

RUN printf 'const http=require("http");\n
const proxy=require("http-proxy").createProxyServer({ws:true});\n
\n
const routes={\n
"/tmux":8081,\n
"/terminal":8082,\n
"/ds2api":5001\n
};\n
\n
const server=http.createServer((req,res)=>{\n
for(const p in routes){\n
if(req.url.startsWith(p)){\n
proxy.web(req,res,{target:`http://127.0.0.1:${routes[p]}`});\n
return;\n
}\n
}\n
proxy.web(req,res,{target:"[http://127.0.0.1:5001"});\n\](http://127.0.0.1:5001%22}%29;\n\)
});\n
\n
server.on("upgrade",(req,socket,head)=>{\n
for(const p in routes){\n
if(req.url.startsWith(p)){\n
proxy.ws(req,socket,head,{target:`http://127.0.0.1:${routes[p]}`});\n
return;\n
}\n
}\n
});\n
\n
server.listen(8080,"0.0.0.0");\n' > proxy.js

# =====================================================

# Startup

# =====================================================

WORKDIR /

RUN printf '#!/bin/bash\n
/ds2api/run-ds2api.sh &\n
ttyd -p 8081 -W -b /tmux /start.sh &\n
ttyd -p 8082 -W -b /terminal bash &\n
exec node /proxy/proxy.js\n
' > /run.sh && chmod +x /run.sh

EXPOSE 8080

CMD ["/run.sh"]
