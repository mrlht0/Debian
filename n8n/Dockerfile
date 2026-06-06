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
  NODE_FUNCTION_ALLOW_EXTERNAL=mongodb,playwright \
  NODE_FUNCTION_ALLOW_BUILTIN=* \
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
const crypto = require('node:crypto');
const httpProxy = require('http-proxy');

const PUBLIC_PORT = Number(process.env.PORT || 8080);
const INTERNAL_N8N_PORT = Number(process.env.N8N_PORT || 5678);

const RAM_TOKEN = process.env.RAM_TOKEN || '';
const MONGODB_URI = process.env.MONGODB_URI || '';
const TARGET_DB = process.env.TARGET_DB || 'application-manager';

// n8n database chính: PostgreSQL/Supabase.
// Dữ liệu n8n như user đăng nhập, workflows, credentials, OAuth token, settings
// sẽ được lưu trong PostgreSQL thay vì /home/node/.n8n/database.sqlite.
// RAM/cost/network vẫn dùng MONGODB_URI riêng ở trên, không dùng PostgreSQL này.
const N8N_DATA_DIR = process.env.N8N_USER_FOLDER || '/home/node/.n8n';

const DEFAULT_N8N_POSTGRES = {
  host: 'db.jiewotcsywbwiuxtpwpm.supabase.co',
  port: '5432',
  database: 'postgres',
  user: 'postgres',
  // Mật khẩu có ký tự @ nên không parse bằng URL thô; để riêng ở đây sẽ đúng hơn.
  password: 'Ty48216965@',
};

const DERIVED_N8N_ENCRYPTION_KEY = crypto
  .createHash('sha256')
  .update(
    process.env.N8N_ENCRYPTION_KEY ||
      process.env.DB_POSTGRESDB_PASSWORD ||
      DEFAULT_N8N_POSTGRES.password
  )
  .digest('hex');

let mongoose = null;
let CostHistory = null;

