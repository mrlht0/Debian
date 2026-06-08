# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/playwright:v1.56.1-noble

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
      libnss3 \
      libatk-bridge2.0-0 \
      libgtk-3-0 \
      libgbm1 \
      libxss1 \
      libasound2t64 \
      dbus \
      udev \
      bash \
      curl \
      wget \
      gnupg \
    && curl -fsSL -o /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/google-chrome.deb \
    && rm -f /tmp/google-chrome.deb \
    && rm -rf /var/lib/apt/lists/* \
    && if ! id -u node >/dev/null 2>&1; then useradd -m -s /bin/bash node; fi \
    && npm install -g --no-audit --no-fund n8n@2.22.4 \
    && npm init -y >/dev/null 2>&1 \
    && npm install --no-package-lock --no-save --no-audit --no-fund \
      http-proxy mongoose mongodb pg playwright playwright-core playwright-extra puppeteer-extra-plugin-stealth
  
RUN cat <<'EOF' > /app/server.js
'use strict';

const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { execSync, spawn } = require('node:child_process');
const path = require('node:path');
const httpProxy = require('http-proxy');
const { Client: PgClient } = require('pg');

const PUBLIC_PORT = Number(process.env.PORT || 8080);
const INTERNAL_N8N_PORT = Number(process.env.N8N_PORT || 5678);

const DISPLAY_NUM = process.env.DISPLAY || ':99';
const NOVNC_PORT = Number(process.env.NOVNC_INTERNAL_PORT || 6080);
const VNC_PORT = Number(process.env.VNC_INTERNAL_PORT || 5900);
const CHROME_BIN = process.env.CHROME_BIN || '';

const AI_STUDIO_APP_URL = process.env.AI_STUDIO_APP_URL || 'https://ai.studio/apps/4c2ff89f-3309-4c2c-9613-3058239f23b3';
const AI_STUDIO_PROFILE_DIR = process.env.AI_STUDIO_PROFILE_DIR || '/data/playwright/ai-studio-profile';
const AI_STUDIO_RUNTIME_PROFILE_DIR = process.env.AI_STUDIO_RUNTIME_PROFILE_DIR || '/tmp/aistudio-profile-runtime';

const RAM_TOKEN = process.env.RAM_TOKEN || 'cliply_ram_secret_token_2026';
const NOVNC_READY_PATH = '/novnc/vnc_lite.html?autoconnect=true&resize=scale&path=websockify';

// MongoDB này chỉ dùng cho RAM/cost/network, không dùng cho n8n login/workflow.
const MONGODB_URI =
  process.env.MONGODB_URI ||
  'mongodb+srv://tylauj04:t482169@cluster0.ygab0.mongodb.net';

const TARGET_DB = process.env.TARGET_DB || 'application-manager';

let mongoose = null;
let CostHistory = null;


// ================= XVFB / noVNC / PLAYWRIGHT HELPERS =================
const childProcesses = [];
let desktopStarted = false;
let aiStudioGuiContext = null;
let aiStudioGuiPage = null;
let aiStudioChromeProcess = null;
let aiStudioLastLaunchUsedCleanProfile = false;
let fallbackXtermProcess = null;
let xvfbProcess = null;
let fluxboxProcess = null;
let x11vncProcess = null;
let websockifyProcess = null;

function spawnManaged(name, command, args, options = {}) {
  const child = spawn(command, args, {
    stdio: options.stdio || ['ignore', 'ignore', 'pipe'],
    env: options.env || process.env,
    detached: false,
  });

  child.on('error', (err) => {
    console.error(`[${name}] failed to start:`, err.message);
  });

  if (child.stderr) {
    child.stderr.on('data', (buf) => {
      const msg = String(buf).trim();
      if (msg) console.log(`[${name}] ${msg}`);
    });
  }

  child.on('exit', (code, signal) => {
    console.log(`[${name}] exited code=${code} signal=${signal}`);
  });

  childProcesses.push(child);
  return child;
}

function isChildAlive(child) {
  return Boolean(child && !child.killed && child.exitCode === null && child.signalCode === null);
}

async function waitMs(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForCondition(check, timeoutMs = 5000, intervalMs = 250) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await check()) return true;
    await waitMs(intervalMs);
  }
  return false;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeFileIfMissing(filePath, content) {
  if (!fs.existsSync(filePath)) {
    fs.writeFileSync(filePath, content, 'utf8');
  }
}

function resetDir(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });
}

function copyDirContents(sourceDir, targetDir) {
  if (!fs.existsSync(sourceDir)) return;
  ensureDir(targetDir);
  fs.cpSync(sourceDir, targetDir, { recursive: true, force: true });
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
  if (isDisplayResponsive()) return false;

  const id = displayId();
  console.log(`[desktop] DISPLAY ${DISPLAY_NUM} is not responsive. Cleaning stale locks/processes...`);

  try {
    execSync(`pkill -f "Xvfb ${DISPLAY_NUM}" || true`, { stdio: 'ignore', shell: '/bin/bash' });
  } catch {}

  try {
    fs.rmSync(`/tmp/.X${id}-lock`, { force: true });
    fs.rmSync(`/tmp/.X11-unix/X${id}`, { force: true });
  } catch {}

  xvfbProcess = null;
  fluxboxProcess = null;
  x11vncProcess = null;

  return true;
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
  fs.mkdirSync('/data/playwright', { recursive: true });
  fs.mkdirSync('/home/node', { recursive: true });
  fs.mkdirSync('/home/node/.fluxbox', { recursive: true });
  fs.mkdirSync(AI_STUDIO_PROFILE_DIR, { recursive: true });
  fs.mkdirSync('/tmp/.X11-unix', { recursive: true });

  writeFileIfMissing(
    '/home/node/.fluxbox/init',
    [
      'session.screen0.toolbar.visible:        false',
      'session.screen0.slit.autoHide:          false',
      'session.screen0.slit.visible:           false',
      'session.screen0.workspaces:             1',
      'session.screen0.focusModel:             ClickFocus',
      'session.screen0.tabFocusModel:          ClickToTabFocus',
      'session.screen0.focusNewWindows:        true',
      'session.screen0.focusSameHead:          false',
      'session.screen0.windowPlacement:        RowSmartPlacement',
      'session.screen0.rowPlacementDirection:  LeftToRight',
      'session.screen0.colPlacementDirection:  TopToBottom',
      'session.screen0.menu.alpha:             255',
      'session.screen0.window.focus.alpha:     255',
      'session.screen0.window.unfocus.alpha:   255',
      'session.screen0.toolbar.alpha:          255',
      'session.screen0.slit.alpha:             255',
      'session.screen0.allowRemoteActions:     false',
      'session.screen0.titlebar.left:          Stick',
      'session.screen0.titlebar.right:         Minimize Maximize Close',
      '',
    ].join('\n')
  );
  writeFileIfMissing(
    '/home/node/.fluxbox/startup',
    '#!/bin/sh\nexec fluxbox\n'
  );

  process.env.DISPLAY = DISPLAY_NUM;

  // Nếu có lock nhưng X server không sống thì dọn sạch. Nếu X server sống thì tuyệt đối không start Xvfb lần 2.
  cleanupStaleDisplay();

  if (!isDisplayResponsive()) {
    if (!isChildAlive(xvfbProcess)) {
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
    }

    // Đợi Xvfb thật sự nhận kết nối, không chỉ đợi timeout cố định.
    for (let i = 0; i < 20; i++) {
      if (isDisplayResponsive()) break;
      await waitMs(300);
    }
  } else {
    console.log(`[desktop] reusing active DISPLAY ${DISPLAY_NUM}`);
  }

  if (!isDisplayResponsive()) {
    throw new Error(`X server ${DISPLAY_NUM} is not ready. Check /tmp/.X${displayId()}-lock and Xvfb logs.`);
  }

  if (!isChildAlive(fluxboxProcess)) {
    fluxboxProcess = spawnManaged('fluxbox', 'fluxbox', [], {
      env: { ...process.env, DISPLAY: DISPLAY_NUM, HOME: '/home/node' },
    });
    await waitMs(700);
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
      '-repeat',
      '-rfbwait',
      '120000',
      '-defer',
      '10',
      '-wait',
      '10',
      '-o',
      '/tmp/x11vnc.log',
    ]);
    for (let i = 0; i < 20; i++) {
      if (await isPortOpen(VNC_PORT)) break;
      await waitMs(300);
    }
  }

  if (!(await isPortOpen(VNC_PORT))) {
    throw new Error(`x11vnc is not listening on 127.0.0.1:${VNC_PORT}. Check /tmp/x11vnc.log.`);
  }

  const novncWebCandidates = [
    '/usr/share/novnc',
    '/usr/share/noVNC',
    '/usr/share/webapps/novnc',
  ];
  const novncWeb = novncWebCandidates.find((x) => fs.existsSync(x)) || '/usr/share/novnc';

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

  if (!(await isPortOpen(NOVNC_PORT))) {
    throw new Error(`websockify is not listening on 127.0.0.1:${NOVNC_PORT}.`);
  }

  desktopStarted = true;
  console.log(`[desktop] services ready: DISPLAY=${DISPLAY_NUM}, VNC=${VNC_PORT}, noVNC=${NOVNC_PORT}`);
}

function ensureFallbackTerminal() {
  if (isChildAlive(fallbackXtermProcess)) return;

  fallbackXtermProcess = spawnManaged('desktop-xterm', 'xterm', [
    '-geometry',
    '120x30+40+40',
    '-fa',
    'Monospace',
    '-fs',
    '11',
    '-title',
    'AI Studio Desktop',
    '-e',
    'bash',
    '-lc',
    'echo "Desktop is ready."; echo "If Chrome crashes, inspect /tmp/aistudio-chrome.log"; tail -f /tmp/aistudio-chrome.log',
  ], {
    env: { ...process.env, DISPLAY: DISPLAY_NUM, HOME: '/home/node' },
  });
}

async function closeAiStudioContext() {
  if (aiStudioGuiPage) {
    try {
      await aiStudioGuiPage.close();
    } catch {}
    aiStudioGuiPage = null;
  }

  if (aiStudioGuiContext) {
    try {
      await aiStudioGuiContext.close();
    } catch {}
    aiStudioGuiContext = null;
  }
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

function getChromiumExecutablePath() {
  const candidates = [
    CHROME_BIN,
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    findPlaywrightBundledChromium(),
  ];

  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) return candidate;
  }

  return '';
}

async function launchChromium(options = {}) {
  const { chromium } = require('playwright-extra');
  const StealthPlugin = require('puppeteer-extra-plugin-stealth');
  const executablePath = getChromiumExecutablePath();
  chromium.use(StealthPlugin());

  const isHeadless = options.headless ?? false;

  const args = [
    '--no-sandbox',
    '--disable-dev-shm-usage',
    '--disable-gpu',
    '--disable-software-rasterizer',
    '--disable-background-networking',
    '--disable-background-timer-throttling',
    '--disable-backgrounding-occluded-windows',
    '--disable-breakpad',
    '--disable-component-extensions-with-background-pages',
    '--disable-extensions',
    '--disable-features=Translate,BackForwardCache,AcceptCHFrame,MediaRouter,OptimizationHints',
    '--disable-ipc-flooding-protection',
    '--disable-renderer-backgrounding',
    '--disable-sync',
    '--metrics-recording-only',
    '--mute-audio',
    '--no-first-run',
    '--no-default-browser-check',
    '--password-store=basic',
    '--use-mock-keychain',
    '--window-size=1365,900',
  ];

  const launchOptions = {
    headless: isHeadless,
    ...(executablePath ? { executablePath } : {}),
    args,
  };

  if (!isHeadless) {
    launchOptions.env = {
      ...process.env,
      DISPLAY: DISPLAY_NUM,
    };
  }

  return chromium.launch(launchOptions);
}


function hasProfileFiles() {
  try {
    return fs.existsSync(path.join(AI_STUDIO_PROFILE_DIR, 'Default')) ||
      fs.existsSync(path.join(AI_STUDIO_PROFILE_DIR, 'Local State')) ||
      fs.readdirSync(AI_STUDIO_PROFILE_DIR).length > 0;
  } catch {
    return false;
  }
}

function getChromeExecutablePath() {
  const candidates = [
    process.env.GOOGLE_CHROME_BIN,
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/opt/google/chrome/chrome',
    getChromiumExecutablePath(),
  ];

  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) return candidate;
  }

  return '';
}

async function waitForProfileSettled(ms = 2500) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

function cleanupChromeSingletonFiles(userDataDir) {
  for (const name of ['SingletonCookie', 'SingletonLock', 'SingletonSocket']) {
    try {
      fs.rmSync(path.join(userDataDir, name), { force: true, recursive: true });
    } catch {}
  }
}

async function startAiStudioGui() {
  await ensureDesktopServices();
  const chromePath = getChromeExecutablePath();

  if (aiStudioGuiContext) {
    return {
      ok: true,
      reused: true,
      url: AI_STUDIO_APP_URL,
      noVncPath: NOVNC_READY_PATH,
      profileDir: AI_STUDIO_PROFILE_DIR,
      browser: chromePath,
      restore: { ok: true, skipped: 'chrome_already_running' },
    };
  }

  if (!chromePath) {
    throw new Error('Không tìm thấy Google Chrome/Chromium executable trong container.');
  }

  fs.mkdirSync(AI_STUDIO_PROFILE_DIR, { recursive: true });
  const restoreResult = { ok: false, skipped: 'disabled' };
  let runtimeProfileSource = AI_STUDIO_PROFILE_DIR;

  const useCleanProfile = String(process.env.AI_STUDIO_FORCE_CLEAN_PROFILE || 'false').toLowerCase() === 'true';
  if (useCleanProfile) {
    resetDir(AI_STUDIO_RUNTIME_PROFILE_DIR);
    runtimeProfileSource = AI_STUDIO_RUNTIME_PROFILE_DIR;
  }
  cleanupChromeSingletonFiles(runtimeProfileSource);

  const { chromium } = require('playwright-extra');
  const StealthPlugin = require('puppeteer-extra-plugin-stealth');
  chromium.use(StealthPlugin());
  const contextArgs = [
    '--no-sandbox',
    '--disable-dev-shm-usage',
    '--disable-gpu',
    '--disable-software-rasterizer',
    '--disable-background-networking',
    '--disable-background-timer-throttling',
    '--disable-backgrounding-occluded-windows',
    '--disable-renderer-backgrounding',
    '--disable-component-update',
    '--disable-sync',
    '--disable-breakpad',
    '--disable-crash-reporter',
    '--disable-features=Translate,BackForwardCache,AcceptCHFrame,MediaRouter,OptimizationHints,PushMessaging,VizDisplayCompositor,RendererCodeIntegrity,site-per-process,IsolateOrigins',
    '--password-store=basic',
    '--use-mock-keychain',
    '--window-size=1365,900',
    '--start-maximized',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-session-crashed-bubble',
    '--disable-infobars',
    '--disable-popup-blocking',
    '--disable-blink-features=AutomationControlled',
    '--disable-accelerated-2d-canvas',
    '--disable-gpu-compositing',
    '--disable-renderer-accessibility',
    '--disable-features=InfiniteSessionRestore',
    '--lang=en-US',
  ];

  async function launchPersistent(userDataDir) {
    return await chromium.launchPersistentContext(userDataDir, {
      headless: false,
      executablePath: chromePath,
      args: contextArgs,
      viewport: { width: 1365, height: 900 },
      env: {
        ...process.env,
        DISPLAY: DISPLAY_NUM,
        HOME: '/home/node',
      },
    });
  }

  try {
    aiStudioGuiContext = await launchPersistent(runtimeProfileSource);
  } catch (error) {
    console.error('[aistudio-playwright] first launch failed, retrying with clean runtime profile:', error.message);
    resetDir(AI_STUDIO_RUNTIME_PROFILE_DIR);
    aiStudioLastLaunchUsedCleanProfile = true;
    cleanupChromeSingletonFiles(AI_STUDIO_RUNTIME_PROFILE_DIR);
    try {
      aiStudioGuiContext = await launchPersistent(AI_STUDIO_RUNTIME_PROFILE_DIR);
    } catch (retryError) {
      ensureFallbackTerminal();
      throw new Error(`Playwright persistent launch failed: ${retryError.message}`);
    }
  }

  aiStudioGuiContext.on('close', async () => {
    aiStudioGuiContext = null;
    aiStudioGuiPage = null;
  });

  const existingPages = aiStudioGuiContext.pages();
  aiStudioGuiPage = existingPages[0] || await aiStudioGuiContext.newPage();

  try {
    await aiStudioGuiPage.goto(AI_STUDIO_APP_URL, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });
  } catch (navError) {
    console.error('[aistudio-playwright] goto failed:', navError.message);
  }

  await waitForProfileSettled(1500);

  return {
    ok: true,
    reused: false,
    url: AI_STUDIO_APP_URL,
    noVncPath: NOVNC_READY_PATH,
    profileDir: AI_STUDIO_PROFILE_DIR,
    browser: chromePath,
    restore: restoreResult,
  };
}

function cleanTitle(t) {
  return String(t || '').replace(/\s+/g, ' ').replace(/[\\/:*?"<>|]/g, '').trim();
}

function inferEpisode(title) {
  const s = String(title || '');
  const m =
    s.match(/第\s*([0-9一二三四五六七八九十百千万]+)\s*[集话話回]/) ||
    s.match(/EP\.?\s*(\d+)/i) ||
    s.match(/E(?:pisode)?\s*(\d+)/i);
  return m ? String(m[1]) : '';
}

async function scrapeBilibiliToday(payload = {}) {
  const bilibiliUrl =
    payload.bilibiliUrl ||
    process.env.BILIBILI_URL ||
    'https://www.bilibili.com/c/douga/?spm_id_from=333.1007.0.0';

  const maxVideos = Number(
    payload.maxVideos ||
    process.env.MAX_BILIBILI_VIDEOS ||
    20
  );

  const runDate =
    payload.runDate ||
    new Date().toISOString().slice(0, 10);

  const scraperHeadless =
    String(
      payload.headless ??
      process.env.SCRAPER_HEADLESS ??
      'true'
    ).toLowerCase() !== 'false';

  const browser = await launchChromium({
    headless: scraperHeadless,
    scraper: true,
  });
  const page = await browser.newPage({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125 Safari/537.36',
    viewport: { width: 1365, height: 900 },
  });

  try {
    await page.goto(bilibiliUrl, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForTimeout(6000);
    try {
      await page.mouse.wheel(0, 2400);
      await page.waitForTimeout(2500);
    } catch {}

    const rows = await page.evaluate(() => {
      function absUrl(href) {
        try { return new URL(href, location.origin).href; } catch { return ''; }
      }

      function cleanText(value) {
        return String(value || '')
          .replace(/\s+/g, ' ')
          .replace(/[\u200b\u200c\u200d]/g, '')
          .trim();
      }

      function textOf(el) {
        if (!el) return '';
        return cleanText(
          el.getAttribute?.('title') ||
          el.getAttribute?.('aria-label') ||
          el.innerText ||
          el.textContent ||
          ''
        );
      }

      function validTitle(title) {
        const s = cleanText(title);
        if (!s) return '';
        // Loại các chuỗi thống kê/thời lượng kiểu: 36.3万 142 00:11
        if (/^[\d.]+\s*[万萬]?\s+\d+\s+\d{1,2}:?\d{2}$/.test(s)) return '';
        if (/^[\d.]+\s*[万萬]\s*\d*\s*\d*:?[\d]*$/.test(s)) return '';
        if (/^\d{1,2}:\d{2}$/.test(s)) return '';
        if (s.length < 4) return '';
        return s;
      }

      function pickTitle(a, card) {
        const candidates = [
          a.getAttribute?.('title'),
          a.getAttribute?.('aria-label'),
          a.querySelector?.('.bili-video-card__info--tit')?.getAttribute?.('title'),
          a.querySelector?.('.bili-video-card__info--tit')?.textContent,
          a.querySelector?.('.video-name')?.textContent,
          a.querySelector?.('.title')?.textContent,
          card?.querySelector?.('.bili-video-card__info--tit')?.getAttribute?.('title'),
          card?.querySelector?.('.bili-video-card__info--tit')?.textContent,
          card?.querySelector?.('.video-name')?.textContent,
          card?.querySelector?.('.title')?.textContent,
          card?.querySelector?.('img[alt]')?.getAttribute?.('alt'),
          card?.querySelector?.('[title]')?.getAttribute?.('title'),
        ];

        for (const c of candidates) {
          const title = validTitle(c);
          if (title) return title;
        }

        const lines = cleanText(card?.innerText || card?.textContent || '')
          .split(/\n+/)
          .map(validTitle)
          .filter(Boolean);

        return lines.find(line => !/播放|弹幕|评论|收藏|分享/.test(line)) || '';
      }

      const anchors = [...document.querySelectorAll('a[href*="/video/BV"], a[href*="bilibili.com/video/BV"]')];

      return anchors
        .map((a) => {
          const rawUrl = absUrl(a.getAttribute('href') || a.href || '');
          const match = rawUrl.match(/BV[a-zA-Z0-9]+/);
          if (!match) return null;

          const bvid = match[0];
          const source_url = `https://www.bilibili.com/video/${bvid}`;
          const card =
            a.closest('.bili-video-card, .bili-video-card__wrap, .video-card, .feed-card, .card-box, li') ||
            a.parentElement;
          const original_title = pickTitle(a, card);
          if (!original_title) return null;

          const img = card?.querySelector?.('img') || a.querySelector?.('img');
          const thumbnail_url = img?.currentSrc || img?.src || img?.getAttribute?.('data-src') || '';
          const card_text = cleanText(card?.innerText || card?.textContent || '');

          return {
            bvid,
            source_url,
            original_title,
            card_text,
            thumbnail_url,
          };
        })
        .filter(Boolean);
    });

    const seen = new Set();
    return rows
      .filter((x) => x.bvid && x.original_title && !seen.has(x.bvid) && seen.add(x.bvid))
      .slice(0, maxVideos)
      .map((x) => {
        const original = cleanTitle(x.original_title);
        const episode = inferEpisode(original);
        return {
          run_date: runDate,
          unique_key: x.bvid,
          bvid: x.bvid,
          episode,
          original_title: original,
          processed_title_vi: '',
          processed_title_en: '',
          processed_title_ja: '',
          source_url: x.source_url,
          thumbnail_url: x.thumbnail_url,
          card_text: x.card_text,
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

async function readJsonBody(req) {
  return await new Promise((resolve) => {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      try { resolve(body ? JSON.parse(body) : {}); } catch { resolve({}); }
    });
    req.on('error', () => resolve({}));
  });
}

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

function getTrackedPidList() {
  const pids = new Set([process.pid]);

  if (n8nChild?.pid) pids.add(n8nChild.pid);

  for (const child of childProcesses) {
    if (child?.pid) pids.add(child.pid);
  }

  return [...pids].filter((pid) => Number.isFinite(pid));
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
  if (process.platform !== 'linux') {
    return {
      trackedProcesses: [],
      totalTrackedRssBytes: 0,
    };
  }

  const pids = getTrackedPidList();
  if (!pids.length) {
    return {
      trackedProcesses: [],
      totalTrackedRssBytes: 0,
    };
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

function getTopProcessesByRss(limit = 10) {
  if (process.platform !== 'linux') return [];

  const output = safeExec(`ps -eo pid=,rss=,comm=,args= --sort=-rss | head -n ${Math.max(limit, 1)}`);
  return parsePsTable(output).map((row) => ({
    pid: row.pid,
    rssMb: Number((row.rssKb / 1024).toFixed(2)),
    command: row.command,
  }));
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

function getCurrentRxBytes() {
  if (process.platform !== 'linux') return 0;

  let total = 0;

  try {
    const base = '/sys/class/net';
    const interfaces = fs.readdirSync(base);

    for (const iface of interfaces) {
      if (iface === 'lo') continue;

      const rxPath = `${base}/${iface}/statistics/rx_bytes`;

      if (fs.existsSync(rxPath)) {
        const value = parseInt(fs.readFileSync(rxPath, 'utf8').trim(), 10);
        if (Number.isFinite(value)) total += value;
      }
    }
  } catch {}

  return total;
}

function getCgroupStats() {
  if (process.platform !== 'linux') {
    return {
      memoryCurrentBytes: null,
      memoryMaxBytes: null,
      cpuUsageUsec: null,
    };
  }

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

  return {
    memoryCurrentBytes,
    memoryMaxBytes,
    cpuUsageUsec,
  };
}

async function buildMonitorStats() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const cpu = await measureCpuPercent();
  const mem = process.memoryUsage();
  const projectName = getProjectName();
  const tracked = getTrackedProcessStats();
  const cgroup = getCgroupStats();
  const txBytes = getCurrentTxBytes();
  const rxBytes = getCurrentRxBytes();

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
      rssBytes: mem.rss,
    },
    tracked: {
      wrapperRssMb: Number(toMB(mem.rss)),
      wrapperRssBytes: mem.rss,
      childProcessesRssMb: Number(toMB(Math.max(0, tracked.totalTrackedRssBytes - mem.rss))),
      childProcessesRssBytes: Math.max(0, tracked.totalTrackedRssBytes - mem.rss),
      totalTrackedRssMb: Number(toMB(tracked.totalTrackedRssBytes)),
      totalTrackedRssBytes: tracked.totalTrackedRssBytes,
      processes: tracked.trackedProcesses,
    },
    container: {
      memoryCurrentMb:
        cgroup.memoryCurrentBytes != null ? Number(toMB(cgroup.memoryCurrentBytes)) : null,
      memoryCurrentBytes: cgroup.memoryCurrentBytes,
      memoryLimitMb:
        cgroup.memoryMaxBytes != null ? Number(toMB(cgroup.memoryMaxBytes)) : null,
      memoryLimitBytes: cgroup.memoryMaxBytes,
      cpuUsageUsec: cgroup.cpuUsageUsec,
      networkTxBytes: txBytes,
      networkRxBytes: rxBytes,
      networkTxGb: Number((txBytes / 1024 / 1024 / 1024).toFixed(4)),
      networkRxGb: Number((rxBytes / 1024 / 1024 / 1024).toFixed(4)),
    },
    timestamp: new Date().toISOString(),
  };

  if (process.platform === 'linux') {
    const freeOutput = safeExec('free -h');

    if (freeOutput) stats.freeCommandOutput = freeOutput;

    const ps = safeExec('ps aux --sort=-%mem | head -n 6');

    if (ps) stats.topProcesses = ps.split('\n');

    const topByRss = getTopProcessesByRss(10);
    if (topByRss.length) stats.topProcessesByRss = topByRss;

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
    rssBytes: cgroup.memoryCurrentBytes || tracked.totalTrackedRssBytes || mem.rss,
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
    tracked: stats.tracked,
    container: stats.container,
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

const novncProxy = httpProxy.createProxyServer({
  target: `http://127.0.0.1:${NOVNC_PORT}`,
  ws: true,
  xfwd: true,
  changeOrigin: false,
});

novncProxy.on('error', (err, req, res) => {
  console.error('[novnc-proxy] error:', err.message);
  if (res && !res.headersSent) {
    sendText(res, 502, `noVNC proxy error: ${err.message}`);
  }
});

novncProxy.on('close', () => {
  console.log('[novnc-proxy] websocket closed');
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

  if (url.pathname === '/ram') {
    await handleRamRequest(req, res);
    return;
  }

  if (url.pathname === '/api/desktop/start') {
    try {
      await ensureDesktopServices();
      sendJson(res, 200, {
        ok: true,
        noVncPath: NOVNC_READY_PATH,
        display: DISPLAY_NUM,
      });
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  if (url.pathname === '/api/aistudio/profile/backup') {
    sendJson(res, 410, { ok: false, error: 'Profile backup feature removed' });
    return;
  }

  if (url.pathname === '/api/aistudio/profile/restore') {
    sendJson(res, 410, { ok: false, error: 'Profile restore feature removed' });
    return;
  }

  if (url.pathname === '/api/aistudio/profile/status') {
    try {
      sendJson(res, 200, {
        ok: true,
        profileDir: AI_STUDIO_PROFILE_DIR,
        profileExists: hasProfileFiles(),
        backupEnabled: false,
        chromeRunning: Boolean(aiStudioChromeProcess && !aiStudioChromeProcess.killed),
      });
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  if (url.pathname === '/api/aistudio/gui/start') {
    try {
      const result = await startAiStudioGui();
      sendJson(res, 200, result);
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  if (url.pathname === '/api/scrape-bilibili') {
    try {
      const payload = req.method === 'POST' ? await readJsonBody(req) : Object.fromEntries(url.searchParams.entries());
      const rows = await scrapeBilibiliToday(payload);
      sendJson(res, 200, { ok: true, count: rows.length, rows });
    } catch (err) {
      sendJson(res, 500, { ok: false, error: err.message });
    }
    return;
  }

  // noVNC entrypoint: start desktop + open AI Studio automatically, then redirect to noVNC UI.
  if (url.pathname === '/novnc' || url.pathname === '/novnc/') {
    try {
      await startAiStudioGui();
    } catch (err) {
      console.error('[novnc] failed to auto-open AI Studio:', err.message);
      sendJson(res, 500, { ok: false, error: err.message, logHint: '/tmp/aistudio-chrome.log' });
      return;
    }

    res.writeHead(302, { Location: NOVNC_READY_PATH });
    res.end();
    return;
  }

  // Silence harmless noVNC version lookup 404.
  if (url.pathname === '/novnc/package.json') {
    sendJson(res, 200, { name: 'novnc', version: 'container' });
    return;
  }

  if (url.pathname === '/websockify' || url.pathname.startsWith('/novnc/')) {
    // If the user opens /novnc/vnc.html directly, also open AI Studio automatically.
    if (url.pathname === '/novnc/vnc.html' || url.pathname.endsWith('/vnc.html')) {
      try {
        await startAiStudioGui();
      } catch (err) {
        console.error('[novnc] failed to auto-open AI Studio:', err.message);
        await ensureDesktopServices();
        ensureFallbackTerminal();
      }
    } else {
      await ensureDesktopServices();
    }

    if (url.pathname.startsWith('/novnc/')) {
      req.url = req.url.replace(/^\/novnc/, '') || '/';
    }

    novncProxy.web(req, res);
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

  for (const child of childProcesses) {
    try {
      if (child && !child.killed) child.kill('SIGTERM');
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

RUN mkdir -p /data/playwright /app/temp_uploads \
    && chown -R node:node /app /home/node /data

USER node

EXPOSE 8080

ENTRYPOINT ["node", "/app/server.js"]
