# syntax=docker/dockerfile:1

# Base image:
# n8n is already installed here, so we do not waste RAM/time reinstalling it.
FROM n8nio/n8n:2.22.4

# Runtime defaults:
# - n8n listens on 5678 internally
# - our public entrypoint will listen on $PORT or 8080
# - heavy features are disabled to keep the footprint low
ENV N8N_PORT=5678 \
    N8N_LISTEN_ADDRESS=127.0.0.1 \
    N8N_HIRING_BANNER=false \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_RUNNERS_ENABLED=false \
    N8N_COMMUNITY_PACKAGES_ENABLED=false \
    EXECUTIONS_PROCESS=main \
    EXECUTIONS_DATA_SAVE_ON_SUCCESS=none \
    EXECUTIONS_DATA_SAVE_ON_ERROR=none \
    EXECUTIONS_DATA_SAVE_ON_PROGRESS=false \
    NODES_EXCLUDE=["n8n-nodes-base.aws*","n8n-nodes-base.google*","n8n-nodes-base.microsoft*","n8n-nodes-base.hubspot*","n8n-nodes-base.salesforce*","n8n-nodes-base.stripe*","n8n-nodes-base.jira*"]

# Work in /app so the runtime files stay in one predictable place.
WORKDIR /app

# The base n8n image is hardened. It does not ship with apt-get, so we avoid
# OS-level package installs here and keep the runtime dependent only on Node.
USER root

# Install only the two runtime libraries we need for the public wrapper:
# - http-proxy: forward every non-/ram request to n8n
# - mongoose: optional cost history persistence when MONGODB_URI is present
RUN npm init -y >/dev/null 2>&1 \
    && npm install --no-package-lock --no-save --no-audit --no-fund http-proxy mongoose

# Write the whole runtime into one JS file so the image stays single-file in practice.
RUN cat <<'EOF' > /app/server.js
'use strict';

const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const { execSync, spawn } = require('node:child_process');
const httpProxy = require('http-proxy');

// Public port:
// - Render sets PORT automatically.
// - Local docker run can map 8080:8080 and still work.
const PUBLIC_PORT = Number(process.env.PORT || 8080);

// Internal n8n port:
// - the real n8n server stays on localhost only
// - the wrapper below is the only public listener
const INTERNAL_N8N_PORT = Number(process.env.N8N_PORT || 5678);

// RAM endpoint protection:
// - query string:  /ram?token=...
// - header:        x-ram-token: ...
const RAM_TOKEN = process.env.RAM_TOKEN || 'cliply_ram_secret_token_2026';

// Optional database for cost history.
// If MONGODB_URI is missing, the RAM endpoint still works.
const TARGET_DB_NAME = 'application-manager';
const MONGODB_URI = process.env.MONGODB_URI || '';

// Keep mongoose lazy so the process does not pay the cost unless Mongo is configured.
let mongoose = null;
let CostHistory = null;

function loadMongoose() {
  if (mongoose) return mongoose;

  mongoose = require('mongoose');

  // Store one monthly row per month.
  const CostHistorySchema = new mongoose.Schema(
    {
      month: { type: String, required: true, unique: true },
      accumulatedMemoryMinutes: { type: Number, default: 0 },
      accumulatedCpuMinutes: { type: Number, default: 0 },
      accumulatedEgressBytes: { type: Number, default: 0 },
      lastTxBytes: { type: Number, default: 0 },
      lastMeasurementTime: { type: Date, default: Date.now },
      memoryCost: { type: Number, default: 0 },
      cpuCost: { type: Number, default: 0 },
      egressCost: { type: Number, default: 0 },
      totalCost: { type: Number, default: 0 },
    },
    { timestamps: true },
  );

  CostHistory = mongoose.models.CostHistory || mongoose.model('CostHistory', CostHistorySchema);
  return mongoose;
}

async function connectToMongo() {
  if (!MONGODB_URI) return false;

  const lib = loadMongoose();
  if (lib.connection.readyState >= 1) return true;

  // Force the target database name while preserving query parameters.
  let targetUri = MONGODB_URI;
  try {
    const url = new URL(MONGODB_URI);
    url.pathname = `/${TARGET_DB_NAME}`;
    targetUri = url.toString();
  } catch {
    const base = MONGODB_URI.split('?')[0].replace(/\/+$/, '');
    const query = MONGODB_URI.split('?')[1] || 'retryWrites=true&w=majority';
    targetUri = `${base}/${TARGET_DB_NAME}?${query}`;
  }

  await lib.connect(targetUri);
  return true;
}

function toMB(bytes) {
  return (bytes / 1024 / 1024).toFixed(2);
}

function toGB(bytes) {
  return (bytes / 1024 / 1024 / 1024).toFixed(2);
}

function readTailLines(filePath, count = 5) {
  try {
    if (!fs.existsSync(filePath)) return [];
    const lines = fs.readFileSync(filePath, 'utf8').trim().split(/\r?\n/);
    return lines.slice(-count).filter(Boolean);
  } catch {
    return [];
  }
}

