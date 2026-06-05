# syntax=docker/dockerfile:1
FROM n8nio/n8n:2.22.4

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
  NODE_FUNCTION_ALLOW_EXTERNAL=mongodb \
  NODE_FUNCTION_ALLOW_BUILTIN=* \
  NODE_FUNCTION_ALLOW_EXTERNAL=* \
  NODE_FUNCTION_ALLOW_EXTERNAL=playwright \
  NODES_EXCLUDE=["n8n-nodes-base.aws*","n8n-nodes-base.google*","n8n-nodes-base.microsoft*","n8n-nodes-base.hubspot*","n8n-nodes-base.salesforce*","n8n-nodes-base.stripe*","n8n-nodes-base.jira*"]

WORKDIR /app
USER root

RUN npm init -y >/dev/null 2>&1 \
  && npm install --no-package-lock --no-save --no-audit --no-fund http-proxy mongoose mongodb

RUN cat <<'EOF' > /app/server.js
'use strict';
const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { execSync, spawn } = require('node:child_process');
const httpProxy = require('http-proxy');

const PUBLIC_PORT = Number(process.env.PORT || 8080);
const INTERNAL_N8N_PORT = Number(process.env.N8N_PORT || 5678);

const RAM_TOKEN = process.env.RAM_TOKEN || '';
const MONGODB_URI = process.env.MONGODB_URI || '';
const TARGET_DB = process.env.TARGET_DB || 'application-manager';

let mongoose = null;
let CostHistory = null;

function getProjectName() {
  try {
    const host = os.hostname();
    const renderHostMatch = host.match(/^(srv-[a-z0-9]+)/);
    if (renderHostMatch) return renderHostMatch[1];
    if (process.env.MACHINE_ID) return process.env.MACHINE_ID;
    const genericHosts = ['localhost', '127.0.0.1', 'desktop', 'laptop', 'server'];
    const isGeneric = genericHosts.some((g) => host.toLowerCase().includes(g)) || host.length < 3;
    if (isGeneric) {
      let packageJsonName = 'unknown';
      try {
        const packageJsonPath = path.join(process.cwd(), 'package.json');
        if (fs.existsSync(packageJsonPath)) {
          const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
          packageJsonName = packageJson.name || 'unknown';
        }
      } catch {}
      const ips = Object.values(os.networkInterfaces()).flat().filter((f) => f && !f.internal && f.family === 'IPv4').map((f) => f.address).join('_');
      return `${host}_${packageJsonName}_${ips || 'noip'}`;
    }
    return host;
  } catch {
    return process.env.MACHINE_ID || os.hostname() || 'unknown';
  }
}

