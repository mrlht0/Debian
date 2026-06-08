# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim

ENV N8N_PORT=5678 \
    N8N_LISTEN_ADDRESS=127.0.0.1 \
    N8N_HIRING_BANNER=false \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_RUNNERS_ENABLED=false \
    N8N_COMMUNITY_PACKAGES_ENABLED=false \
    N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
    EXECUTIONS_PROCESS=main \
    EXECUTIONS_DATA_SAVE_ON_SUCCESS=none \
    EXECUTIONS_DATA_SAVE_ON_ERROR=none \
    EXECUTIONS_DATA_SAVE_ON_PROGRESS=false \
    NODE_FUNCTION_ALLOW_EXTERNAL=mongodb,pg \
    NODE_FUNCTION_ALLOW_BUILTIN=* \
    DB_TYPE=postgresdb \
    DB_POSTGRESDB_HOST=aws-1-ap-south-1.pooler.supabase.com \
    DB_POSTGRESDB_PORT=5432 \
    DB_POSTGRESDB_DATABASE=postgres \
    DB_POSTGRESDB_USER=postgres.jiewotcsywbwiuxtpwpm \
    DB_POSTGRESDB_PASSWORD=Ty48216965@ \
    DB_POSTGRESDB_SSL_ENABLED=true \
    DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false \
    N8N_ENCRYPTION_KEY=cliply_fixed_n8n_key_2026_do_not_change_keep_same \
    RAM_TOKEN=cliply_ram_secret_token_2026

