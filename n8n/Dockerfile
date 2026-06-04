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
    NODE_FUNCTION_ALLOW_BUILTIN=* \
    NODE_FUNCTION_ALLOW_EXTERNAL=* \
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

    if (renderHostMatch) {
      return renderHostMatch[1];
    }

    if (process.env.MACHINE_ID) {
      return process.env.MACHINE_ID;
    }

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
        .filter((iface) => iface && !iface.internal && iface.family === 'IPv4')
        .map((iface) => iface.address)
        .join('_');

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
    mongoose.models.CostHistory ||
    mongoose.model('CostHistory', schema);

  return mongoose;
}

async function connectToMongo() {
  if (!MONGODB_URI) return false;

  const lib = loadMongoose();

  if (lib.connection.readyState >= 1) {
    return true;
  }

  let uri = MONGODB_URI;

  try {
    const u = new URL(MONGODB_URI);
    u.pathname = `/${TARGET_DB}`;
    uri = u.toString();
  } catch {
    const [base, qs] = MONGODB_URI.split('?');

    uri =
      `${base.replace(/\/+$/, '')}/${TARGET_DB}` +
      `?${qs || 'retryWrites=true&w=majority'}`;
  }

  await lib.connect(uri);

  return true;
}

async function migrateCostHistoryIndexes() {
  if (!mongoose?.connection?.db) return;

  try {
    const collection = mongoose.connection.db.collection('costhistories');
    const indexes = await collection.indexes();

    const hasOldMonthIndex = indexes.some((idx) => idx.name === 'month_1');

    if (hasOldMonthIndex) {
      console.log('[RAM API] Dropping obsolete unique index month_1...');
      await collection.dropIndex('month_1');
      console.log('[RAM API] Dropped obsolete unique index month_1');
    }
  } catch (err) {
    console.warn('[RAM API] Failed to check/drop old index:', err.message);
  }
}

const toMB = (bytes) => (bytes / 1024 / 1024).toFixed(2);
const toGB = (bytes) => (bytes / 1024 / 1024 / 1024).toFixed(2);

// Railway pricing x2.
// Memory/CPU are calculated per minute; network is calculated per outbound GB.
const RAILWAY_X2_PRICING = {
  memoryPerGBMinute: 0.000231 * 2,
  cpuPerVCPUMinute: 0.000463 * 2,
  egressPerGB: 0.05 * 2,
};

function money(value) {
  return `$${Number(value || 0).toFixed(4)}`;
}

function bytesToGBNumber(bytes) {
  return Number(bytes || 0) / 1024 / 1024 / 1024;
}

function buildRailwayX2Cost(record) {
  const memoryGBMinutes = Number(record.accumulatedMemoryMinutes || 0);
  const cpuVCPUMinutes = Number(record.accumulatedCpuMinutes || 0);
  const egressGB = bytesToGBNumber(record.accumulatedEgressBytes);

  const memoryCost = memoryGBMinutes * RAILWAY_X2_PRICING.memoryPerGBMinute;
  const cpuCost = cpuVCPUMinutes * RAILWAY_X2_PRICING.cpuPerVCPUMinute;
  const networkCost = egressGB * RAILWAY_X2_PRICING.egressPerGB;
  const totalCost = memoryCost + cpuCost + networkCost;

  return {
    pricing: {
      provider: 'Railway',
      multiplier: 'x2',
      memoryPerGBMinute: `$${RAILWAY_X2_PRICING.memoryPerGBMinute}`,
      cpuPerVCPUMinute: `$${RAILWAY_X2_PRICING.cpuPerVCPUMinute}`,
      egressPerGB: `$${RAILWAY_X2_PRICING.egressPerGB}`,
    },
    usage: {
      memoryGBMinutes: memoryGBMinutes.toFixed(2),
      cpuVCPUMinutes: cpuVCPUMinutes.toFixed(2),
      egressGB: egressGB.toFixed(4),
    },
    memoryCost: money(memoryCost),
    cpuCost: money(cpuCost),
    networkCost: money(networkCost),
    egressCost: money(networkCost),
    totalCost: money(totalCost),
  };
}