function getProjectName() {
  // Ưu tiên tên cố định người dùng tự đặt.
  // Railway đổi hostname sau mỗi redeploy, nên không dùng hostname làm ID chính nếu có Railway service env.
  try {
    if (process.env.MACHINE_ID) {
      return process.env.MACHINE_ID;
    }

    if (process.env.RAILWAY_SERVICE_ID) {
      return `railway_${process.env.RAILWAY_SERVICE_ID}`;
    }

    if (process.env.RAILWAY_PROJECT_ID && process.env.RAILWAY_SERVICE_NAME) {
      return `railway_${process.env.RAILWAY_PROJECT_ID}_${process.env.RAILWAY_SERVICE_NAME}`;
    }

    if (process.env.RENDER_SERVICE_ID) {
      return `render_${process.env.RENDER_SERVICE_ID}`;
    }

    if (process.env.RENDER_EXTERNAL_URL) {
      try {
        return `render_${new URL(process.env.RENDER_EXTERNAL_URL).hostname}`;
      } catch {}
    }

    const host = os.hostname();

    const renderHostMatch = host.match(/^(srv-[a-z0-9]+)/);
    if (renderHostMatch) return `render_${renderHostMatch[1]}`;

    const genericHosts = [
      'localhost',
      '127.0.0.1',
      'desktop',
      'laptop',
      'server',
    ];

    const isGeneric =
      genericHosts.some((g) => host.toLowerCase().includes(g)) ||
      host.length < 3;

    if (isGeneric) {
      let packageJsonName = 'unknown';

      try {
        const packageJsonPath = path.join(process.cwd(), 'package.json');

        if (fs.existsSync(packageJsonPath)) {
          const packageJson = JSON.parse(
            fs.readFileSync(packageJsonPath, 'utf8')
          );

          packageJsonName = packageJson.name || 'unknown';
        }
      } catch {}

      const ips = Object.values(os.networkInterfaces())
        .flat()
        .filter((f) => f && !f.internal && f.family === 'IPv4')
        .map((f) => f.address)
        .join('_');

      return `${host}_${packageJsonName}_${ips || 'noip'}`;
    }

    return host;
  } catch {
    return (
      process.env.MACHINE_ID ||
      process.env.RAILWAY_SERVICE_ID ||
      process.env.RENDER_SERVICE_ID ||
      os.hostname() ||
      'unknown'
    );
  }
}

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
  const hrStart = process.hrtime();

  await new Promise((resolve) => setTimeout(resolve, 100));

  const endCpu = os.cpus();
  const endUsage = process.cpuUsage(startUsage);
  const hrEnd = process.hrtime();

  const elapTimeMS =
    (hrEnd[0] * 1e9 + hrEnd[1] - (hrStart[0] * 1e9 + hrStart[1])) /
    1e6;

  const cpuPercentNode =
    elapTimeMS > 0
      ? (
          ((endUsage.user / 1000 + endUsage.system / 1000) / elapTimeMS) *
          100
        ).toFixed(2)
      : '0.00';

  let totalDiff = 0;
  let idleDiff = 0;

  for (let i = 0; i < startCpu.length; i++) {
    const s = startCpu[i].times;
    const e = endCpu[i].times;

    totalDiff +=
      e.user +
      e.nice +
      e.sys +
      e.idle +
      e.irq -
      (s.user + s.nice + s.sys + s.idle + s.irq);

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

    let currentTxBytes = 0;

    if (process.platform === 'linux') {
      try {
        const txPath = '/sys/class/net/eth0/statistics/tx_bytes';

        if (fs.existsSync(txPath)) {
          currentTxBytes = parseInt(fs.readFileSync(txPath, 'utf8').trim(), 10);
        }
      } catch {}
    }

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

function parsePostgresUrl(raw) {
  if (!raw) return null;

  try {
    const url = new URL(raw);

    return {
      host: url.hostname,
      port: url.port || '5432',
      database: url.pathname.replace(/^\//, '') || 'postgres',
      user: decodeURIComponent(url.username || 'postgres'),
      password: decodeURIComponent(url.password || ''),
    };
  } catch {
    return null;
  }
}

function getN8nPostgresConfig() {
  // Có thể override bằng DATABASE_URL/POSTGRES_URL nếu sau này đổi database.
  // Lưu ý: nếu password chứa @ thì trong URL phải encode thành %40.
  const parsed =
    parsePostgresUrl(process.env.DATABASE_URL) ||
    parsePostgresUrl(process.env.POSTGRES_URL) ||
    parsePostgresUrl(process.env.POSTGRESQL_URL) ||
    parsePostgresUrl(process.env.DB_POSTGRESDB_URL);

  return {
    host:
      process.env.DB_POSTGRESDB_HOST ||
      parsed?.host ||
      DEFAULT_N8N_POSTGRES.host,
    port:
      process.env.DB_POSTGRESDB_PORT ||
      parsed?.port ||
      DEFAULT_N8N_POSTGRES.port,
    database:
      process.env.DB_POSTGRESDB_DATABASE ||
      parsed?.database ||
      DEFAULT_N8N_POSTGRES.database,
    user:
      process.env.DB_POSTGRESDB_USER ||
      parsed?.user ||
      DEFAULT_N8N_POSTGRES.user,
    password:
      process.env.DB_POSTGRESDB_PASSWORD ||
      parsed?.password ||
      DEFAULT_N8N_POSTGRES.password,
  };
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
      n8nEnv.N8N_SECURE_COOKIE = process.env.N8N_SECURE_COOKIE || 'true';
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

function buildN8nEnv(publicUrlInput = '') {
  const pg = getN8nPostgresConfig();

  const n8nEnv = {
    ...process.env,

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

    N8N_USER_FOLDER:
      process.env.N8N_USER_FOLDER || N8N_DATA_DIR,

    // PostgreSQL là database chính của n8n.
    // Build/redeploy container mới vẫn giữ user, login, workflows, credentials và OAuth token.
    DB_TYPE: process.env.DB_TYPE || 'postgresdb',
    DB_POSTGRESDB_HOST: pg.host,
    DB_POSTGRESDB_PORT: String(pg.port),
    DB_POSTGRESDB_DATABASE: pg.database,
    DB_POSTGRESDB_USER: pg.user,
    DB_POSTGRESDB_PASSWORD: pg.password,
    DB_POSTGRESDB_SCHEMA: process.env.DB_POSTGRESDB_SCHEMA || 'public',
    DB_POSTGRESDB_SSL_ENABLED:
      process.env.DB_POSTGRESDB_SSL_ENABLED || 'true',
    DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED:
      process.env.DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED || 'false',

    // Cố định key để credentials/OAuth token giải mã được sau redeploy.
    // Tốt nhất nên set N8N_ENCRYPTION_KEY riêng; nếu không có thì tự derive ổn định từ mật khẩu PostgreSQL.
    N8N_ENCRYPTION_KEY:
      process.env.N8N_ENCRYPTION_KEY || DERIVED_N8N_ENCRYPTION_KEY,

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

  const child = spawn('n8n', ['start'], {
    stdio: 'inherit',
    env: n8nEnv,
  });

  child.on('exit', (code, signal) => {
    process.exit(signal ? 1 : code ?? 0);
  });

  return child;
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
    proxyReq.setHeader('x-forwarded-port', url.protocol === 'https:' ? '443' : '80');
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
    n8nChild = startN8n(publicUrlInput);

    if (!n8nChild) {
      n8nStartingPromise = null;
      return;
    }

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