function safeExec(command) {
  try {
    return execSync(command, { stdio: ['ignore', 'pipe', 'pipe'] }).toString().trim();
  } catch {
    return '';
  }
}

async function measureCpuPercent() {
  // Sample twice so we can estimate CPU usage over a short interval.
  const startCpu = os.cpus();
  const startUsage = process.cpuUsage();
  const hrStart = process.hrtime();

  await new Promise((resolve) => setTimeout(resolve, 100));

  const endCpu = os.cpus();
  const endUsage = process.cpuUsage(startUsage);
  const hrEnd = process.hrtime();

  const elapsedNs = hrEnd[0] * 1e9 + hrEnd[1] - (hrStart[0] * 1e9 + hrStart[1]);
  const elapsedMs = elapsedNs / 1e6;
  const userMs = endUsage.user / 1000;
  const systemMs = endUsage.system / 1000;
  const cpuPercentNode = elapsedMs > 0 ? (((userMs + systemMs) / elapsedMs) * 100).toFixed(2) : '0.00';

  let totalDiff = 0;
  let idleDiff = 0;
  for (let i = 0; i < startCpu.length; i++) {
    const start = startCpu[i].times;
    const end = endCpu[i].times;
    const startTotal = start.user + start.nice + start.sys + start.idle + start.irq;
    const endTotal = end.user + end.nice + end.sys + end.idle + end.irq;
    totalDiff += endTotal - startTotal;
    idleDiff += end.idle - start.idle;
  }

  const cpuPercentSystem = totalDiff > 0 ? ((1 - idleDiff / totalDiff) * 100).toFixed(2) : '0.00';

  return {
    nodeProcess: `${cpuPercentNode}%`,
    systemTotal: `${cpuPercentSystem}%`,
    coresCount: startCpu.length,
    loadAverage: os.loadavg().map((value) => value.toFixed(2)),
  };
}

async function buildMonitorStats() {
  const totalMemBytes = os.totalmem();
  const freeMemBytes = os.freemem();
  const usedMemBytes = totalMemBytes - freeMemBytes;
  const cpu = await measureCpuPercent();
  const rssBytes = process.memoryUsage().rss;

  const stats = {
    cpu,
    os: {
      total: `${toGB(totalMemBytes)} GB`,
      free: `${toGB(freeMemBytes)} GB`,
      used: `${toGB(usedMemBytes)} GB`,
      usedPercentage: `${((usedMemBytes / totalMemBytes) * 100).toFixed(2)}%`,
    },
    node: {
      heapTotal: `${toMB(process.memoryUsage().heapTotal)} MB`,
      heapUsed: `${toMB(process.memoryUsage().heapUsed)} MB`,
      rss: `${toMB(rssBytes)} MB`,
    },
    timestamp: new Date().toISOString(),
  };

  // If the `ram` command exists, include it as a quick human-readable mirror.
  const ramOutput = safeExec('ram');
  if (ramOutput) {
    stats.ramCommandOutput = ramOutput;
  }

  return { stats, rssBytes };
}