function loadMongoose() {
  if (mongoose) return mongoose;
  mongoose = require('mongoose');
  const schema = new mongoose.Schema(
    {
      month: { type: String, required: true },
      projectName: { type: String, required: true, default: 'unknown' },
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
    { timestamps: true }
  );
  schema.index({ month: 1, projectName: 1 }, { unique: true });
  CostHistory = mongoose.models.CostHistory || mongoose.model('CostHistory', schema);
  return mongoose;
}

async function connectToMongo() {
  if (!MONGODB_URI) return false;
  const lib = loadMongoose();
  if (lib.connection.readyState >= 1) return true;
  let uri = MONGODB_URI;
  try {
    const u = new URL(MONGODB_URI);
    u.pathname = `/${TARGET_DB}`;
    uri = u.toString();
  } catch {
    const [base, qs] = MONGODB_URI.split('?');
    uri = `${base.replace(/\/+$/, '')}/${TARGET_DB}?${qs || 'retryWrites=true&w=majority'}`;
  }
  await lib.connect(uri);
  return true;
}

async function migrateCostHistoryIndexes() {
  if (!mongoose?.connection?.db) return;
  try {
    const collection = mongoose.connection.db.collection('costhistories');
    const indexes = await collection.indexes();
    if (indexes.some((idx) => idx.name === 'month_1')) {
      await collection.dropIndex('month_1');
    }
  } catch {}
}

const toMB = (bytes) => (bytes / 1024 / 1024).toFixed(2);
const toGB = (bytes) => (bytes / 1024 / 1024 / 1024).toFixed(2);

function safeExec(cmd) {
  try { return execSync(cmd, { stdio: ['ignore', 'pipe', 'pipe'] }).toString().trim(); } catch { return ''; }
}

async function measureCpuPercent() {
  const startCpu = os.cpus(), startUsage = process.cpuUsage(), hrStart = process.hrtime();
  await new Promise((resolve) => setTimeout(resolve, 100));
  const endCpu = os.cpus(), endUsage = process.cpuUsage(startUsage), hrEnd = process.hrtime();
  const elapTimeMS = ((hrEnd[0] * 1e9 + hrEnd[1]) - (hrStart[0] * 1e9 + hrStart[1])) / 1e6;
  const cpuPercentNode = elapTimeMS > 0 ? (((endUsage.user / 1000 + endUsage.system / 1000) / elapTimeMS) * 100).toFixed(2) : '0.00';
  let totalDiff = 0, idleDiff = 0;
  for (let i = 0; i < startCpu.length; i++) {
    const s = startCpu[i].times, e = endCpu[i].times;
    totalDiff += (e.user + e.nice + e.sys + e.idle + e.irq) - (s.user + s.nice + s.sys + s.idle + s.irq);
    idleDiff += e.idle - s.idle;
  }
  return { nodeProcess: `${cpuPercentNode}%`, systemTotal: totalDiff > 0 ? ((1 - idleDiff / totalDiff) * 100).toFixed(2) : '0.00', coresCount: startCpu.length, loadAverage: os.loadavg().map((v) => v.toFixed(2)) };
}

async function buildMonitorStats() {
  const totalMem = os.totalmem(), freeMem = os.freemem(), usedMem = totalMem - freeMem, cpu = await measureCpuPercent(), mem = process.memoryUsage(), projectName = getProjectName();
  const stats = { cpu, os: { total: `${toGB(totalMem)} GB`, free: `${toGB(freeMem)} GB`, used: `${toGB(usedMem)} GB`, usedPercentage: `${((usedMem / totalMem) * 100).toFixed(2)}%` }, node: { heapTotal: `${toMB(mem.heapTotal)} MB`, heapUsed: `${toMB(mem.heapUsed)} MB`, rss: `${toMB(mem.rss)} MB` }, timestamp: new Date().toISOString() };
  if (process.platform === 'linux') {
    const freeOutput = safeExec('free -h'); if (freeOutput) stats.freeCommandOutput = freeOutput;
    const ps = safeExec('ps aux --sort=-%mem | head -n 6'); if (ps) stats.topProcesses = ps.split('\n');
    const logPaths = ['/tmp/mem_guard.log', '/var/log/mem_guard.log', './mem_guard.log'];
    for (const logPath of logPaths) {
      const logTail = safeExec(`tail -n 5 ${logPath} 2>/dev/null`);
      if (logTail) { stats.memGuardLog = { path: logPath, lines: logTail.split('\n') }; break; }
    }
  }
  stats.identity = { name: projectName, machineId: projectName, hostname: os.hostname(), platform: os.platform(), arch: os.arch(), ips: Object.values(os.networkInterfaces()).flat().filter((f) => f && !f.internal && f.family === 'IPv4').map((f) => f.address) };
  return { stats, rssBytes: mem.rss };
}

async function updateCostHistory(rssBytes) {
  if (!MONGODB_URI) return { currentMonth: null, last5MonthsHistory: [], disabled: true };
  try {
    await connectToMongo(); await migrateCostHistoryIndexes();
    const now = new Date(), currentMonthStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`, projectName = getProjectName();
    let currentTxBytes = 0;
    if (process.platform === 'linux') {
      try { const txPath = '/sys/class/net/eth0/statistics/tx_bytes'; if (fs.existsSync(txPath)) currentTxBytes = parseInt(fs.readFileSync(txPath, 'utf8').trim(), 10); } catch {}
    }
    let record = await CostHistory.findOne({ month: currentMonthStr, projectName });
    if (!record) {
      record = new CostHistory({ month: currentMonthStr, projectName, lastMeasurementTime: now, lastTxBytes: currentTxBytes });
      await record.save();
    }
    const minutesElapsed = (now.getTime() - new Date(record.lastMeasurementTime).getTime()) / 60000;
    if (minutesElapsed > 0.01) {
      record.accumulatedMemoryMinutes += (rssBytes / 1024 / 1024 / 1024) * minutesElapsed;
      const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1);
      record.accumulatedCpuMinutes += allocatedCpu * minutesElapsed;
      if (currentTxBytes > 0 && record.lastTxBytes > 0 && currentTxBytes >= record.lastTxBytes) record.accumulatedEgressBytes += (currentTxBytes - record.lastTxBytes);
      record.lastTxBytes = currentTxBytes > 0 ? currentTxBytes : record.lastTxBytes;
      record.lastMeasurementTime = now;
      record.memoryCost = record.accumulatedMemoryMinutes * 0.000462;
      record.cpuCost = record.accumulatedCpuMinutes * 0.000926;
      record.egressCost = (record.accumulatedEgressBytes / 1024 / 1024 / 1024) * 0.10;
      record.totalCost = record.memoryCost + record.cpuCost + record.egressCost;
      await record.save();
    }
    const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1), activeMinutes = allocatedCpu > 0 ? record.accumulatedCpuMinutes / allocatedCpu : 0;
    const d = Math.floor(activeMinutes / 1440), h = Math.floor((activeMinutes % 1440) / 60), m = Math.floor(activeMinutes % 60);
    const currentCost = {
      projectName: record.projectName, machineId: record.projectName, month: record.month, runningDuration: `${d}d ${h}h ${m}m`, runningDays: `${(activeMinutes / 1440).toFixed(2)} days`,
      accumulatedMemoryGBMinutes: record.accumulatedMemoryMinutes.toFixed(2), accumulatedCpuVCPUMinutes: record.accumulatedCpuMinutes.toFixed(2), accumulatedEgressGB: (record.accumulatedEgressBytes / 1024 / 1024 / 1024).toFixed(4),
      ramCost: `$${record.memoryCost.toFixed(4)}`, cpuCost: `$${record.cpuCost.toFixed(4)}`, networkCost: `$${record.egressCost.toFixed(4)}`, totalCost: `$${record.totalCost.toFixed(4)}`,
    };
    const history = await CostHistory.find({ projectName }).sort({ month: -1 }).limit(5);
    const last5MonthsHistory = history.map((hist) => {
      const hAct = allocatedCpu > 0 ? hist.accumulatedCpuMinutes / allocatedCpu : 0;
      return {
        projectName: hist.projectName, machineId: hist.projectName, month: hist.month, runningDuration: `${Math.floor(hAct / 1440)}d ${Math.floor((hAct % 1440) / 60)}h ${Math.floor(hAct % 60)}m`,
        ramCost: `$${(hist.memoryCost || 0).toFixed(4)}`, cpuCost: `$${(hist.cpuCost || 0).toFixed(4)}`, networkCost: `$${(hist.egressCost || 0).toFixed(4)}`, totalCost: `$${(hist.totalCost || 0).toFixed(4)}`,
      };
    });
    return { currentMonth: currentCost, last5MonthsHistory };
  } catch (err) { return { currentMonth: null, last5MonthsHistory: [], error: err.message }; }
}

function sendJson(res, code, payload) { res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(payload, null, 2)); }
function sendText(res, code, text) { res.writeHead(code, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end(text); }

async function handleRamRequest(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`), token = url.searchParams.get('token') || req.headers['x-ram-token'];
  if (RAM_TOKEN && token !== RAM_TOKEN) { sendJson(res, 401, { error: 'Unauthorized' }); return; }
  const { stats, rssBytes } = await buildMonitorStats();
  const projectCost = await updateCostHistory(rssBytes);
  sendJson(res, 200, { identity: stats.identity, cpu: stats.cpu, os: stats.os, node: stats.node, timestamp: stats.timestamp, ...(stats.freeCommandOutput ? { freeCommandOutput: stats.freeCommandOutput } : {}), ...(stats.topProcesses ? { topProcesses: stats.topProcesses } : {}), ...(stats.memGuardLog ? { memGuardLog: stats.memGuardLog } : {}), projectCost });
}

function startN8n() {
  const n8nEnv = { ...process.env, N8N_PORT: String(INTERNAL_N8N_PORT), N8N_LISTEN_ADDRESS: '127.0.0.1' };
  if (!n8nEnv.WEBHOOK_URL && n8nEnv.RENDER_EXTERNAL_URL) n8nEnv.WEBHOOK_URL = n8nEnv.RENDER_EXTERNAL_URL;
  const child = spawn('n8n', ['start'], { stdio: 'inherit', env: n8nEnv });
  child.on('exit', (code, signal) => { process.exit(signal ? 1 : code ?? 0); });
  return child;
}

function waitForPort(port, host, timeoutMs = 120000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    function attempt() {
      const sock = new net.Socket(); sock.setTimeout(1000);
      sock.on('connect', () => { sock.destroy(); resolve(); });
      sock.on('error', () => { sock.destroy(); if (Date.now() - start >= timeoutMs) { reject(new Error(`Timeout`)); } else { setTimeout(attempt, 500); } });
      sock.on('timeout', () => { sock.destroy(); setTimeout(attempt, 500); });
      sock.connect(port, host);
    }
    attempt();
  });
}