function safeExec(cmd) {
  try {
    return execSync(cmd, {
      stdio: ['ignore', 'pipe', 'pipe'],
    }).toString().trim();
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
    (hrEnd[0] * 1e9 +
      hrEnd[1] -
      (hrStart[0] * 1e9 + hrStart[1])) /
    1e6;

  const elapUserMS = endUsage.user / 1000;
  const elapSystMS = endUsage.system / 1000;

  const cpuPercentNode =
    elapTimeMS > 0
      ? (((elapUserMS + elapSystMS) / elapTimeMS) * 100).toFixed(2)
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

  const cpuPercentSystem =
    totalDiff > 0
      ? ((1 - idleDiff / totalDiff) * 100).toFixed(2)
      : '0.00';

  return {
    nodeProcess: `${cpuPercentNode}%`,
    systemTotal: `${cpuPercentSystem}%`,
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
    try {
      const freeOutput = safeExec('free -h');
      if (freeOutput) {
        stats.freeCommandOutput = freeOutput;
      }

      const ps = safeExec('ps aux --sort=-%mem | head -n 6');
      if (ps) {
        stats.topProcesses = ps.split('\n');
      }
    } catch (e) {
      stats.diagnosticError = String(e);
    }

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
      .filter((iface) => iface && !iface.internal && iface.family === 'IPv4')
      .map((iface) => iface.address),
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

    const currentMonthStr =
      `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

    const projectName = getProjectName();

    let currentTxBytes = 0;

    if (process.platform === 'linux') {
      try {
        const txPath = '/sys/class/net/eth0/statistics/tx_bytes';

        if (fs.existsSync(txPath)) {
          currentTxBytes = parseInt(
            fs.readFileSync(txPath, 'utf8').trim(),
            10
          );
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
      (now.getTime() -
        new Date(record.lastMeasurementTime).getTime()) /
      60000;

    if (minutesElapsed > 0.01) {
      const currentRssGB = rssBytes / 1024 / 1024 / 1024;

      record.accumulatedMemoryMinutes += currentRssGB * minutesElapsed;

      const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1);
      record.accumulatedCpuMinutes += allocatedCpu * minutesElapsed;

      let deltaEgressBytes = 0;

      if (
        currentTxBytes > 0 &&
        record.lastTxBytes > 0 &&
        currentTxBytes >= record.lastTxBytes
      ) {
        deltaEgressBytes = currentTxBytes - record.lastTxBytes;
      }

      record.accumulatedEgressBytes += deltaEgressBytes;
      record.lastTxBytes =
        currentTxBytes > 0 ? currentTxBytes : record.lastTxBytes;
      record.lastMeasurementTime = now;

      const railwayX2Cost = buildRailwayX2Cost(record);

      record.memoryCost = Number(
        railwayX2Cost.memoryCost.replace(/[^0-9.]/g, '')
      );

      record.cpuCost = Number(
        railwayX2Cost.cpuCost.replace(/[^0-9.]/g, '')
      );

      record.egressCost = Number(
        railwayX2Cost.egressCost.replace(/[^0-9.]/g, '')
      );

      record.totalCost = Number(
        railwayX2Cost.totalCost.replace(/[^0-9.]/g, '')
      );

      await record.save();
    }

    const allocatedCpu = Number(process.env.ALLOCATED_CPU || 0.1);
    const activeMinutes =
      allocatedCpu > 0
        ? record.accumulatedCpuMinutes / allocatedCpu
        : 0;

    const d = Math.floor(activeMinutes / 1440);
    const h = Math.floor((activeMinutes % 1440) / 60);
    const m = Math.floor(activeMinutes % 60);

    const currentCost = {
      projectName: record.projectName,
      machineId: record.projectName,
      month: record.month,

      runningDuration: `${d}d ${h}h ${m}m`,
      runningDays: `${(activeMinutes / 1440).toFixed(2)} days`,

      updatedAt: new Date(record.lastMeasurementTime).toISOString(),
      lastMeasurementTime: new Date(record.lastMeasurementTime).toISOString(),

      accumulatedMemoryGBMinutes:
        record.accumulatedMemoryMinutes.toFixed(2),

      accumulatedCpuVCPUMinutes:
        record.accumulatedCpuMinutes.toFixed(2),

      accumulatedEgressGB:
        (record.accumulatedEgressBytes / 1024 / 1024 / 1024).toFixed(4),

      memoryCost: money(record.memoryCost),
      cpuCost: money(record.cpuCost),
      egressCost: money(record.egressCost),
      networkCost: money(record.egressCost),
      totalCost: money(record.totalCost),

      railwayX2Cost: buildRailwayX2Cost(record),
    };

    const history = await CostHistory
      .find({
        projectName,
      })
      .sort({
        month: -1,
      })
      .limit(5);

    const last5MonthsHistory = history.map((hist) => {
      const histActiveMinutes =
        allocatedCpu > 0
          ? hist.accumulatedCpuMinutes / allocatedCpu
          : 0;

      const hd = Math.floor(histActiveMinutes / 1440);
      const hh = Math.floor((histActiveMinutes % 1440) / 60);
      const hm = Math.floor(histActiveMinutes % 60);

      return {
        projectName: hist.projectName,
        machineId: hist.projectName,
        month: hist.month,

        runningDuration: `${hd}d ${hh}h ${hm}m`,

        memoryCost: money(hist.memoryCost),
        cpuCost: money(hist.cpuCost),
        egressCost: money(hist.egressCost),
        networkCost: money(hist.egressCost),
        totalCost: money(hist.totalCost),

        railwayX2Cost: buildRailwayX2Cost(hist),
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
  const url = new URL(
    req.url,
    `http://${req.headers.host || '127.0.0.1'}`
  );

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

    ...(stats.diagnosticError
      ? {
          diagnosticError: stats.diagnosticError,
        }
      : {}),

    projectCost: {
      currentMonth: projectCost.currentMonth,
      last5MonthsHistory: projectCost.last5MonthsHistory,
      pricing: {
        provider: 'Railway',
        multiplier: 'x2',
        memoryPerGBMinute: `$${RAILWAY_X2_PRICING.memoryPerGBMinute}`,
        cpuPerVCPUMinute: `$${RAILWAY_X2_PRICING.cpuPerVCPUMinute}`,
        egressPerGB: `$${RAILWAY_X2_PRICING.egressPerGB}`,
      },

      ...(projectCost.error
        ? {
            error: projectCost.error,
          }
        : {}),

      ...(projectCost.disabled
        ? {
            disabled: projectCost.disabled,
          }
        : {}),
    },
  });
}