async function updateCostHistory(rssBytes) {
  if (!MONGODB_URI) {
    return {
      currentMonth: null,
      last5MonthsHistory: [],
      disabled: true,
    };
  }

  await connectToMongo();

  const now = new Date();
  const currentMonthStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

  let currentTxBytes = 0;
  if (process.platform === 'linux') {
    try {
      const txPath = '/sys/class/net/eth0/statistics/tx_bytes';
      if (fs.existsSync(txPath)) {
        currentTxBytes = parseInt(fs.readFileSync(txPath, 'utf8').trim(), 10);
      }
    } catch {
      currentTxBytes = 0;
    }
  }

  let record = await CostHistory.findOne({ month: currentMonthStr });
  if (!record) {
    record = new CostHistory({
      month: currentMonthStr,
      lastMeasurementTime: now,
      lastTxBytes: currentTxBytes,
    });
  }

  const lastTime = new Date(record.lastMeasurementTime);
  const minutesElapsed = (now.getTime() - lastTime.getTime()) / 60000;

  // Avoid writing on every single request; keep the update cadence relaxed.
  if (minutesElapsed > 0.01) {
    const currentRssGB = rssBytes / (1024 * 1024 * 1024);
    const deltaMemoryMinutes = currentRssGB * minutesElapsed;

    // Treat the container as a 0.1 vCPU baseline to approximate the old Render model.
    const allocatedCpu = 0.1;
    const deltaCpuMinutes = allocatedCpu * minutesElapsed;

    let deltaEgressBytes = 0;
    if (currentTxBytes > 0 && record.lastTxBytes > 0 && currentTxBytes >= record.lastTxBytes) {
      deltaEgressBytes = currentTxBytes - record.lastTxBytes;
    }

    record.accumulatedMemoryMinutes += deltaMemoryMinutes;
    record.accumulatedCpuMinutes += deltaCpuMinutes;
    record.accumulatedEgressBytes += deltaEgressBytes;
    record.lastTxBytes = currentTxBytes > 0 ? currentTxBytes : record.lastTxBytes;
    record.lastMeasurementTime = now;

    // Keep the same pricing shape as the source snippet, including the x2 factor.
    const MEMORY_PRICE_PER_GB_MIN_X2 = 0.000231 * 2;
    const CPU_PRICE_PER_VCPU_MIN_X2 = 0.000463 * 2;
    const EGRESS_PRICE_PER_GB_X2 = 0.05 * 2;

    record.memoryCost = record.accumulatedMemoryMinutes * MEMORY_PRICE_PER_GB_MIN_X2;
    record.cpuCost = record.accumulatedCpuMinutes * CPU_PRICE_PER_VCPU_MIN_X2;
    record.egressCost = (record.accumulatedEgressBytes / (1024 * 1024 * 1024)) * EGRESS_PRICE_PER_GB_X2;
    record.totalCost = record.memoryCost + record.cpuCost + record.egressCost;

    await record.save();
  }

  const currentCost = {
    month: record.month,
    accumulatedMemoryGBMinutes: record.accumulatedMemoryMinutes.toFixed(2),
    accumulatedCpuVCPUMinutes: record.accumulatedCpuMinutes.toFixed(2),
    accumulatedEgressGB: (record.accumulatedEgressBytes / (1024 * 1024 * 1024)).toFixed(4),
    memoryCost: `$${record.memoryCost.toFixed(4)}`,
    cpuCost: `$${record.cpuCost.toFixed(4)}`,
    egressCost: `$${record.egressCost.toFixed(4)}`,
    totalCost: `$${record.totalCost.toFixed(4)}`,
  };

  const history = await CostHistory.find({}).sort({ month: -1 }).limit(5);
  const last5MonthsHistory = history.map((item) => ({
    month: item.month,
    memoryCost: `$${item.memoryCost.toFixed(4)}`,
    cpuCost: `$${item.cpuCost.toFixed(4)}`,
    egressCost: `$${item.egressCost.toFixed(4)}`,
    totalCost: `$${item.totalCost.toFixed(4)}`,
  }));

  return {
    currentMonth: currentCost,
    last5MonthsHistory,
  };
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload, null, 2));
}

function sendText(res, statusCode, text) {
  res.writeHead(statusCode, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(text);
}

// Start n8n as a child process on localhost only.
// This keeps the public wrapper in full control of the exposed port.
function startN8n() {
  const env = {
    ...process.env,
    N8N_PORT: String(INTERNAL_N8N_PORT),
    N8N_LISTEN_ADDRESS: '127.0.0.1',
  };

  const child = spawn('n8n', ['start'], {
    stdio: 'inherit',
    env,
  });

  child.on('exit', (code, signal) => {
    if (signal) process.exit(1);
    process.exit(code ?? 0);
  });

  return child;
}

async function handleRamRequest(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  const token = url.searchParams.get('token') || req.headers['x-ram-token'];

  if (token !== RAM_TOKEN) {
    sendJson(res, 401, { error: 'Unauthorized' });
    return;
  }

  const { stats, rssBytes } = await buildMonitorStats();
  const projectCost = await updateCostHistory(rssBytes);

  sendJson(res, 200, {
    ...stats,
    projectCost,
  });
}

// This proxy keeps one public URL while forwarding everything except /ram to n8n.
const proxy = httpProxy.createProxyServer({
  target: `http://127.0.0.1:${INTERNAL_N8N_PORT}`,
  ws: true,
  xfwd: true,
});

proxy.on('error', (err, req, res) => {
  if (res && !res.headersSent) {
    sendText(res, 502, `Proxy error: ${err.message}`);
  }
});

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  if (url.pathname === '/ram') {
    await handleRamRequest(req, res);
    return;
  }

  proxy.web(req, res);
});

server.on('upgrade', (req, socket, head) => {
  proxy.ws(req, socket, head);
});

// Clean shutdown so Render or Docker stops do not leave a zombie child process behind.
let n8nChild = null;

function shutdown(exitCode) {
  try {
    server.close();
  } catch {}

  if (n8nChild && !n8nChild.killed) {
    n8nChild.kill('SIGTERM');
  }

  process.exit(exitCode);
}

process.on('SIGTERM', () => shutdown(0));
process.on('SIGINT', () => shutdown(0));

// Bring everything up in the right order:
// 1) n8n backend
// 2) public proxy + /ram endpoint
n8nChild = startN8n();
server.listen(PUBLIC_PORT, '0.0.0.0', () => {
  console.log(`Public wrapper listening on 0.0.0.0:${PUBLIC_PORT}`);
});
EOF

# Runtime files are owned by the non-root n8n user so the container can run safely.
RUN chown -R node:node /app /home/node

# Drop privileges before runtime.
USER node

# Only one public port exists.
EXPOSE 8080

# The wrapper starts n8n internally and exposes the single public port.
ENTRYPOINT ["node", "/app/server.js"]