let n8nReady = false;
const pendingQueue = [];

// SỬA ĐỔI CHÍNH TẠI ĐÂY: Ép Proxy chuyển tiếp Host header gốc của tên miền thay vì ẩn nó đi
const proxy = httpProxy.createProxyServer({ 
  target: `http://127.0.0.1:${INTERNAL_N8N_PORT}`, 
  ws: true, 
  xfwd: true,
  changeOrigin: false // Đặt false để giữ nguyên Host của Domain gốc truyền vào n8n
});

proxy.on('error', (err, req, res) => {
  if (res && !res.headersSent) sendText(res, 502, `Proxy error: ${err.message}`);
});

proxy.on('proxyRes', (proxyRes) => {
  proxyRes.headers['x-content-type-options'] = 'nosniff';
  proxyRes.headers['x-frame-options'] = 'SAMEORIGIN';
  proxyRes.headers['x-xss-protection'] = '1; mode=block';
  proxyRes.headers['referrer-policy'] = 'strict-origin-when-cross-origin';
  proxyRes.headers['cache-control'] = proxyRes.headers['cache-control'] || 'no-store';
  proxyRes.headers['strict-transport-security'] = 'max-age=31536000; includeSubDomains';
  delete proxyRes.headers['x-powered-by']; delete proxyRes.headers['server'];
});