function normalizePublicBaseUrl(raw) {
  if (!raw) return '';

  let value = String(raw).trim();
  if (!value) return '';

  if (!/^https?:\/\//i.test(value)) {
    value = `https://${value}`;
  }

  return value.replace(/\/+$/, '');
}

function startN8n() {
  const forwardedPublicUrl =
    process.env.PUBLIC_DOMAIN ||
    process.env.PUBLIC_URL ||
    process.env.N8N_PUBLIC_URL ||
    process.env.RENDER_EXTERNAL_URL ||
    process.env.RAILWAY_PUBLIC_DOMAIN ||
    process.env.WEBHOOK_URL ||
    process.env.N8N_EDITOR_BASE_URL ||
    '';

  const publicBaseUrl = normalizePublicBaseUrl(forwardedPublicUrl);
  let publicHost = '';
  let publicProtocol = 'https';

  if (publicBaseUrl) {
    try {
      const parsed = new URL(publicBaseUrl);
      publicHost = parsed.host;
      publicProtocol = parsed.protocol.replace(':', '') || 'https';
    } catch {}
  }

  const n8nEnv = {
    ...process.env,
    N8N_PORT: String(INTERNAL_N8N_PORT),
    N8N_LISTEN_ADDRESS: '127.0.0.1',

    ...(publicBaseUrl
      ? {
          WEBHOOK_URL: `${publicBaseUrl}/`,
          N8N_EDITOR_BASE_URL: publicBaseUrl,
          N8N_HOST: publicHost,
          N8N_PROTOCOL: publicProtocol,
        }
      : {}),
  };

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
          reject(new Error(`Timeout waiting for ${host}:${port}`));
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
const pendingQueue = [];

const proxy = httpProxy.createProxyServer({
  target: `http://127.0.0.1:${INTERNAL_N8N_PORT}`,
  ws: true,
  xfwd: true,
});

proxy.on('error', (err, req, res) => {
  console.error(`[proxy] ${err.message}`);

  if (res && !res.headersSent) {
    sendText(res, 502, `Proxy error: ${err.message}`);
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

  proxyRes.headers['content-security-policy'] = [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data:",
    "connect-src 'self' wss: ws: https:",
    "frame-ancestors 'self'",
  ].join('; ');

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

const server = http.createServer(async (req, res) => {
  const url = new URL(
    req.url,
    `http://${req.headers.host || '127.0.0.1'}`
  );

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
    }, 30000);

    pendingQueue.push({
      req,
      res,
      timer,
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

let n8nChild = null;

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
      console.log(`[wrapper] Port ${PUBLIC_PORT} open — waiting for n8n...`);
      resolve();
    });
  });

  n8nChild = startN8n();

  try {
    await waitForPort(INTERNAL_N8N_PORT, '127.0.0.1');
  } catch (err) {
    console.error(`[wrapper] ${err.message}`);
    shutdown(1);
    return;
  }

  console.log('[wrapper] n8n ready — serving traffic');

  n8nReady = true;

  while (pendingQueue.length) {
    const { req, res, timer } = pendingQueue.shift();

    clearTimeout(timer);

    if (!res.writableEnded) {
      proxy.web(req, res);
    }
  }
})();
EOF

RUN chown -R node:node /app /home/node

USER node

EXPOSE 8080

ENTRYPOINT ["node", "/app/server.js"]
