#!/usr/bin/env node
/**
 * qr-login.mjs — QR code login helper for Claude Code plugin
 *
 * Replicates `ldc login` QR flow but generates a PNG image instead of
 * terminal ASCII art. Claude Code uses the Read tool to display the PNG
 * inline in the conversation.
 *
 * Usage: node scripts/qr-login.mjs
 *
 * Output (stdout):
 *   STATUS:<status>        — OK | NEED_QR | EXPIRED | ERROR
 *   QR_PNG:<path>          — path to PNG file (when STATUS:NEED_QR)
 *   MESSAGE:<text>         — human-readable message
 *
 * Token is saved to ~/.cloud-cli/token.json (shared with ldc CLI).
 */

import { createRequire } from 'module';
import { execSync } from 'child_process';
import { existsSync, cpSync, rmSync, mkdtempSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { homedir, tmpdir } from 'os';
import { join } from 'path';

// ── Resolve dependencies ──────────────────────────────────────────

const NVM_ROOT = process.env.NVM_DIR
  ? join(process.env.NVM_DIR, 'versions/node', process.version, 'lib/node_modules')
  : join(homedir(), '.nvm/versions/node', process.version, 'lib/node_modules');

// playwright-core from ledu-cloud-cli
const ldcNodeModules = join(NVM_ROOT, 'ledu-cloud-cli/node_modules');
const requireLdc = createRequire(join(ldcNodeModules, '_'));
const { chromium } = requireLdc('playwright-core');

// qrcode from global install
const requireGlobal = createRequire(join(NVM_ROOT, '_'));
const QRCode = requireGlobal('qrcode');

// ── Constants ─────────────────────────────────────────────────────

const PLATFORM_URL = 'https://cloud.xuepeiyou.com';
const TOKEN_DIR = join(homedir(), '.cloud-cli');
const TOKEN_PATH = join(TOKEN_DIR, 'token.json');
const QR_PNG_PATH = '/tmp/ldc-login-qr.png';
const LOGIN_TIMEOUT = 120000;

const BROWSER_PROFILES = {
  'com.google.chrome': {
    name: 'Google Chrome',
    dir: join(homedir(), 'Library/Application Support/Google/Chrome')
  },
  'com.microsoft.edgemac': {
    name: 'Microsoft Edge',
    dir: join(homedir(), 'Library/Application Support/Microsoft Edge')
  },
  'com.brave.browser': {
    name: 'Brave Browser',
    dir: join(homedir(), 'Library/Application Support/BraveSoftware/Brave-Browser')
  }
};

// ── Output helpers ────────────────────────────────────────────────

function emit(status, message, qrPng) {
  if (qrPng) console.log(`QR_PNG:${qrPng}`);
  console.log(`STATUS:${status}`);
  console.log(`MESSAGE:${message}`);
}

// ── Token management ──────────────────────────────────────────────

function saveToken(token, userInfo) {
  mkdirSync(TOKEN_DIR, { recursive: true });
  const data = { token, created_at: new Date().toISOString() };
  if (userInfo) data.userInfo = userInfo;
  writeFileSync(TOKEN_PATH, JSON.stringify(data, null, 2));
}

function loadToken() {
  try {
    const data = JSON.parse(readFileSync(TOKEN_PATH, 'utf-8'));
    const payload = JSON.parse(Buffer.from(data.token.split('.')[1], 'base64').toString());
    if (Date.now() / 1000 > payload.exp) return null;
    return data.token;
  } catch {
    return null;
  }
}

async function verifyToken(token) {
  try {
    const res = await fetch('https://cloud.xuepeiyou.com/k8s/apiv3/app/detail?app_id=1', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }
    });
    const json = await res.json();
    return !json.msg?.includes('expired');
  } catch {
    return false;
  }
}

// ── Browser profile helpers ───────────────────────────────────────

function getDefaultBrowser() {
  try {
    const bundleId = execSync(
      'defaults read ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | grep -B1 "https" | grep "LSHandlerRoleAll" | head -1 | sed \'s/.*= "\\(.*\\)";/\\1/\'',
      { encoding: 'utf-8' }
    ).trim();
    if (BROWSER_PROFILES[bundleId]) return BROWSER_PROFILES[bundleId];
  } catch {}
  for (const profile of Object.values(BROWSER_PROFILES)) {
    if (existsSync(profile.dir)) return profile;
  }
  return null;
}

function copyProfileToTemp(profileDir) {
  const tmpDir = mkdtempSync(join(tmpdir(), 'cloud-cli-chrome-'));
  const srcDefault = join(profileDir, 'Default');
  const destDefault = join(tmpDir, 'Default');
  const localStorageSrc = join(srcDefault, 'Local Storage');
  if (existsSync(localStorageSrc)) {
    cpSync(localStorageSrc, join(destDefault, 'Local Storage'), { recursive: true });
  }
  const prefSrc = join(srcDefault, 'Preferences');
  if (existsSync(prefSrc)) cpSync(prefSrc, join(destDefault, 'Preferences'));
  const localStateSrc = join(profileDir, 'Local State');
  if (existsSync(localStateSrc)) cpSync(localStateSrc, join(tmpDir, 'Local State'));
  return tmpDir;
}