function applySecurityHeaders(res) {
  res.setHeader('x-content-type-options', 'nosniff'); res.setHeader('x-frame-options', 'SAMEORIGIN');
  res.setHeader('x-xss-protection', '1; mode=block'); res.setHeader('referrer-policy', 'strict-origin-when-cross-origin');
  res.setHeader('strict-transport-security', 'max-age=31536000; includeSubDomains');
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  if (url.pathname === '/ram') { await handleRamRequest(req, res); return; }
  if (!n8nReady) {
    applySecurityHeaders(res);
    const timer = setTimeout(() => { if (!res.writableEnded) sendText(res, 503, 'n8n is starting, please retry'); }, 30000);
    pendingQueue.push({ req, res, timer }); return;
  }
  proxy.web(req, res);
});

server.on('upgrade', (req, socket, head) => {
  if (!n8nReady) { socket.destroy(); return; }
  proxy.ws(req, socket, head);
});

let n8nChild = null;
function shutdown(code) {
  try { server.close(); } catch {}
  if (n8nChild && !n8nChild.killed) n8nChild.kill('SIGTERM');
  process.exit(code);
}
process.on('SIGTERM', () => shutdown(0)); process.on('SIGINT', () => shutdown(0));

(async () => {
  await new Promise((resolve) => { server.listen(PUBLIC_PORT, '0.0.0.0', () => { resolve(); }); });
  n8nChild = startN8n();
  try { await waitForPort(INTERNAL_N8N_PORT, '127.0.0.1'); } catch (err) { shutdown(1); return; }
  n8nReady = true;
  while (pendingQueue.length) {
    const { req, res, timer } = pendingQueue.shift(); clearTimeout(timer);
    if (!res.writableEnded) proxy.web(req, res);
  }
})();
EOF

RUN chown -R node:node /app /home/node
USER node
EXPOSE 8080
ENTRYPOINT ["node", "/app/server.js"]
