# syntax=docker/dockerfile:1
FROM n8nio/n8n:2.22.4

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
    NODE_FUNCTION_ALLOW_EXTERNAL=mongodb,playwright \
    NODE_FUNCTION_ALLOW_BUILTIN=* \
    DB_TYPE=postgresdb \
    DB_POSTGRESDB_HOST=aws-1-ap-south-1.pooler.supabase.com \
    DB_POSTGRESDB_PORT=5432 \
    DB_POSTGRESDB_DATABASE=postgres \
    DB_POSTGRESDB_USER=postgres.jiewotcsywbwiuxtpwpm \
    DB_POSTGRESDB_PASSWORD=Ty48216965@ \
    DB_POSTGRESDB_SSL_ENABLED=true \
    DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false \
    N8N_ENCRYPTION_KEY=cliply_fixed_n8n_key_2026_do_not_change_keep_same

WORKDIR /app
USER root

RUN if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache xvfb dbus ttf-freefont nss freetype harfbuzz ca-certificates udev; \
    elif command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends \
        xvfb dbus-x11 fonts-liberation libnss3 libatk-bridge2.0-0 libgtk-3-0 \
        libxss1 libasound2 libgbm1 libxshmfence1 ca-certificates \
      && rm -rf /var/lib/apt/lists/*; \
    fi

RUN npm init -y >/dev/null 2>&1 \
    && npm install --no-package-lock --no-save --no-audit --no-fund \
       http-proxy mongoose mongodb pg express socket.io playwright playwright-extra puppeteer-extra-plugin-stealth \
    && npx playwright install chromium


RUN cat <<'EOF' > /app/server.js
'use strict';

const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { execSync, spawn } = require('node:child_process');
const path = require('node:path');
const httpProxy = require('http-proxy');
const { Server: SocketIOServer } = require('socket.io');
const { Client: PgClient } = require('pg');

let chromium = null;
try {
  const pwExtra = require('playwright-extra');
  const stealth = require('puppeteer-extra-plugin-stealth')();
  pwExtra.chromium.use(stealth);
  chromium = pwExtra.chromium;
} catch (err) {
  console.warn('[playwright] playwright-extra unavailable, fallback to playwright:', err.message);
  try {
    chromium = require('playwright').chromium;
  } catch (fallbackErr) {
    console.warn('[playwright] unavailable:', fallbackErr.message);
  }
}

const PUBLIC_PORT = Number(process.env.PORT || 8080);
const INTERNAL_N8N_PORT = Number(process.env.N8N_PORT || 5678);

const RAM_TOKEN = process.env.RAM_TOKEN || 'cliply_ram_secret_token_2026';

// MongoDB này chỉ dùng cho RAM/cost/network, không dùng cho n8n login/workflow.
const MONGODB_URI =
  process.env.MONGODB_URI ||
  'mongodb+srv://tylauj04:t482169@cluster0.ygab0.mongodb.net';

const TARGET_DB = process.env.TARGET_DB || 'application-manager';

let mongoose = null;
let CostHistory = null;

// ================= STABLE ID =================
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

  if (process.env.RAILWAY_STATIC_URL) {
    return `railway_${sanitizeId(process.env.RAILWAY_STATIC_URL)}`;
  }

  if (process.env.RENDER_SERVICE_ID) {
    return `render_${sanitizeId(process.env.RENDER_SERVICE_ID)}`;
  }

  if (process.env.RENDER_EXTERNAL_URL) {
    try {
      return `render_${sanitizeId(new URL(process.env.RENDER_EXTERNAL_URL).hostname)}`;
    } catch {}
  }

  if (process.env.FLY_APP_NAME) {
    return `fly_${sanitizeId(process.env.FLY_APP_NAME)}`;
  }

  if (process.env.KOYEB_SERVICE_NAME) {
    return `koyeb_${sanitizeId(process.env.KOYEB_SERVICE_NAME)}`;
  }

  if (process.env.COOLIFY_FQDN) {
    return `coolify_${sanitizeId(process.env.COOLIFY_FQDN)}`;
  }

  const publicCandidates = [
    process.env.PUBLIC_DOMAIN,
    process.env.PUBLIC_URL,
    process.env.APP_URL,
    process.env.BASE_URL,
    process.env.WEBHOOK_URL,
    process.env.N8N_EDITOR_BASE_URL,
  ];

  for (const raw of publicCandidates) {
    if (!raw) continue;

    try {
      let value = String(raw).trim();
      if (!/^https?:\/\//i.test(value)) value = `https://${value}`;
      const host = new URL(value).hostname;

      if (
        host &&
        !host.includes('localhost') &&
        !host.startsWith('127.') &&
        !host.startsWith('0.0.0.0')
      ) {
        return `domain_${sanitizeId(host)}`;
      }
    } catch {}
  }

  return `vps_${sanitizeId(os.hostname() || 'unknown')}`;
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

// ================= MONGODB COST =================
function loadMongoose() {
  if (mongoose) return mongoose;

  mongoose = require('mongoose');

  const schema = new mongoose.Schema(
    {
      month: {
        type: String,
        required: true,
      },
      projectName: {
        type: String,
        required: true,
        default: 'unknown',
      },
      accumulatedMemoryMinutes: {
        type: Number,
        default: 0,
      },
      accumulatedCpuMinutes: {
        type: Number,
        default: 0,
      },
      accumulatedEgressBytes: {
        type: Number,
        default: 0,
      },
      lastTxBytes: {
        type: Number,
        default: 0,
      },
      lastMeasurementTime: {
        type: Date,
        default: Date.now,
      },
      memoryCost: {
        type: Number,
        default: 0,
      },
      cpuCost: {
        type: Number,
        default: 0,
      },
      egressCost: {
        type: Number,
        default: 0,
      },
      totalCost: {
        type: Number,
        default: 0,
      },
    },
    {
      timestamps: true,
    }
  );

  schema.index(
    {
      month: 1,
      projectName: 1,
    },
    {
      unique: true,
    }
  );

  CostHistory =
    mongoose.models.CostHistory || mongoose.model('CostHistory', schema);

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

    uri = `${base.replace(/\/+$/, '')}/${TARGET_DB}?${
      qs || 'retryWrites=true&w=majority'
    }`;
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
  try {
    return execSync(cmd, {
      stdio: ['ignore', 'pipe', 'pipe'],
    })
      .toString()
      .trim();
  } catch {
    return '';
  }
}

async function measureCpuPercent() {
  const startCpu = os.cpus();
  const startUsage = process.cpuUsage();
  const hrStart = process.hrtime.bigint();

  await new Promise((resolve) => setTimeout(resolve, 100));

  const endCpu = os.cpus();
  const endUsage = process.cpuUsage(startUsage);
  const elapsedMs = Math.max(Number(process.hrtime.bigint() - hrStart) / 1e6, 1);

  const cpuPercentNode = (
    ((endUsage.user + endUsage.system) / 1000 / elapsedMs) *
    100
  ).toFixed(2);

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
    systemTotal:
      totalDiff > 0
        ? ((1 - idleDiff / totalDiff) * 100).toFixed(2)
        : '0.00',
    coresCount: startCpu.length,
    loadAverage: os.loadavg().map((v) => v.toFixed(2)),
  };
}

function getCurrentTxBytes() {
  if (process.platform !== 'linux') return 0;

  let total = 0;

  try {
    const base = '/sys/class/net';
    const interfaces = fs.readdirSync(base);

    for (const iface of interfaces) {
      if (iface === 'lo') continue;

      const txPath = `${base}/${iface}/statistics/tx_bytes`;

      if (fs.existsSync(txPath)) {
        const value = parseInt(fs.readFileSync(txPath, 'utf8').trim(), 10);

        if (Number.isFinite(value)) total += value;
      }
    }
  } catch {}

  return total;
}

async function buildMonitorStats() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const cpu = await measureCpuPercent();
  const mem = process.memoryUsage();
  const projectName = getProjectName();

  const stats = {
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
    },
    timestamp: new Date().toISOString(),
  };

  if (process.platform === 'linux') {
    const freeOutput = safeExec('free -h');

    if (freeOutput) stats.freeCommandOutput = freeOutput;

    const ps = safeExec('ps aux --sort=-%mem | head -n 6');

    if (ps) stats.topProcesses = ps.split('\n');

    const logPaths = [
      '/tmp/mem_guard.log',
      '/var/log/mem_guard.log',
      './mem_guard.log',
    ];

    for (const logPath of logPaths) {
      const logTail = safeExec(`tail -n 5 ${logPath} 2>/dev/null`);

      if (logTail) {
        stats.memGuardLog = {
          path: logPath,
          lines: logTail.split('\n'),
        };
        break;
      }
    }
  }

  stats.identity = {
    name: projectName,
    machineId: projectName,
    hostname: os.hostname(),
    platform: os.platform(),
    arch: os.arch(),
    ips: Object.values(os.networkInterfaces())
      .flat()
      .filter((f) => f && !f.internal && f.family === 'IPv4')
      .map((f) => f.address),
  };

  return {
    stats,
    rssBytes: mem.rss,
  };
}

async function updateCostHistory(rssBytes) {
  if (!MONGODB_URI) {
    return {
      currentMonth: null,
      last5MonthsHistory: [],
      disabled: true,
    };
  }

  try {
    await connectToMongo();
    await migrateCostHistoryIndexes();

    const now = new Date();
    const currentMonthStr = `${now.getFullYear()}-${String(
      now.getMonth() + 1
    ).padStart(2, '0')}`;

    const projectName = getProjectName();
    const currentTxBytes = getCurrentTxBytes();

    let record = await CostHistory.findOne({
      month: currentMonthStr,
      projectName,
    });

    if (!record) {
      record = new CostHistory({
        month: currentMonthStr,
        projectName,
        lastMeasurementTime: now,
        lastTxBytes: currentTxBytes,
      });

      await record.save();
    }

    const minutesElapsed =
      (now.getTime() - new Date(record.lastMeasurementTime).getTime()) /
      60000;

    if (minutesElapsed > 0.01) {
      record.accumulatedMemoryMinutes +=
        (rssBytes / 1024 / 1024 / 1024) * minutesElapsed;

      const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1);

      record.accumulatedCpuMinutes += allocatedCpu * minutesElapsed;

      if (
        currentTxBytes > 0 &&
        record.lastTxBytes > 0 &&
        currentTxBytes >= record.lastTxBytes
      ) {
        record.accumulatedEgressBytes += currentTxBytes - record.lastTxBytes;
      }

      record.lastTxBytes =
        currentTxBytes > 0 ? currentTxBytes : record.lastTxBytes;

      record.lastMeasurementTime = now;

      // Railway x2
      record.memoryCost = record.accumulatedMemoryMinutes * 0.000462;
      record.cpuCost = record.accumulatedCpuMinutes * 0.000926;
      record.egressCost =
        (record.accumulatedEgressBytes / 1024 / 1024 / 1024) * 0.1;

      record.totalCost =
        record.memoryCost + record.cpuCost + record.egressCost;

      await record.save();
    }

    const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1);
    const activeMinutes =
      allocatedCpu > 0 ? record.accumulatedCpuMinutes / allocatedCpu : 0;

    const d = Math.floor(activeMinutes / 1440);
    const h = Math.floor((activeMinutes % 1440) / 60);
    const m = Math.floor(activeMinutes % 60);

    const currentCost = {
      projectName: record.projectName,
      machineId: record.projectName,
      month: record.month,
      runningDuration: `${d}d ${h}h ${m}m`,
      runningDays: `${(activeMinutes / 1440).toFixed(2)} days`,
      accumulatedMemoryGBMinutes:
        record.accumulatedMemoryMinutes.toFixed(2),
      accumulatedCpuVCPUMinutes:
        record.accumulatedCpuMinutes.toFixed(2),
      accumulatedEgressGB: (
        record.accumulatedEgressBytes /
        1024 /
        1024 /
        1024
      ).toFixed(4),
      ramCost: `$${record.memoryCost.toFixed(4)}`,
      cpuCost: `$${record.cpuCost.toFixed(4)}`,
      networkCost: `$${record.egressCost.toFixed(4)}`,
      totalCost: `$${record.totalCost.toFixed(4)}`,
    };

    const history = await CostHistory.find({
      projectName,
    })
      .sort({
        month: -1,
      })
      .limit(5);

    const last5MonthsHistory = history.map((hist) => {
      const hAct =
        allocatedCpu > 0 ? hist.accumulatedCpuMinutes / allocatedCpu : 0;

      return {
        projectName: hist.projectName,
        machineId: hist.projectName,
        month: hist.month,
        runningDuration: `${Math.floor(hAct / 1440)}d ${Math.floor(
          (hAct % 1440) / 60
        )}h ${Math.floor(hAct % 60)}m`,
        ramCost: `$${(hist.memoryCost || 0).toFixed(4)}`,
        cpuCost: `$${(hist.cpuCost || 0).toFixed(4)}`,
        networkCost: `$${(hist.egressCost || 0).toFixed(4)}`,
        totalCost: `$${(hist.totalCost || 0).toFixed(4)}`,
      };
    });

    return {
      currentMonth: currentCost,
      last5MonthsHistory,
    };
  } catch (err) {
    return {
      currentMonth: null,
      last5MonthsHistory: [],
      error: err.message,
    };
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

async function handleRamRequest(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  const token =
    url.searchParams.get('token') ||
    req.headers['x-ram-token'];

  if (RAM_TOKEN && token !== RAM_TOKEN) {
    sendJson(res, 401, {
      error: 'Unauthorized',
    });
    return;
  }

  const { stats, rssBytes } = await buildMonitorStats();
  const projectCost = await updateCostHistory(rssBytes);

  sendJson(res, 200, {
    identity: stats.identity,
    cpu: stats.cpu,
    os: stats.os,
    node: stats.node,
    timestamp: stats.timestamp,
    ...(stats.freeCommandOutput
      ? {
          freeCommandOutput: stats.freeCommandOutput,
        }
      : {}),
    ...(stats.topProcesses
      ? {
          topProcesses: stats.topProcesses,
        }
      : {}),
    ...(stats.memGuardLog
      ? {
          memGuardLog: stats.memGuardLog,
        }
      : {}),
    projectCost,
  });
}

// ================= PUBLIC DOMAIN =================
function normalizePublicUrl(raw) {
  if (!raw) return '';

  let value = String(raw).trim();

  if (!value) return '';

  if (!/^https?:\/\//i.test(value)) {
    value = `https://${value}`;
  }

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

  return (
    clean.includes('localhost') ||
    clean.startsWith('127.') ||
    clean.startsWith('0.0.0.0') ||
    clean.startsWith('::1')
  );
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

      if (!isBadPublicHost(url.hostname)) {
        return normalized;
      }
    } catch {}
  }

  return '';
}

function detectPublicUrlFromRequest(req) {
  const forwardedHost =
    req.headers['x-forwarded-host'] ||
    req.headers['x-original-host'] ||
    req.headers['host'];

  const rawHost = Array.isArray(forwardedHost)
    ? forwardedHost[0]
    : String(forwardedHost || '').split(',')[0].trim();

  if (isBadPublicHost(rawHost)) return '';

  const forwardedProto =
    req.headers['x-forwarded-proto'] ||
    req.headers['x-forwarded-protocol'] ||
    req.headers['x-url-scheme'];

  let proto = Array.isArray(forwardedProto)
    ? forwardedProto[0]
    : String(forwardedProto || '').split(',')[0].trim();

  if (!proto) proto = 'https';

  if (!/^https?$/i.test(proto)) proto = 'https';

  if (
    proto === 'http' &&
    !rawHost.includes('localhost') &&
    !rawHost.startsWith('127.')
  ) {
    proto = 'https';
  }

  return normalizePublicUrl(`${proto}://${rawHost}`);
}

function applyN8nPublicUrlEnv(n8nEnv, publicUrlInput = '') {
  const publicUrl =
    normalizePublicUrl(publicUrlInput) ||
    detectPublicUrlFromEnv();

  if (!publicUrl) {
    console.warn(
      '[n8n] Public URL not detected yet. n8n will start after first public request.'
    );
    return {
      env: n8nEnv,
      publicUrl: '',
    };
  }

  try {
    const url = new URL(publicUrl);

    n8nEnv.WEBHOOK_URL = `${publicUrl}/`;
    n8nEnv.N8N_EDITOR_BASE_URL = publicUrl;
    n8nEnv.N8N_HOST = url.hostname;
    n8nEnv.N8N_PROTOCOL = url.protocol.replace(':', '');
    n8nEnv.N8N_PROXY_HOPS = process.env.N8N_PROXY_HOPS || '1';

    if (url.protocol === 'https:') {
      n8nEnv.N8N_SECURE_COOKIE =
        process.env.N8N_SECURE_COOKIE || 'true';
    }

    console.log('[n8n] Public URL detected:', publicUrl);
    console.log('[n8n] WEBHOOK_URL:', n8nEnv.WEBHOOK_URL);
    console.log('[n8n] N8N_EDITOR_BASE_URL:', n8nEnv.N8N_EDITOR_BASE_URL);
    console.log('[n8n] N8N_HOST:', n8nEnv.N8N_HOST);
    console.log('[n8n] N8N_PROTOCOL:', n8nEnv.N8N_PROTOCOL);

    return {
      env: n8nEnv,
      publicUrl,
    };
  } catch (err) {
    console.warn('[n8n] Invalid public URL:', publicUrl, err.message);

    return {
      env: n8nEnv,
      publicUrl: '',
    };
  }
}

// ================= N8N POSTGRES =================
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
    ssl:
      String(n8nEnv.DB_POSTGRESDB_SSL_ENABLED) === 'true'
        ? {
            rejectUnauthorized:
              String(n8nEnv.DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED) === 'true',
          }
        : false,
  });

  await client.connect();

  try {
    await client.query(`CREATE SCHEMA IF NOT EXISTS "${schemaName}"`);
    console.log('[n8n-db] schema ensured:', schemaName);
  } finally {
    await client.end().catch(() => {});
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

    // Cho phép n8n Code node đọc env bằng $env/process.env
    N8N_BLOCK_ENV_ACCESS_IN_NODE:
      process.env.N8N_BLOCK_ENV_ACCESS_IN_NODE || 'false',

    // PostgreSQL Supabase Pooler IPv4 cho n8n.
    DB_TYPE: process.env.DB_TYPE || 'postgresdb',
    DB_POSTGRESDB_HOST:
      process.env.DB_POSTGRESDB_HOST ||
      'aws-1-ap-south-1.pooler.supabase.com',
    DB_POSTGRESDB_PORT:
      process.env.DB_POSTGRESDB_PORT || '5432',
    DB_POSTGRESDB_DATABASE:
      process.env.DB_POSTGRESDB_DATABASE || 'postgres',
    DB_POSTGRESDB_USER:
      process.env.DB_POSTGRESDB_USER ||
      'postgres.jiewotcsywbwiuxtpwpm',
    DB_POSTGRESDB_PASSWORD:
      process.env.DB_POSTGRESDB_PASSWORD ||
      'Ty48216965@',
    DB_POSTGRESDB_SCHEMA: schemaName,
    DB_POSTGRESDB_SSL_ENABLED:
      process.env.DB_POSTGRESDB_SSL_ENABLED || 'true',
    DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED:
      process.env.DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED || 'false',

    N8N_ENCRYPTION_KEY:
      process.env.N8N_ENCRYPTION_KEY ||
      'cliply_fixed_n8n_key_2026_do_not_change_keep_same',

    N8N_PORT: String(INTERNAL_N8N_PORT),
    N8N_LISTEN_ADDRESS: '127.0.0.1',

    N8N_HIRING_BANNER:
      process.env.N8N_HIRING_BANNER || 'false',

    N8N_DIAGNOSTICS_ENABLED:
      process.env.N8N_DIAGNOSTICS_ENABLED || 'false',

    N8N_RUNNERS_ENABLED:
      process.env.N8N_RUNNERS_ENABLED || 'false',

    N8N_COMMUNITY_PACKAGES_ENABLED:
      process.env.N8N_COMMUNITY_PACKAGES_ENABLED || 'false',

    EXECUTIONS_PROCESS:
      process.env.EXECUTIONS_PROCESS || 'main',

    EXECUTIONS_DATA_SAVE_ON_SUCCESS:
      process.env.EXECUTIONS_DATA_SAVE_ON_SUCCESS || 'none',

    EXECUTIONS_DATA_SAVE_ON_ERROR:
      process.env.EXECUTIONS_DATA_SAVE_ON_ERROR || 'none',

    EXECUTIONS_DATA_SAVE_ON_PROGRESS:
      process.env.EXECUTIONS_DATA_SAVE_ON_PROGRESS || 'false',
  };

  return applyN8nPublicUrlEnv(n8nEnv, publicUrlInput);
}

function startN8n(publicUrlInput = '') {
  const { env: n8nEnv, publicUrl } = buildN8nEnv(publicUrlInput);

  if (!publicUrl) {
    return null;
  }

  console.log('[machine] MACHINE_ID:', n8nEnv.MACHINE_ID);
  console.log('[machine] N8N_BLOCK_ENV_ACCESS_IN_NODE:', n8nEnv.N8N_BLOCK_ENV_ACCESS_IN_NODE);
  console.log('[n8n-db] DB_TYPE:', n8nEnv.DB_TYPE);
  console.log('[n8n-db] DB_POSTGRESDB_HOST:', n8nEnv.DB_POSTGRESDB_HOST);
  console.log('[n8n-db] DB_POSTGRESDB_DATABASE:', n8nEnv.DB_POSTGRESDB_DATABASE);
  console.log('[n8n-db] DB_POSTGRESDB_USER:', n8nEnv.DB_POSTGRESDB_USER);
  console.log('[n8n-db] DB_POSTGRESDB_SCHEMA:', n8nEnv.DB_POSTGRESDB_SCHEMA);
  console.log('[n8n-db] DB_POSTGRESDB_SSL_ENABLED:', n8nEnv.DB_POSTGRESDB_SSL_ENABLED);
  console.log('[n8n-db] N8N_ENCRYPTION_KEY exists:', Boolean(n8nEnv.N8N_ENCRYPTION_KEY));

  const child = spawn('n8n', ['start'], {
    stdio: 'inherit',
    env: n8nEnv,
  });

  child.on('exit', (code, signal) => {
    process.exit(signal ? 1 : code ?? 0);
  });

  ensureN8nPostgresSchema(n8nEnv).catch((err) => {
    console.error('[n8n-db] failed to ensure schema:', err.message);
  });

  return child;
}



// ================= VIRTUAL DISPLAY =================
let xvfbChild = null;

function ensureVirtualDisplayStarted() {
  if (process.env.DISPLAY) return;

  process.env.DISPLAY = ':99';

  try {
    xvfbChild = spawn('Xvfb', [
      ':99',
      '-screen',
      '0',
      '1365x900x24',
      '-ac',
      '+extension',
      'RANDR',
    ], {
      stdio: 'ignore',
      detached: true,
    });

    xvfbChild.unref();
    console.log('[xvfb] started on DISPLAY=:99');
  } catch (err) {
    console.warn('[xvfb] could not start:', err.message);
  }
}

// ================= PLAYWRIGHT APIs =================
const REMOTE_BROWSER_DIR = process.env.REMOTE_BROWSER_DIR || '/data/playwright/ai-studio-profile';
const REMOTE_UPLOAD_DIR = process.env.REMOTE_UPLOAD_DIR || '/tmp/remote-browser-uploads';
const AI_STUDIO_APP_URL =
  process.env.AI_STUDIO_APP_URL ||
  'https://ai.studio/apps/4c2ff89f-3309-4c2c-9613-3058239f23b3';

let io = null;
let remoteContext = null;
let remotePage = null;
let remoteCdpClient = null;
let pendingFileChooser = null;

function readJsonBody(req, limitBytes = 10 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let body = '';
    let size = 0;

    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limitBytes) {
        reject(new Error('Request body too large'));
        req.destroy();
        return;
      }
      body += chunk.toString('utf8');
    });

    req.on('end', () => {
      if (!body.trim()) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(body));
      } catch (err) {
        reject(err);
      }
    });

    req.on('error', reject);
  });
}

function cleanBilibiliTitle(title) {
  return String(title || '')
    .replace(/\s+/g, ' ')
    .replace(/[\\/:*?"<>|]/g, '')
    .trim();
}

function inferBilibiliEpisode(title) {
  const text = String(title || '');
  const match =
    text.match(/第\s*([0-9一二三四五六七八九十百千万]+)\s*[集话話回]/) ||
    text.match(/EP\.?\s*(\d+)/i) ||
    text.match(/E(?:pisode)?\s*(\d+)/i);

  return match ? String(match[1]) : '';
}

async function scrapeBilibiliToday(options = {}) {
  if (!chromium) {
    throw new Error('Playwright is not installed or could not be loaded');
  }

  const runDate =
    options.runDate ||
    new Date().toISOString().slice(0, 10);

  const bilibiliUrl =
    options.bilibiliUrl ||
    process.env.BILIBILI_URL ||
    'https://www.bilibili.com/c/douga/?spm_id_from=333.1007.0.0';

  const maxVideos = Number(
    options.maxVideos ||
    process.env.MAX_BILIBILI_VIDEOS ||
    20
  );

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
    ],
  });

  try {
    const page = await browser.newPage({
      userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125 Safari/537.36',
      viewport: {
        width: 1365,
        height: 900,
      },
    });

    await page.goto(bilibiliUrl, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(6000);

    try {
      await page.mouse.wheel(0, 2400);
      await page.waitForTimeout(2500);
    } catch {}

    const rows = await page.evaluate(() => {
      function absUrl(href) {
        try {
          return new URL(href, location.origin).href;
        } catch {
          return '';
        }
      }

      function textOf(el) {
        return (
          el?.innerText ||
          el?.textContent ||
          el?.getAttribute?.('title') ||
          ''
        ).trim();
      }

      return [
        ...document.querySelectorAll(
          'a[href*="/video/"], a[href*="bilibili.com/video/"]'
        ),
      ]
        .map((a) => {
          const source_url = absUrl(a.getAttribute('href') || a.href || '');
          const match = source_url.match(/BV[a-zA-Z0-9]+/);

          if (!match) return null;

          const card =
            a.closest(
              '.video-card, .bili-video-card, .feed-card, .card-box, .bili-video-card__wrap, li, div'
            ) || a.parentElement;

          const title =
            textOf(a) ||
            textOf(card?.querySelector?.('.title')) ||
            textOf(card?.querySelector?.('[title]')) ||
            '';

          const cardText = textOf(card);
          const img = card?.querySelector?.('img');
          const thumbnail =
            img?.src ||
            img?.getAttribute?.('data-src') ||
            img?.getAttribute?.('src') ||
            '';

          return {
            bvid: match[0],
            source_url,
            original_title: title || cardText.split('\n')[0] || '',
            card_text: cardText,
            thumbnail_url: thumbnail,
          };
        })
        .filter(Boolean);
    });

    const seen = new Set();

    return rows
      .filter((item) => {
        if (!item.bvid || !item.original_title) return false;
        if (seen.has(item.bvid)) return false;
        seen.add(item.bvid);
        return true;
      })
      .slice(0, maxVideos)
      .map((item) => {
        const original = cleanBilibiliTitle(item.original_title);
        const episode = inferBilibiliEpisode(original);

        return {
          run_date: runDate,
          unique_key: `${item.bvid}_${episode || 'unknown'}`,
          bvid: item.bvid,
          episode,
          original_title: original,
          processed_title_vi: `VI - ${original}`,
          processed_title_en: `EN - ${original}`,
          processed_title_ja: `JP - ${original}`,
          source_url: item.source_url,
          thumbnail_url: item.thumbnail_url,
          card_text: item.card_text,
          download_url: '',
          manual_file_path: '',
          download_path: '',
          processed_path: '',
          preview_url: '',
          status: 'FOUND_TODAY',
          platforms: '',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          error: '',
        };
      });
  } finally {
    await browser.close().catch(() => {});
  }
}

async function handleScrapeBilibiliRequest(req, res) {
  try {
    const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
    const body = req.method === 'POST' ? await readJsonBody(req) : {};

    const rows = await scrapeBilibiliToday({
      runDate: body.runDate || url.searchParams.get('runDate'),
      bilibiliUrl: body.bilibiliUrl || url.searchParams.get('url'),
      maxVideos: body.maxVideos || url.searchParams.get('maxVideos'),
    });

    sendJson(res, 200, {
      ok: true,
      count: rows.length,
      rows,
    });
  } catch (err) {
    sendJson(res, 500, {
      ok: false,
      error: err.message,
    });
  }
}

function sendRemotePage(res) {
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
  });

  res.end(`<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Remote Playwright Browser</title>
  <script src="/socket.io/socket.io.js"></script>
  <style>
    body { margin:0; background:#202124; color:#e8eaed; font-family:Arial,sans-serif; overflow:hidden; }
    .bar { height:36px; display:flex; align-items:center; gap:12px; padding:0 12px; background:#303134; font-size:13px; }
    .bar a { color:#8ab4f8; }
    #screen { width:100vw; height:calc(100vh - 36px); object-fit:contain; display:block; background:#111; outline:none; }
  </style>
</head>
<body>
  <div class="bar">
    <b>Remote Playwright Browser</b>
    <span>Click vào màn hình để điều khiển. Upload file sẽ mở file picker máy bạn.</span>
    <a href="/api/remote/open" target="_blank">open/reload AI Studio</a>
  </div>
  <img id="screen" tabindex="0" draggable="false" />
  <input id="fileInput" type="file" style="display:none" />
  <script>
    const socket = io();
    const screen = document.getElementById('screen');
    const fileInput = document.getElementById('fileInput');
    let waitingFile = false;

    function focusScreen() { screen.focus(); }
    document.body.addEventListener('click', focusScreen);
    screen.addEventListener('load', focusScreen);

    socket.on('sync-render-image', (data) => {
      screen.src = 'data:image/jpeg;base64,' + data.image;
    });

    socket.on('request-file-upload', (data) => {
      if (data.multiple) fileInput.setAttribute('multiple', 'multiple');
      else fileInput.removeAttribute('multiple');
      waitingFile = true;
      fileInput.click();
    });

    fileInput.addEventListener('change', async (event) => {
      if (!waitingFile) return;
      const files = Array.from(event.target.files || []);

      if (!files.length) {
        socket.emit('cancel-file-upload');
        waitingFile = false;
        return;
      }

      const payload = [];
      for (const file of files) {
        const buffer = await file.arrayBuffer();
        payload.push({ name: file.name, data: buffer });
      }

      socket.emit('upload-file-data', payload);
      waitingFile = false;
      fileInput.value = '';
    });

    function coords(e) {
      const rect = screen.getBoundingClientRect();
      const scaleX = screen.naturalWidth / rect.width;
      const scaleY = screen.naturalHeight / rect.height;
      return {
        x: Math.round((e.clientX - rect.left) * scaleX),
        y: Math.round((e.clientY - rect.top) * scaleY),
      };
    }

    function buttonName(button) {
      return button === 2 ? 'right' : button === 1 ? 'middle' : 'left';
    }

    screen.addEventListener('mousemove', (e) => socket.emit('ui-action', { type:'mouse-move', ...coords(e) }));
    screen.addEventListener('mousedown', (e) => socket.emit('ui-action', { type:'mouse-down', ...coords(e), button: buttonName(e.button) }));
    screen.addEventListener('mouseup', (e) => socket.emit('ui-action', { type:'mouse-up', ...coords(e), button: buttonName(e.button) }));
    screen.addEventListener('wheel', (e) => {
      socket.emit('ui-action', { type:'scroll', deltaX:e.deltaX, deltaY:e.deltaY });
      e.preventDefault();
    }, { passive:false });
    screen.addEventListener('contextmenu', (e) => e.preventDefault());

    screen.addEventListener('keydown', (e) => {
      socket.emit('ui-action', { type:'key-down', key:e.key });
      if (!['Tab','Meta','Control','Alt','Shift'].includes(e.key)) e.preventDefault();
    });

    screen.addEventListener('keyup', (e) => {
      socket.emit('ui-action', { type:'key-up', key:e.key });
      if (!['Tab','Meta','Control','Alt','Shift'].includes(e.key)) e.preventDefault();
    });
  </script>
</body>
</html>`);
}

async function ensureRemoteBrowserStarted() {
  ensureVirtualDisplayStarted();

  if (!chromium) {
    throw new Error('Playwright is not installed or could not be loaded');
  }

  if (remotePage && !remotePage.isClosed()) {
    return remotePage;
  }

  fs.mkdirSync(REMOTE_BROWSER_DIR, { recursive: true });
  fs.mkdirSync(REMOTE_UPLOAD_DIR, { recursive: true });

  remoteContext = await chromium.launchPersistentContext(REMOTE_BROWSER_DIR, {
    headless: false,
    viewport: {
      width: 1280,
      height: 800,
    },
    acceptDownloads: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--start-maximized',
      '--disable-gpu',
    ],
  });

  remotePage = remoteContext.pages()[0] || await remoteContext.newPage();

  remotePage.on('filechooser', async (fileChooser) => {
    pendingFileChooser = fileChooser;
    if (io) {
      io.emit('request-file-upload', {
        multiple: fileChooser.isMultiple(),
      });
    }
  });

  remoteCdpClient = await remotePage.context().newCDPSession(remotePage);
  await remoteCdpClient.send('Page.startScreencast', {
    format: 'jpeg',
    quality: 60,
    everyNthFrame: 1,
  });

  remoteCdpClient.on('Page.screencastFrame', async (frame) => {
    if (io) {
      io.emit('sync-render-image', {
        image: frame.data,
      });
    }

    try {
      await remoteCdpClient.send('Page.screencastFrameAck', {
        sessionId: frame.sessionId,
      });
    } catch {}
  });

  await remotePage.goto(AI_STUDIO_APP_URL, {
    waitUntil: 'domcontentloaded',
    timeout: 120000,
  });

  return remotePage;
}

async function handleRemoteOpen(req, res) {
  try {
    await ensureRemoteBrowserStarted();
    sendJson(res, 200, {
      ok: true,
      remoteUrl: '/remote',
      aiStudioAppUrl: AI_STUDIO_APP_URL,
      profileDir: REMOTE_BROWSER_DIR,
    });
  } catch (err) {
    sendJson(res, 500, {
      ok: false,
      error: err.message,
    });
  }
}

function setupRemoteSockets(server) {
  io = new SocketIOServer(server, {
    cors: {
      origin: '*',
    },
    maxHttpBufferSize: 50 * 1024 * 1024,
  });

  io.on('connection', (socket) => {
    console.log('[remote] socket connected');

    ensureRemoteBrowserStarted().catch((err) => {
      console.error('[remote] start failed:', err.message);
    });

    socket.on('cancel-file-upload', () => {
      pendingFileChooser = null;
    });

    socket.on('upload-file-data', async (filesData) => {
      try {
        const paths = [];

        for (const file of filesData || []) {
          const safeName = path.basename(String(file.name || `upload_${Date.now()}`));
          const filePath = path.join(REMOTE_UPLOAD_DIR, safeName);
          fs.writeFileSync(filePath, Buffer.from(file.data));
          paths.push(filePath);
        }

        if (pendingFileChooser) {
          await pendingFileChooser.setFiles(paths);
          pendingFileChooser = null;
        }
      } catch (err) {
        console.error('[remote] upload failed:', err.message);
      }
    });

    socket.on('ui-action', async (action) => {
      try {
        if (!remotePage || remotePage.isClosed()) return;

        switch (action.type) {
          case 'mouse-move':
            await remotePage.mouse.move(action.x, action.y);
            break;
          case 'mouse-down':
            await remotePage.mouse.move(action.x, action.y);
            await remotePage.mouse.down({ button: action.button || 'left' });
            break;
          case 'mouse-up':
            await remotePage.mouse.move(action.x, action.y);
            await remotePage.mouse.up({ button: action.button || 'left' });
            break;
          case 'scroll':
            await remotePage.mouse.wheel(action.deltaX || 0, action.deltaY || 0);
            break;
          case 'key-down':
            await remotePage.keyboard.down(action.key);
            break;
          case 'key-up':
            await remotePage.keyboard.up(action.key);
            break;
        }
      } catch {}
    });
  });
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

        if (Date.now() - start >= timeoutMs) {
          reject(new Error('Timeout'));
        } else {
          setTimeout(attempt, 500);
        }
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

let n8nReady = false;
let n8nChild = null;
let n8nStartingPromise = null;

const pendingQueue = [];

const proxy = httpProxy.createProxyServer({
  target: `http://127.0.0.1:${INTERNAL_N8N_PORT}`,
  ws: true,
  xfwd: true,
  changeOrigin: false,
});

proxy.on('error', (err, req, res) => {
  if (res && !res.headersSent) {
    sendText(res, 502, `Proxy error: ${err.message}`);
  }
});

proxy.on('proxyReq', (proxyReq, req) => {
  const publicUrl = detectPublicUrlFromRequest(req);

  if (publicUrl) {
    const url = new URL(publicUrl);

    proxyReq.setHeader('x-forwarded-host', url.host);
    proxyReq.setHeader('x-forwarded-proto', url.protocol.replace(':', ''));
    proxyReq.setHeader(
      'x-forwarded-port',
      url.protocol === 'https:' ? '443' : '80'
    );
  }
});

proxy.on('proxyRes', (proxyRes) => {
  proxyRes.headers['x-content-type-options'] = 'nosniff';
  proxyRes.headers['x-frame-options'] = 'SAMEORIGIN';
  proxyRes.headers['x-xss-protection'] = '1; mode=block';
  proxyRes.headers['referrer-policy'] = 'strict-origin-when-cross-origin';
  proxyRes.headers['cache-control'] =
    proxyRes.headers['cache-control'] || 'no-store';
  proxyRes.headers['strict-transport-security'] =
    'max-age=31536000; includeSubDomains';

  delete proxyRes.headers['x-powered-by'];
  delete proxyRes.headers['server'];
});

function applySecurityHeaders(res) {
  res.setHeader('x-content-type-options', 'nosniff');
  res.setHeader('x-frame-options', 'SAMEORIGIN');
  res.setHeader('x-xss-protection', '1; mode=block');
  res.setHeader('referrer-policy', 'strict-origin-when-cross-origin');
  res.setHeader(
    'strict-transport-security',
    'max-age=31536000; includeSubDomains'
  );
}

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

    console.log('[machine] MACHINE_ID:', n8nEnv.MACHINE_ID);
  console.log('[machine] N8N_BLOCK_ENV_ACCESS_IN_NODE:', n8nEnv.N8N_BLOCK_ENV_ACCESS_IN_NODE);
    console.log('[n8n-db] DB_TYPE:', n8nEnv.DB_TYPE);
    console.log('[n8n-db] DB_POSTGRESDB_HOST:', n8nEnv.DB_POSTGRESDB_HOST);
    console.log('[n8n-db] DB_POSTGRESDB_DATABASE:', n8nEnv.DB_POSTGRESDB_DATABASE);
    console.log('[n8n-db] DB_POSTGRESDB_USER:', n8nEnv.DB_POSTGRESDB_USER);
    console.log('[n8n-db] DB_POSTGRESDB_SCHEMA:', n8nEnv.DB_POSTGRESDB_SCHEMA);
    console.log('[n8n-db] DB_POSTGRESDB_SSL_ENABLED:', n8nEnv.DB_POSTGRESDB_SSL_ENABLED);
    console.log('[n8n-db] N8N_ENCRYPTION_KEY exists:', Boolean(n8nEnv.N8N_ENCRYPTION_KEY));

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

      if (!res.writableEnded) {
        proxy.web(req, res);
      }
    }
  })();

  await n8nStartingPromise;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  if (url.pathname === '/remote') {
    sendRemotePage(res);
    return;
  }

  if (url.pathname === '/api/remote/open') {
    await handleRemoteOpen(req, res);
    return;
  }

  if (url.pathname === '/api/scrape-bilibili') {
    await handleScrapeBilibiliRequest(req, res);
    return;
  }

  if (url.pathname === '/ram') {
    await handleRamRequest(req, res);
    return;
  }

  if (!n8nReady) {
    applySecurityHeaders(res);

    const timer = setTimeout(() => {
      if (!res.writableEnded) {
        sendText(res, 503, 'n8n is starting, please retry');
      }
    }, 60000);

    pendingQueue.push({
      req,
      res,
      timer,
    });

    const publicUrlFromRequest =
      detectPublicUrlFromRequest(req) ||
      detectPublicUrlFromEnv();

    ensureN8nStarted(publicUrlFromRequest).catch((err) => {
      console.error('[n8n] failed to start:', err);

      while (pendingQueue.length) {
        const item = pendingQueue.shift();

        clearTimeout(item.timer);

        if (!item.res.writableEnded) {
          sendText(item.res, 500, `n8n failed to start: ${err.message}`);
        }
      }
    });

    return;
  }

  proxy.web(req, res);
});

setupRemoteSockets(server);

server.on('upgrade', (req, socket, head) => {
  if (req.url && req.url.startsWith('/socket.io/')) {
    return;
  }

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

  if (xvfbChild && !xvfbChild.killed) {
    try {
      xvfbChild.kill('SIGTERM');
    } catch {}
  }

  process.exit(code);
}

process.on('SIGTERM', () => shutdown(0));
process.on('SIGINT', () => shutdown(0));

(async () => {
  await new Promise((resolve) => {
    server.listen(PUBLIC_PORT, '0.0.0.0', () => {
      console.log(`[wrapper] listening on 0.0.0.0:${PUBLIC_PORT}`);
      resolve();
    });
  });

  const initialPublicUrl = detectPublicUrlFromEnv();

  if (initialPublicUrl) {
    await ensureN8nStarted(initialPublicUrl);
  } else {
    console.log(
      '[wrapper] No public URL env found. Waiting first public request to detect domain before starting n8n.'
    );
  }
})();
EOF

RUN chown -R node:node /app /home/node

USER node

EXPOSE 8080

ENTRYPOINT ["node", "/app/server.js"]
