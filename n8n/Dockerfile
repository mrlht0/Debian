# syntax=docker/dockerfile:1

# Base image:
# n8n is already included here, so there is no custom proxy layer and no extra install step.
FROM n8nio/n8n:2.22.4

# Keep n8n small and predictable:
# - run everything in the main process
# - do not load community packages
# - disable verbose save behavior
# - make the webhook prefix stable
ENV N8N_HIRING_BANNER=false \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_RUNNERS_ENABLED=false \
    N8N_COMMUNITY_PACKAGES_ENABLED=false \
    EXECUTIONS_PROCESS=main \
    EXECUTIONS_DATA_SAVE_ON_SUCCESS=none \
    EXECUTIONS_DATA_SAVE_ON_ERROR=none \
    EXECUTIONS_DATA_SAVE_ON_PROGRESS=false \
    N8N_ENDPOINT_WEBHOOK=ram

# All runtime files stay under /home/node so the official image can run normally.
WORKDIR /home/node

# Write a single workflow file into the image.
# This workflow exposes one webhook and returns RAM stats from the host/container.
RUN cat <<'EOF' > /tmp/ram.workflow.json
{
  "name": "RAM Monitor",
  "nodes": [
    {
      "parameters": {
        "path": "",
        "httpMethod": "GET",
        "responseMode": "responseNode"
      },
      "id": "Webhook",
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2.1,
      "position": [260, 300]
    },
    {
      "parameters": {
        "executeOnce": true,
        "command": "node -e \"const os=require('os');const total=os.totalmem();const free=os.freemem();const used=total-free;const mem=process.memoryUsage();const stats={cpu:{loadAverage:os.loadavg().map(v=>v.toFixed(2)),coresCount:os.cpus().length},os:{total:(total/1024/1024/1024).toFixed(2)+' GB',free:(free/1024/1024/1024).toFixed(2)+' GB',used:(used/1024/1024/1024).toFixed(2)+' GB',usedPercentage:((used/total)*100).toFixed(2)+'%'},node:{heapTotal:(mem.heapTotal/1024/1024).toFixed(2)+' MB',heapUsed:(mem.heapUsed/1024/1024).toFixed(2)+' MB',rss:(mem.rss/1024/1024).toFixed(2)+' MB'},timestamp:new Date().toISOString()};console.log(JSON.stringify(stats,null,2))\""
      },
      "id": "ExecuteCommand",
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
      "id": "RespondToWebhook",
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

# Import the workflow once. If the container restarts, the marker prevents duplicates.
RUN mkdir -p /home/node/.n8n
RUN printf '%s\n' '#!/bin/sh' \
    'set -eu' \
    'export N8N_PORT="${PORT:-8080}"' \
    'export N8N_LISTEN_ADDRESS=0.0.0.0' \
    'if [ ! -f /home/node/.n8n/.ram-workflow-imported ]; then' \
    '  n8n import:workflow --input=/tmp/ram.workflow.json --activeState=fromJson >/tmp/ram-import.log 2>&1' \
    '  touch /home/node/.n8n/.ram-workflow-imported' \
    'fi' \
    'exec n8n start' \
    > /home/node/start-n8n.sh && chmod +x /home/node/start-n8n.sh

# Only one public port exists; Render will map its PORT to this container.
EXPOSE 8080

# Run the direct n8n server. No proxy layer means no proxy-related browser warning.
CMD ["/home/node/start-n8n.sh"]
