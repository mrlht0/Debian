# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/playwright:v1.56.1-noble

ENV PORT=8080 \
    RAM_TOKEN=cliply_ram_secret_token_2026 \
    DISPLAY=:99 \
    NOVNC_INTERNAL_PORT=6080 \
    VNC_INTERNAL_PORT=5900 \
    BROWSER_PROFILE_DIR=/data/playwright/browser-profile

WORKDIR /app
USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      xvfb \
      fluxbox \
      x11vnc \
      x11-xserver-utils \
      procps \
      novnc \
      websockify \
      xterm \
      x11-apps \
      ca-certificates \
      fonts-liberation \
      fonts-noto \
      fonts-noto-cjk \
      bash \
      curl \
    && rm -rf /var/lib/apt/lists/* \
    && if ! id -u node >/dev/null 2>&1; then useradd -m -s /bin/bash node; fi \
    && npm init -y >/dev/null 2>&1 \
    && npm install --no-package-lock --no-save --no-audit --no-fund \
      http-proxy playwright playwright-core playwright-extra puppeteer-extra-plugin-stealth

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
const DISPLAY_NUM = process.env.DISPLAY || ':99';
const NOVNC_PORT = Number(process.env.NOVNC_INTERNAL_PORT || 6080);
const VNC_PORT = Number(process.env.VNC_INTERNAL_PORT || 5900);
const RAM_TOKEN = process.env.RAM_TOKEN || 'cliply_ram_secret_token_2026';
const BROWSER_PROFILE_DIR = process.env.BROWSER_PROFILE_DIR || '/data/playwright/browser-profile';
const UPLOAD_DIR = '/app/uploads';
const NOVNC_READY_PATH = '/novnc/vnc.html?autoconnect=true&resize=scale&path=websockify';

const childProcesses = [];
let browserContext = null;
let browserPage = null;
let xvfbProcess = null;
let fluxboxProcess = null;
let x11vncProcess = null;
let websockifyProcess = null;

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

const novncProxy = httpProxy.createProxyServer({
  target: `http://127.0.0.1:${NOVNC_PORT}`,
  ws: true,
  xfwd: true,
  changeOrigin: false,
});

novncProxy.on('error', (err, req, res) => {
  if (res && !res.headersSent) {
    sendText(res, 502, `noVNC proxy error: ${err.message}`);
  }
});

function spawnManaged(name, command, args, options = {}) {
  const child = spawn(command, args, {
    stdio: options.stdio || ['ignore', 'ignore', 'pipe'],
    env: options.env || process.env,
    detached: false,
  });
  child.on('exit', () => {});
  if (child.stderr) {
    child.stderr.on('data', (buf) => {
      const msg = String(buf).trim();
      if (msg) console.log(`[${name}] ${msg}`);
    });
  }
  childProcesses.push(child);
  return child;
}

function isChildAlive(child) {
  return Boolean(child && !child.killed && child.exitCode === null && child.signalCode === null);
}

async function waitMs(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeFileIfMissing(filePath, content) {
  if (!fs.existsSync(filePath)) {
    fs.writeFileSync(filePath, content, 'utf8');
  }
}

function shellOk(command) {
  try {
    execSync(command, { stdio: 'ignore', shell: '/bin/bash' });
    return true;
  } catch {
    return false;
  }
}

function displayId() {
  return String(DISPLAY_NUM).replace(/^:/, '').split('.')[0] || '99';
}

function isDisplayResponsive() {
  return shellOk(`DISPLAY=${DISPLAY_NUM} timeout 2 xset q`);
}

function cleanupStaleDisplay() {
  if (isDisplayResponsive()) return;
  const id = displayId();
  try {
    execSync(`pkill -f "Xvfb ${DISPLAY_NUM}" || true`, { stdio: 'ignore', shell: '/bin/bash' });
  } catch {}
  try {
    fs.rmSync(`/tmp/.X${id}-lock`, { force: true });
    fs.rmSync(`/tmp/.X11-unix/X${id}`, { force: true });
  } catch {}
}

function isPortOpen(port) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host: '127.0.0.1', port, timeout: 800 }, () => {
      socket.destroy();
      resolve(true);
    });
    socket.on('error', () => resolve(false));
    socket.on('timeout', () => {
      socket.destroy();
      resolve(false);
    });
  });
}

async function ensureDesktopServices() {
  ensureDir('/data/playwright');
  ensureDir('/home/node/.fluxbox');
  ensureDir(BROWSER_PROFILE_DIR);
  ensureDir(UPLOAD_DIR);
  ensureDir('/tmp/.X11-unix');

  writeFileIfMissing(
    '/home/node/.fluxbox/init',
    [
      'session.screen0.toolbar.visible:        false',
      'session.screen0.slit.visible:           false',
      'session.screen0.workspaces:             1',
      'session.screen0.focusModel:             ClickFocus',
      'session.screen0.windowPlacement:        RowSmartPlacement',
      '',
    ].join('\n')
  );
  writeFileIfMissing('/home/node/.fluxbox/startup', '#!/bin/sh\nexec fluxbox\n');

  process.env.DISPLAY = DISPLAY_NUM;
  cleanupStaleDisplay();

  if (!isDisplayResponsive() && !isChildAlive(xvfbProcess)) {
    xvfbProcess = spawnManaged('xvfb', 'Xvfb', [
      DISPLAY_NUM,
      '-screen',
      '0',
      '1365x900x24',
      '-ac',
      '+extension',
      'RANDR',
      '-nolisten',
      'tcp',
    ]);
    for (let i = 0; i < 20; i++) {
      if (isDisplayResponsive()) break;
      await waitMs(300);
    }
  }

  if (!isDisplayResponsive()) throw new Error(`X server ${DISPLAY_NUM} is not ready`);

  if (!isChildAlive(fluxboxProcess)) {
    fluxboxProcess = spawnManaged('fluxbox', 'fluxbox', [], {
      env: { ...process.env, DISPLAY: DISPLAY_NUM, HOME: '/home/node' },
    });
    await waitMs(500);
  }

  if (!isChildAlive(x11vncProcess) || !(await isPortOpen(VNC_PORT))) {
    x11vncProcess = spawnManaged('x11vnc', 'x11vnc', [
      '-display',
      DISPLAY_NUM,
      '-rfbport',
      String(VNC_PORT),
      '-forever',
      '-shared',
      '-nopw',
      '-noxdamage',
      '-o',
      '/tmp/x11vnc.log',
    ]);
    for (let i = 0; i < 20; i++) {
      if (await isPortOpen(VNC_PORT)) break;
      await waitMs(300);
    }
  }

  const novncWeb = ['/usr/share/novnc', '/usr/share/noVNC', '/usr/share/webapps/novnc']
    .find((item) => fs.existsSync(item)) || '/usr/share/novnc';

  if (!isChildAlive(websockifyProcess) || !(await isPortOpen(NOVNC_PORT))) {
    websockifyProcess = spawnManaged('websockify', 'websockify', [
      '--web',
      novncWeb,
      '--heartbeat',
      '30',
      String(NOVNC_PORT),
      `127.0.0.1:${VNC_PORT}`,
    ]);
    for (let i = 0; i < 20; i++) {
      if (await isPortOpen(NOVNC_PORT)) break;
      await waitMs(300);
    }
  }
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
  const pids = new Set([process.pid]);
  for (const child of childProcesses) {
    if (child?.pid) pids.add(child.pid);
  }
  const pidList = [...pids];
  const output = safeExec(`ps -o pid=,rss=,args= -p ${pidList.join(',')}`);
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
  await waitMs(100);
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

async function buildMonitorStats() {
  const mem = process.memoryUsage();
  const tracked = getTrackedProcessStats();
  const cgroup = getCgroupStats();
  const txBytes = getCurrentTxBytes();
  const rxBytes = getCurrentRxBytes();
  const cpu = await measureCpuPercent();
  return {
    identity: {
      service: 'playwright-only',
      hostname: os.hostname(),
      platform: os.platform(),
      arch: os.arch(),
    },
    cpu,
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
    topProcesses: safeExec('ps aux --sort=-%mem | head -n 10').split('\n').filter(Boolean),
    timestamp: new Date().toISOString(),
  };
}

function findPlaywrightBundledChromium() {
  const roots = [
    process.env.PLAYWRIGHT_BROWSERS_PATH,
    '/ms-playwright',
  ].filter(Boolean);

  for (const root of roots) {
    try {
      if (!fs.existsSync(root)) continue;
      const dirs = fs.readdirSync(root).filter((name) => name.startsWith('chromium'));
      for (const dir of dirs) {
        const candidates = [
          path.join(root, dir, 'chrome-linux', 'chrome'),
          path.join(root, dir, 'chrome-linux-headless-shell', 'headless_shell'),
        ];
        for (const candidate of candidates) {
          if (fs.existsSync(candidate)) return candidate;
        }
      }
    } catch {}
  }

  return '';
}

function getChromeExecutablePath() {
  const candidates = [
    process.env.GOOGLE_CHROME_BIN,
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/opt/google/chrome/chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    findPlaywrightBundledChromium(),
  ];
  return candidates.find((candidate) => candidate && fs.existsSync(candidate)) || '';
}

async function startBrowser(targetUrl) {
  await ensureDesktopServices();
  if (browserContext) {
    if (targetUrl && browserPage) {
      await browserPage.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 90000 }).catch(() => {});
    }
    return { ok: true, reused: true, noVncPath: NOVNC_READY_PATH, url: targetUrl || browserPage?.url() || '' };
  }

  const chromePath = getChromeExecutablePath();
  if (!chromePath) throw new Error('Chrome executable not found');

  const { chromium } = require('playwright-extra');
  const StealthPlugin = require('puppeteer-extra-plugin-stealth');
  chromium.use(StealthPlugin());

  browserContext = await chromium.launchPersistentContext(BROWSER_PROFILE_DIR, {
    headless: false,
    executablePath: chromePath,
    args: [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--disable-software-rasterizer',
      '--window-size=1365,900',
      '--start-maximized',
      '--no-first-run',
      '--no-default-browser-check',
      '--password-store=basic',
      '--use-mock-keychain',
    ],
    viewport: { width: 1365, height: 900 },
    env: { ...process.env, DISPLAY: DISPLAY_NUM, HOME: '/home/node' },
  });

  browserContext.on('close', () => {
    browserContext = null;
    browserPage = null;
  });

  browserPage = browserContext.pages()[0] || await browserContext.newPage();
  if (targetUrl) {
    await browserPage.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 90000 }).catch(() => {});
  }
  return { ok: true, reused: false, noVncPath: NOVNC_READY_PATH, url: targetUrl || browserPage.url() || '' };
}

async function closeBrowser() {
  if (browserPage) {
    await browserPage.close().catch(() => {});
    browserPage = null;
  }
  if (browserContext) {
    await browserContext.close().catch(() => {});
    browserContext = null;
  }
  return { ok: true };
}

async function readBody(req) {
  return await new Promise((resolve) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', () => resolve(Buffer.alloc(0)));
  });
}

async function readJsonBody(req) {
  const body = await readBody(req);
  try {
    return body.length ? JSON.parse(body.toString('utf8')) : {};
  } catch {
    return {};
  }
}

async function saveUploadedFile(req) {
  ensureDir(UPLOAD_DIR);
  const body = await readJsonBody(req);
  const fileName = path.basename(String(body.fileName || 'upload.bin'));
  const targetPath = path.join(UPLOAD_DIR, `${Date.now()}-${fileName}`);
  const content = body.base64 ? Buffer.from(String(body.base64), 'base64') : Buffer.alloc(0);
  fs.writeFileSync(targetPath, content);
  return {
    ok: true,
    fileName,
    path: targetPath,
    sizeBytes: content.length,
  };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  if (url.pathname === '/' || url.pathname === '/healthz') {
    sendJson(res, 200, { ok: true, service: 'playwright-only', browserRunning: Boolean(browserContext) });
    return;
  }

  if (url.pathname === '/ram') {
    const token = url.searchParams.get('token') || req.headers['x-ram-token'];
    if (RAM_TOKEN && token !== RAM_TOKEN) {
      sendJson(res, 401, { error: 'Unauthorized' });
      return;
    }
    sendJson(res, 200, await buildMonitorStats());
    return;
  }

  if (url.pathname === '/api/browser/start' && req.method === 'POST') {
    try {
      const body = await readJsonBody(req);
      sendJson(res, 200, await startBrowser(body.url || ''));
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  if (url.pathname === '/api/browser/close' && req.method === 'POST') {
    sendJson(res, 200, await closeBrowser());
    return;
  }

  if (url.pathname === '/api/browser/status') {
    sendJson(res, 200, {
      ok: true,
      browserRunning: Boolean(browserContext),
      currentUrl: browserPage?.url() || '',
      noVncPath: NOVNC_READY_PATH,
    });
    return;
  }

  if (url.pathname === '/api/files/upload' && req.method === 'POST') {
    try {
      sendJson(res, 200, await saveUploadedFile(req));
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  if (url.pathname === '/novnc' || url.pathname === '/novnc/') {
    try {
      await startBrowser(url.searchParams.get('url') || '');
      res.writeHead(302, { Location: NOVNC_READY_PATH });
      res.end();
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  if (url.pathname === '/novnc/package.json') {
    sendJson(res, 200, { name: 'novnc', version: 'container' });
    return;
  }

  if (url.pathname === '/websockify' || url.pathname.startsWith('/novnc/')) {
    try {
      await ensureDesktopServices();
      if (url.pathname.startsWith('/novnc/')) {
        req.url = req.url.replace(/^\/novnc/, '') || '/';
      }
      novncProxy.web(req, res);
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  sendJson(res, 404, { ok: false, error: 'Not found' });
});

server.on('upgrade', (req, socket, head) => {
  const reqUrl = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  if (reqUrl.pathname === '/websockify' || reqUrl.pathname.startsWith('/novnc/')) {
    ensureDesktopServices()
      .then(() => {
        if (reqUrl.pathname.startsWith('/novnc/')) {
          req.url = req.url.replace(/^\/novnc/, '') || '/';
        }
        novncProxy.ws(req, socket, head);
      })
      .catch(() => socket.destroy());
    return;
  }

  socket.destroy();
});

function shutdown(code) {
  try {
    server.close();
  } catch {}
  for (const child of childProcesses) {
    try {
      if (child && !child.killed) child.kill('SIGTERM');
    } catch {}
  }
  process.exit(code);
}

process.on('SIGTERM', () => shutdown(0));
process.on('SIGINT', () => shutdown(0));

server.listen(PUBLIC_PORT, '0.0.0.0', () => {
  console.log(`[playwright-only] listening on 0.0.0.0:${PUBLIC_PORT}`);
});
EOF

RUN mkdir -p /data/playwright /app/uploads \
    && chown -R node:node /app /home/node /data

USER node

EXPOSE 8080

ENTRYPOINT ["node", "/app/server.js"]