async function extractTokenFromProfile(profileDir) {
  const tmpDir = copyProfileToTemp(profileDir);
  try {
    const context = await chromium.launchPersistentContext(tmpDir, {
      channel: 'chrome',
      headless: true
    });
    const page = context.pages()[0] || await context.newPage();
    await page.goto(`${PLATFORM_URL}/k8s-fe/appManage/appManageCenter`);
    await page.waitForTimeout(2000);
    const result = await page.evaluate(() => {
      const t = localStorage.getItem('token') || localStorage.getItem('Authorization');
      const ui = localStorage.getItem('userInfo');
      return {
        token: t ? t.replace('Bearer ', '') : null,
        userInfo: ui ? JSON.parse(ui) : null
      };
    });
    await context.close();
    return result;
  } finally {
    try { rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  }
}

function writeBackToProfile(tmpDir, profileDir) {
  const srcLS = join(tmpDir, 'Default', 'Local Storage');
  const destLS = join(profileDir, 'Default', 'Local Storage');
  if (!existsSync(srcLS)) return;
  try {
    cpSync(srcLS, destLS, { recursive: true, force: true });
  } catch {}
}

// ── QR login with PNG output ──────────────────────────────────────

async function loginWithQrPng(profileDir) {
  const tmpDir = profileDir ? copyProfileToTemp(profileDir) : null;
  let context, browserInstance;

  if (tmpDir) {
    context = await chromium.launchPersistentContext(tmpDir, {
      channel: 'chrome',
      headless: true
    });
  } else {
    browserInstance = await chromium.launch({ channel: 'chrome', headless: true });
    context = await browserInstance.newContext();
  }

  const page = context.pages()[0] || await context.newPage();

  let qrResolve;
  const qrPromise = new Promise(resolve => { qrResolve = resolve; });

  page.on('response', async (response) => {
    if (response.url().includes('/apiv3/plat/auth/getqrcode')) {
      try {
        const json = await response.json();
        if (json.code === 0 && json.data?.qrcode) {
          qrResolve(json.data.qrcode);
        }
      } catch {}
    }
  });

  await page.goto(`${PLATFORM_URL}/k8s-fe/appManage/appManageCenter`);
  await page.waitForTimeout(2000);

  const qrUrl = await qrPromise;

  // Generate PNG QR code
  await QRCode.toFile(QR_PNG_PATH, qrUrl, {
    width: 300,
    margin: 2,
    color: { dark: '#000000', light: '#ffffff' }
  });

  // Tell Claude where the PNG is
  emit('NEED_QR', '请扫描二维码完成登录', QR_PNG_PATH);

  // Wait for scan
  try {
    await page.waitForURL('**/appManage/**', { timeout: LOGIN_TIMEOUT });
  } catch {
    emit('ERROR', '登录超时，请重试。');
    if (browserInstance) await browserInstance.close();
    else await context.close();
    if (tmpDir) try { rmSync(tmpDir, { recursive: true, force: true }); } catch {}
    process.exit(1);
  }

  const { token, userInfo } = await page.evaluate(() => {
    const t = localStorage.getItem('token') || localStorage.getItem('Authorization');
    const ui = localStorage.getItem('userInfo');
    return {
      token: t ? t.replace('Bearer ', '') : null,
      userInfo: ui ? JSON.parse(ui) : null
    };
  });

  if (browserInstance) await browserInstance.close();
  else await context.close();

  if (!token) {
    if (tmpDir) try { rmSync(tmpDir, { recursive: true, force: true }); } catch {}
    emit('ERROR', '无法获取 token，请重试。');
    process.exit(1);
  }

  saveToken(token, userInfo);

  // Write back to browser profile
  if (tmpDir && profileDir) {
    writeBackToProfile(tmpDir, profileDir);
    try { rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  }

  emit('OK', '登录成功，token 已保存。');
}

// ── Main ──────────────────────────────────────────────────────────

async function main() {
  // 1. Check existing token
  const existingToken = loadToken();
  if (existingToken) {
    const valid = await verifyToken(existingToken);
    if (valid) {
      emit('OK', '已登录，token 有效。');
      return;
    }
    console.error('token 已过期，需要重新登录。');
  }

  // 2. Try browser profile extraction
  const browser = getDefaultBrowser();
  if (browser && existsSync(browser.dir)) {
    console.error(`检测到系统浏览器: ${browser.name}`);
    try {
      const result = await extractTokenFromProfile(browser.dir);
      if (result?.token) {
        const valid = await verifyToken(result.token);
        if (valid) {
          saveToken(result.token, result.userInfo);
          emit('OK', '已从浏览器获取登录信息，token 已保存。');
          return;
        }
      }
    } catch (e) {
      console.error(`读取浏览器信息失败: ${e.message}`);
    }
    console.error('浏览器中无有效登录信息，需要扫码登录。');
    await loginWithQrPng(browser.dir);
    return;
  }

  // 3. Direct QR login
  await loginWithQrPng(null);
}

main().catch(err => {
  emit('ERROR', `登录失败: ${err.message}`);
  process.exit(1);
});
