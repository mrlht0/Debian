FROM n8nio/n8n:2.22.4

ENV N8N_PORT=8080 \
    N8N_LISTEN_ADDRESS=0.0.0.0 \
    N8N_HIRING_BANNER=false \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_RUNNERS_ENABLED=false \
    N8N_COMMUNITY_PACKAGES_ENABLED=false \
    EXECUTIONS_DATA_SAVE_ON_SUCCESS=none \
    EXECUTIONS_DATA_SAVE_ON_ERROR=none \
    EXECUTIONS_DATA_SAVE_ON_PROGRESS=false \
    NODES_EXCLUDE=["n8n-nodes-base.aws*","n8n-nodes-base.google*","n8n-nodes-base.microsoft*","n8n-nodes-base.hubspot*","n8n-nodes-base.salesforce*","n8n-nodes-base.stripe*","n8n-nodes-base.jira*"]

EXPOSE 8080