WORKDIR /app
USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      bash \
      curl \
      procps \
    && rm -rf /var/lib/apt/lists/* \
    && if ! id -u node >/dev/null 2>&1; then useradd -m -s /bin/bash node; fi \
    && npm install -g --no-audit --no-fund n8n@2.22.4 \
    && npm init -y >/dev/null 2>&1 \
    && npm install --no-package-lock --no-save --no-audit --no-fund \
      http-proxy mongoose mongodb pg

RUN cat <<'EOF' > /app/server.js
'use strict';

const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { execSync, spawn } = require('node:child_process');
const httpProxy = require('http-proxy');
const { Client: PgClient } = require('pg');

const PUBLIC_PORT = Number(process.env.PORT || 8080);
const INTERNAL_N8N_PORT = Number(process.env.N8N_PORT || 5678);
const RAM_TOKEN = process.env.RAM_TOKEN || 'cliply_ram_secret_token_2026';
const MONGODB_URI =
  process.env.MONGODB_URI ||
  'mongodb+srv://tylauj04:t482169@cluster0.ygab0.mongodb.net';
const TARGET_DB = process.env.TARGET_DB || 'application-manager';

let mongoose = null;
let CostHistory = null;
let n8nReady = false;
let n8nChild = null;
let n8nStartingPromise = null;

const pendingQueue = [];

const toMB = (bytes) => (bytes / 1024 / 1024).toFixed(2);
const toGB = (bytes) => (bytes / 1024 / 1024 / 1024).toFixed(2);

function safeExec(cmd) {
  try {
    return execSync(cmd, {
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: '/bin/bash',
    })
      .toString()
      .trim();
  } catch {
    return '';
  }
}

function sendJson(res, code, payload) {
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
  });
  res.end(JSON.stringify(payload, null, 2));
}

function sendText(res, code, text) {
  res.writeHead(code, {
    'Content-Type': 'text/plain; charset=utf-8',
  });
  res.end(text);
}

function sanitizeId(value) {
  return String(value || '')
    .trim()
    .replace(/^https?:\/\//i, '')
    .replace(/\/+$/, '')
    .replace(/[^a-zA-Z0-9_-]/g, '_');
}

function getStableMachineId() {
  if (process.env.MACHINE_ID) {
    return sanitizeId(process.env.MACHINE_ID);
  }
  if (process.env.RAILWAY_SERVICE_ID) {
    return `railway_${sanitizeId(process.env.RAILWAY_SERVICE_ID)}`;
  }
  if (process.env.RAILWAY_PROJECT_ID && process.env.RAILWAY_SERVICE_NAME) {
    return `railway_${sanitizeId(process.env.RAILWAY_PROJECT_ID)}_${sanitizeId(process.env.RAILWAY_SERVICE_NAME)}`;
  }
  if (process.env.RAILWAY_PUBLIC_DOMAIN) {
    return `railway_${sanitizeId(process.env.RAILWAY_PUBLIC_DOMAIN)}`;
  }
  return `host_${sanitizeId(os.hostname() || 'unknown')}`;
}

function getProjectName() {
  return getStableMachineId();
}

function getN8nSchemaName(machineId) {
  if (process.env.DB_POSTGRESDB_SCHEMA) {
    return sanitizeId(process.env.DB_POSTGRESDB_SCHEMA).replace(/-/g, '_');
  }
  return `n8n_${sanitizeId(machineId).replace(/-/g, '_')}`;
}

function readIntFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    const raw = fs.readFileSync(filePath, 'utf8').trim();
    if (!raw || raw === 'max') return null;
    const value = Number(raw);
    return Number.isFinite(value) ? value : null;
  } catch {
    return null;
  }
}

function getCurrentTxBytes() {
  if (process.platform !== 'linux') return 0;
  let total = 0;
  try {
    for (const iface of fs.readdirSync('/sys/class/net')) {
      if (iface === 'lo') continue;
      const value = readIntFile(`/sys/class/net/${iface}/statistics/tx_bytes`);
      if (value != null) total += value;
    }
  } catch {}
  return total;
}

function getCurrentRxBytes() {
  if (process.platform !== 'linux') return 0;
  let total = 0;
  try {
    for (const iface of fs.readdirSync('/sys/class/net')) {
      if (iface === 'lo') continue;
      const value = readIntFile(`/sys/class/net/${iface}/statistics/rx_bytes`);
      if (value != null) total += value;
    }
  } catch {}
  return total;
}

function getCgroupStats() {
  const memoryCurrentBytes =
    readIntFile('/sys/fs/cgroup/memory.current') ??
    readIntFile('/sys/fs/cgroup/memory/memory.usage_in_bytes');
  const memoryMaxBytes =
    readIntFile('/sys/fs/cgroup/memory.max') ??
    readIntFile('/sys/fs/cgroup/memory/memory.limit_in_bytes');

  let cpuUsageUsec = null;
  try {
    const cpuStatPath = fs.existsSync('/sys/fs/cgroup/cpu.stat')
      ? '/sys/fs/cgroup/cpu.stat'
      : '/sys/fs/cgroup/cpu/cpuacct.usage';
    if (cpuStatPath.endsWith('cpu.stat')) {
      const raw = fs.readFileSync(cpuStatPath, 'utf8');
      const match = raw.match(/^usage_usec\s+(\d+)$/m);
      if (match) cpuUsageUsec = Number(match[1]);
    } else {
      const usageNsec = readIntFile(cpuStatPath);
      if (usageNsec != null) cpuUsageUsec = Math.round(usageNsec / 1000);
    }
  } catch {}

  return { memoryCurrentBytes, memoryMaxBytes, cpuUsageUsec };
}

function parsePsTable(output) {
  return String(output || '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const match = line.match(/^(\d+)\s+(\d+)\s+(.+)$/);
      if (!match) return null;
      return {
        pid: Number(match[1]),
        rssKb: Number(match[2]),
        command: match[3],
      };
    })
    .filter(Boolean);
}

function getTrackedProcessStats() {
  const pids = [process.pid, n8nChild?.pid].filter((pid) => Number.isFinite(pid));
  if (!pids.length) {
    return { trackedProcesses: [], totalTrackedRssBytes: 0 };
  }
  const output = safeExec(`ps -o pid=,rss=,args= -p ${pids.join(',')}`);
  const trackedProcesses = parsePsTable(output).map((row) => ({
    pid: row.pid,
    rssMb: Number((row.rssKb / 1024).toFixed(2)),
    rssBytes: row.rssKb * 1024,
    command: row.command,
  }));
  return {
    trackedProcesses,
    totalTrackedRssBytes: trackedProcesses.reduce((sum, row) => sum + row.rssBytes, 0),
  };
}

async function measureCpuPercent() {
  const startCpu = os.cpus();
  const startUsage = process.cpuUsage();
  const hrStart = process.hrtime.bigint();
  await new Promise((resolve) => setTimeout(resolve, 100));
  const endCpu = os.cpus();
  const endUsage = process.cpuUsage(startUsage);
  const elapsedMs = Math.max(Number(process.hrtime.bigint() - hrStart) / 1e6, 1);
  const cpuPercentNode = (((endUsage.user + endUsage.system) / 1000 / elapsedMs) * 100).toFixed(2);

  let totalDiff = 0;
  let idleDiff = 0;
  for (let i = 0; i < startCpu.length; i++) {
    const s = startCpu[i].times;
    const e = endCpu[i].times;
    const startTotal = s.user + s.nice + s.sys + s.idle + s.irq;
    const endTotal = e.user + e.nice + e.sys + e.idle + e.irq;
    totalDiff += endTotal - startTotal;
    idleDiff += e.idle - s.idle;
  }

  return {
    nodeProcess: `${cpuPercentNode}%`,
    systemTotal: totalDiff > 0 ? ((1 - idleDiff / totalDiff) * 100).toFixed(2) : '0.00',
    coresCount: startCpu.length,
    loadAverage: os.loadavg().map((v) => v.toFixed(2)),
  };
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

async function updateCostHistory(rssBytes) {
  if (!MONGODB_URI) {
    return { currentMonth: null, last5MonthsHistory: [], disabled: true };
  }
  try {
    await connectToMongo();
    await migrateCostHistoryIndexes();

    const now = new Date();
    const currentMonthStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const projectName = getProjectName();
    const currentTxBytes = getCurrentTxBytes();

    let record = await CostHistory.findOne({ month: currentMonthStr, projectName });
    if (!record) {
      record = new CostHistory({
        month: currentMonthStr,
        projectName,
        lastMeasurementTime: now,
        lastTxBytes: currentTxBytes,
      });
      await record.save();
    }

    const minutesElapsed = (now.getTime() - new Date(record.lastMeasurementTime).getTime()) / 60000;
    if (minutesElapsed > 0.01) {
      record.accumulatedMemoryMinutes += (rssBytes / 1024 / 1024 / 1024) * minutesElapsed;
      const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1);
      record.accumulatedCpuMinutes += allocatedCpu * minutesElapsed;
      if (currentTxBytes > 0 && record.lastTxBytes > 0 && currentTxBytes >= record.lastTxBytes) {
        record.accumulatedEgressBytes += currentTxBytes - record.lastTxBytes;
      }
      record.lastTxBytes = currentTxBytes > 0 ? currentTxBytes : record.lastTxBytes;
      record.lastMeasurementTime = now;
      record.memoryCost = record.accumulatedMemoryMinutes * 0.000462;
      record.cpuCost = record.accumulatedCpuMinutes * 0.000926;
      record.egressCost = (record.accumulatedEgressBytes / 1024 / 1024 / 1024) * 0.1;
      record.totalCost = record.memoryCost + record.cpuCost + record.egressCost;
      await record.save();
    }

    const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1);
    const activeMinutes = allocatedCpu > 0 ? record.accumulatedCpuMinutes / allocatedCpu : 0;
    const d = Math.floor(activeMinutes / 1440);
    const h = Math.floor((activeMinutes % 1440) / 60);
    const m = Math.floor(activeMinutes % 60);

    const history = await CostHistory.find({ projectName }).sort({ month: -1 }).limit(5);
    return {
      currentMonth: {
        projectName: record.projectName,
        machineId: record.projectName,
        month: record.month,
        runningDuration: `${d}d ${h}h ${m}m`,
        runningDays: `${(activeMinutes / 1440).toFixed(2)} days`,
        accumulatedMemoryGBMinutes: record.accumulatedMemoryMinutes.toFixed(2),
        accumulatedCpuVCPUMinutes: record.accumulatedCpuMinutes.toFixed(2),
        accumulatedEgressGB: (record.accumulatedEgressBytes / 1024 / 1024 / 1024).toFixed(4),
        ramCost: `$${record.memoryCost.toFixed(4)}`,
        cpuCost: `$${record.cpuCost.toFixed(4)}`,
        networkCost: `$${record.egressCost.toFixed(4)}`,
        totalCost: `$${record.totalCost.toFixed(4)}`,
      },
      last5MonthsHistory: history.map((hist) => {
        const hAct = allocatedCpu > 0 ? hist.accumulatedCpuMinutes / allocatedCpu : 0;
        return {
          projectName: hist.projectName,
          machineId: hist.projectName,
          month: hist.month,
          runningDuration: `${Math.floor(hAct / 1440)}d ${Math.floor((hAct % 1440) / 60)}h ${Math.floor(hAct % 60)}m`,
          ramCost: `$${(hist.memoryCost || 0).toFixed(4)}`,
          cpuCost: `$${(hist.cpuCost || 0).toFixed(4)}`,
          networkCost: `$${(hist.egressCost || 0).toFixed(4)}`,
          totalCost: `$${(hist.totalCost || 0).toFixed(4)}`,
        };
      }),
    };
  } catch (err) {
    return { currentMonth: null, last5MonthsHistory: [], error: err.message };
  }
}

async function buildMonitorStats() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const cpu = await measureCpuPercent();
  const mem = process.memoryUsage();
  const tracked = getTrackedProcessStats();
  const cgroup = getCgroupStats();
  const txBytes = getCurrentTxBytes();
  const rxBytes = getCurrentRxBytes();
  const freeOutput = safeExec('free -h');
  const ps = safeExec('ps aux --sort=-%mem | head -n 8');

  const stats = {
    identity: {
      name: getProjectName(),
      machineId: getProjectName(),
      hostname: os.hostname(),
      platform: os.platform(),
      arch: os.arch(),
      ips: Object.values(os.networkInterfaces())
        .flat()
        .filter((f) => f && !f.internal && f.family === 'IPv4')
        .map((f) => f.address),
    },
    cpu,
    os: {
      total: `${toGB(totalMem)} GB`,
      free: `${toGB(freeMem)} GB`,
      used: `${toGB(usedMem)} GB`,
      usedPercentage: `${((usedMem / totalMem) * 100).toFixed(2)}%`,
    },
    node: {
      heapTotal: `${toMB(mem.heapTotal)} MB`,
      heapUsed: `${toMB(mem.heapUsed)} MB`,
      rss: `${toMB(mem.rss)} MB`,
      rssMb: Number(toMB(mem.rss)),
      rssBytes: mem.rss,
    },
    tracked: {
      totalTrackedRssMb: Number(toMB(tracked.totalTrackedRssBytes)),
      totalTrackedRssBytes: tracked.totalTrackedRssBytes,
      processes: tracked.trackedProcesses,
    },
    container: {
      memoryCurrentMb: cgroup.memoryCurrentBytes != null ? Number(toMB(cgroup.memoryCurrentBytes)) : null,
      memoryCurrentBytes: cgroup.memoryCurrentBytes,
      memoryLimitMb: cgroup.memoryMaxBytes != null ? Number(toMB(cgroup.memoryMaxBytes)) : null,
      memoryLimitBytes: cgroup.memoryMaxBytes,
      cpuUsageUsec: cgroup.cpuUsageUsec,
      networkTxBytes: txBytes,
      networkRxBytes: rxBytes,
      networkTxGb: Number((txBytes / 1024 / 1024 / 1024).toFixed(4)),
      networkRxGb: Number((rxBytes / 1024 / 1024 / 1024).toFixed(4)),
    },
    timestamp: new Date().toISOString(),
  };

  if (freeOutput) stats.freeCommandOutput = freeOutput;
  if (ps) stats.topProcesses = ps.split('\n');

  return {
    stats,
    rssBytes: cgroup.memoryCurrentBytes || tracked.totalTrackedRssBytes || mem.rss,
  };
}

function normalizePublicUrl(raw) {
  if (!raw) return '';
  let value = String(raw).trim();
  if (!value) return '';
  if (!/^https?:\/\//i.test(value)) value = `https://${value}`;
  try {
    const url = new URL(value);
    return `${url.protocol}//${url.host}${url.pathname.replace(/\/+$/, '')}`;
  } catch {
    return value.replace(/\/+$/, '');
  }
}

function isBadPublicHost(host) {
  if (!host) return true;
  const clean = String(host).toLowerCase();
  return clean.includes('localhost') || clean.startsWith('127.') || clean.startsWith('0.0.0.0') || clean.startsWith('::1');
}

function detectPublicUrlFromEnv() {
  const candidates = [
    process.env.WEBHOOK_URL,
    process.env.N8N_EDITOR_BASE_URL,
    process.env.RENDER_EXTERNAL_URL,
    process.env.RAILWAY_STATIC_URL,
    process.env.RAILWAY_PUBLIC_DOMAIN,
    process.env.RAILWAY_SERVICE_DOMAIN,
    process.env.PUBLIC_URL,
    process.env.PUBLIC_DOMAIN,
    process.env.APP_URL,
    process.env.BASE_URL,
  ];
  for (const item of candidates) {
    const normalized = normalizePublicUrl(item);
    if (!normalized) continue;
    try {
      const url = new URL(normalized);
      if (!isBadPublicHost(url.hostname)) return normalized;
    } catch {}
  }
  return '';
}

function detectPublicUrlFromRequest(req) {
  const forwardedHost = req.headers['x-forwarded-host'] || req.headers['x-original-host'] || req.headers['host'];
  const rawHost = Array.isArray(forwardedHost) ? forwardedHost[0] : String(forwardedHost || '').split(',')[0].trim();
  if (isBadPublicHost(rawHost)) return '';

  const forwardedProto =
    req.headers['x-forwarded-proto'] ||
    req.headers['x-forwarded-protocol'] ||
    req.headers['x-url-scheme'];
  let proto = Array.isArray(forwardedProto) ? forwardedProto[0] : String(forwardedProto || '').split(',')[0].trim();
  if (!proto) proto = 'https';
  if (!/^https?$/i.test(proto)) proto = 'https';
  if (proto === 'http' && !rawHost.includes('localhost') && !rawHost.startsWith('127.')) proto = 'https';
  return normalizePublicUrl(`${proto}://${rawHost}`);
}

function applyN8nPublicUrlEnv(n8nEnv, publicUrlInput = '') {
  const publicUrl = normalizePublicUrl(publicUrlInput) || detectPublicUrlFromEnv();
  if (!publicUrl) {
    return { env: n8nEnv, publicUrl: '' };
  }
  try {
    const url = new URL(publicUrl);
    n8nEnv.WEBHOOK_URL = `${publicUrl}/`;
    n8nEnv.N8N_EDITOR_BASE_URL = publicUrl;
    n8nEnv.N8N_HOST = url.hostname;
    n8nEnv.N8N_PROTOCOL = url.protocol.replace(':', '');
    n8nEnv.N8N_PROXY_HOPS = process.env.N8N_PROXY_HOPS || '1';
    if (url.protocol === 'https:') {
      n8nEnv.N8N_SECURE_COOKIE = process.env.N8N_SECURE_COOKIE || 'true';
    }
    return { env: n8nEnv, publicUrl };
  } catch {
    return { env: n8nEnv, publicUrl: '' };
  }
}

function buildN8nEnv(publicUrlInput = '') {
  const machineId = getStableMachineId();
  process.env.MACHINE_ID = machineId;
  process.env.STABLE_MACHINE_ID = machineId;
  process.env.APP_MACHINE_ID = machineId;
  const schemaName = getN8nSchemaName(machineId);

  const n8nEnv = {
    ...process.env,
    MACHINE_ID: machineId,
    STABLE_MACHINE_ID: machineId,
    APP_MACHINE_ID: machineId,
    DB_TYPE: process.env.DB_TYPE || 'postgresdb',
    DB_POSTGRESDB_HOST: process.env.DB_POSTGRESDB_HOST || 'aws-1-ap-south-1.pooler.supabase.com',
    DB_POSTGRESDB_PORT: process.env.DB_POSTGRESDB_PORT || '5432',
    DB_POSTGRESDB_DATABASE: process.env.DB_POSTGRESDB_DATABASE || 'postgres',
    DB_POSTGRESDB_USER: process.env.DB_POSTGRESDB_USER || 'postgres.jiewotcsywbwiuxtpwpm',
    DB_POSTGRESDB_PASSWORD: process.env.DB_POSTGRESDB_PASSWORD || 'Ty48216965@',
    DB_POSTGRESDB_SCHEMA: schemaName,
    DB_POSTGRESDB_SSL_ENABLED: process.env.DB_POSTGRESDB_SSL_ENABLED || 'true',
    DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED: process.env.DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED || 'false',
    N8N_ENCRYPTION_KEY: process.env.N8N_ENCRYPTION_KEY || 'cliply_fixed_n8n_key_2026_do_not_change_keep_same',
    N8N_PORT: String(INTERNAL_N8N_PORT),
    N8N_LISTEN_ADDRESS: '127.0.0.1',
    N8N_HIRING_BANNER: process.env.N8N_HIRING_BANNER || 'false',
    N8N_DIAGNOSTICS_ENABLED: process.env.N8N_DIAGNOSTICS_ENABLED || 'false',
    N8N_RUNNERS_ENABLED: process.env.N8N_RUNNERS_ENABLED || 'false',
    N8N_COMMUNITY_PACKAGES_ENABLED: process.env.N8N_COMMUNITY_PACKAGES_ENABLED || 'false',
    EXECUTIONS_PROCESS: process.env.EXECUTIONS_PROCESS || 'main',
    EXECUTIONS_DATA_SAVE_ON_SUCCESS: process.env.EXECUTIONS_DATA_SAVE_ON_SUCCESS || 'none',
    EXECUTIONS_DATA_SAVE_ON_ERROR: process.env.EXECUTIONS_DATA_SAVE_ON_ERROR || 'none',
    EXECUTIONS_DATA_SAVE_ON_PROGRESS: process.env.EXECUTIONS_DATA_SAVE_ON_PROGRESS || 'false',
    N8N_BLOCK_ENV_ACCESS_IN_NODE: process.env.N8N_BLOCK_ENV_ACCESS_IN_NODE || 'false',
  };
  return applyN8nPublicUrlEnv(n8nEnv, publicUrlInput);
}

async function ensureN8nPostgresSchema(n8nEnv) {
  if (n8nEnv.DB_TYPE !== 'postgresdb') return;
  const schemaName = n8nEnv.DB_POSTGRESDB_SCHEMA || 'public';
  if (schemaName === 'public') return;

  const client = new PgClient({
    host: n8nEnv.DB_POSTGRESDB_HOST,
    port: Number(n8nEnv.DB_POSTGRESDB_PORT || 5432),
    database: n8nEnv.DB_POSTGRESDB_DATABASE,
    user: n8nEnv.DB_POSTGRESDB_USER,
    password: n8nEnv.DB_POSTGRESDB_PASSWORD,
    ssl: String(n8nEnv.DB_POSTGRESDB_SSL_ENABLED) === 'true'
      ? {
          rejectUnauthorized: String(n8nEnv.DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED) === 'true',
        }
      : false,
  });

  await client.connect();
  try {
    await client.query(`CREATE SCHEMA IF NOT EXISTS "${schemaName}"`);
  } finally {
    await client.end().catch(() => {});
  }
}

function waitForPort(port, host, timeoutMs = 120000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    function attempt() {
      const sock = new net.Socket();
      sock.setTimeout(1000);
      sock.on('connect', () => {
        sock.destroy();
        resolve();
      });
      sock.on('error', () => {
        sock.destroy();
        if (Date.now() - start >= timeoutMs) reject(new Error('Timeout'));
        else setTimeout(attempt, 500);
      });
      sock.on('timeout', () => {
        sock.destroy();
        setTimeout(attempt, 500);
      });
      sock.connect(port, host);
    }
    attempt();
  });
}

const proxy = httpProxy.createProxyServer({
  target: `http://127.0.0.1:${INTERNAL_N8N_PORT}`,
  ws: true,
  xfwd: true,
  changeOrigin: false,
});

proxy.on('error', (err, req, res) => {
  if (res && !res.headersSent) sendText(res, 502, `Proxy error: ${err.message}`);
});

async function ensureN8nStarted(publicUrlInput = '') {
  if (n8nReady) return;
  if (n8nStartingPromise) {
    await n8nStartingPromise;
    return;
  }

  n8nStartingPromise = (async () => {
    const { env: n8nEnv, publicUrl } = buildN8nEnv(publicUrlInput);
    if (!publicUrl) {
      n8nStartingPromise = null;
      return;
    }

    await ensureN8nPostgresSchema(n8nEnv);

    n8nChild = spawn('n8n', ['start'], {
      stdio: 'inherit',
      env: n8nEnv,
    });

    n8nChild.on('exit', (code, signal) => {
      process.exit(signal ? 1 : code ?? 0);
    });

    await waitForPort(INTERNAL_N8N_PORT, '127.0.0.1');
    n8nReady = true;

    while (pendingQueue.length) {
      const { req, res, timer } = pendingQueue.shift();
      clearTimeout(timer);
      if (!res.writableEnded) proxy.web(req, res);
    }
  })();

  await n8nStartingPromise;
}

async function handleRamRequest(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  const token = url.searchParams.get('token') || req.headers['x-ram-token'];
  if (RAM_TOKEN && token !== RAM_TOKEN) {
    sendJson(res, 401, { error: 'Unauthorized' });
    return;
  }
  const { stats, rssBytes } = await buildMonitorStats();
  const projectCost = await updateCostHistory(rssBytes);
  sendJson(res, 200, {
    identity: stats.identity,
    cpu: stats.cpu,
    os: stats.os,
    node: stats.node,
    tracked: stats.tracked,
    container: stats.container,
    timestamp: stats.timestamp,
    ...(stats.freeCommandOutput ? { freeCommandOutput: stats.freeCommandOutput } : {}),
    ...(stats.topProcesses ? { topProcesses: stats.topProcesses } : {}),
    projectCost,
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  if (url.pathname === '/healthz') {
    sendJson(res, 200, { ok: true, service: 'n8n-only', n8nReady });
    return;
  }

  if (url.pathname === '/ram') {
    await handleRamRequest(req, res);
    return;
  }

  if (!n8nReady) {
    const timer = setTimeout(() => {
      if (!res.writableEnded) sendText(res, 503, 'n8n is starting, please retry');
    }, 60000);

    pendingQueue.push({ req, res, timer });
    const publicUrlFromRequest = detectPublicUrlFromRequest(req) || detectPublicUrlFromEnv();
    ensureN8nStarted(publicUrlFromRequest).catch((err) => {
      while (pendingQueue.length) {
        const item = pendingQueue.shift();
        clearTimeout(item.timer);
        if (!item.res.writableEnded) sendText(item.res, 500, `n8n failed to start: ${err.message}`);
      }
    });
    return;
  }

  proxy.web(req, res);
});

server.on('upgrade', (req, socket, head) => {
  if (!n8nReady) {
    socket.destroy();
    return;
  }
  proxy.ws(req, socket, head);
});

function shutdown(code) {
  try {
    server.close();
  } catch {}
  if (n8nChild && !n8nChild.killed) {
    n8nChild.kill('SIGTERM');
  }
  process.exit(code);
}

process.on('SIGTERM', () => shutdown(0));
process.on('SIGINT', () => shutdown(0));

(async () => {
  await new Promise((resolve) => {
    server.listen(PUBLIC_PORT, '0.0.0.0', resolve);
  });
  const initialPublicUrl = detectPublicUrlFromEnv();
  if (initialPublicUrl) {
    await ensureN8nStarted(initialPublicUrl);
  }
})();
EOF

RUN chown -R node:node /app /home/node

USER node

EXPOSE 8080

ENTRYPOINT ["node", "/app/server.js"]
