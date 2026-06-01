# syntax=docker/dockerfile:1

FROM node:22.16-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    N8N_PORT=8080 \
    N8N_LISTEN_ADDRESS=0.0.0.0 \
    N8N_HIRING_BANNER=false \
    N8N_DIAGNOSTICS_ENABLED=false

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY . .

EXPOSE 8080

ENTRYPOINT ["tini", "--"]
CMD ["npm", "start"]
