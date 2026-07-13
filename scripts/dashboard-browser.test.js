#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { pathToFileURL } = require('url');

function loadPlaywright() {
  const candidates = [
    process.env.MISSION_CONTROL_PLAYWRIGHT,
    path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'),
    'playwright',
  ].filter(Boolean);
  for (const candidate of candidates) {
    try { return require(candidate); } catch (_) {}
  }
  throw new Error('Playwright is required; set MISSION_CONTROL_PLAYWRIGHT to its module path');
}

const ROOT = path.resolve(__dirname, '..');
const DASH = path.join(ROOT, 'scripts', 'dashboard');
const FIXTURES = path.join(ROOT, 'dashboard', 'fixtures');
const CHROME = process.env.MISSION_CONTROL_CHROME ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ARTIFACTS = process.env.MISSION_CONTROL_BROWSER_ARTIFACT_DIR || '';
let passed = 0;

function assert(ok, message) {
  if (!ok) throw new Error(message);
  passed++;
}

function installedState(tmp) {
  const home = path.join(tmp, 'home');
  const state = path.join(tmp, 'installed');
  fs.mkdirSync(home, { recursive: true });
  execFileSync('/bin/bash', [DASH, 'install'], {
    cwd: ROOT,
    env: { ...process.env, HOME: home, MISSION_CONTROL_HOME: state,
      DASHBOARD_INSTALL_NO_LAUNCHD: '1', DASHBOARD_NO_OPEN: '1' },
    stdio: 'pipe',
  });
  // Exercise the candidate worktree before it has a commit. The install suite
  // separately proves that a committed install sources these exact assets from
  // its immutable HEAD and rejects drift.
  fs.copyFileSync(path.join(ROOT, 'dashboard', 'index.html'), path.join(state, 'index.html'));
  fs.mkdirSync(path.join(state, 'vendor'), { recursive: true });
  fs.copyFileSync(path.join(ROOT, 'dashboard', 'vendor', 'cytoscape.min.js'),
    path.join(state, 'vendor', 'cytoscape.min.js'));
  fs.mkdirSync(path.join(state, 'data'), { recursive: true });
  for (const name of ['usage', 'git', 'chats', 'automation', 'decisions', 'brief']) {
    const obj = JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'));
    fs.writeFileSync(path.join(state, 'data', `${name}.json`), JSON.stringify(obj) + '\n');
    fs.writeFileSync(path.join(state, 'data', `${name}.js`),
      `window.MC=window.MC||{feeds:{},feedErrors:{}};window.MC.feeds[${JSON.stringify(name)}]=${JSON.stringify(obj)};\n`);
    fs.writeFileSync(path.join(state, 'data', `${name}.error.js`),
      `window.MC=window.MC||{feeds:{},feedErrors:{}};window.MC.feedErrors[${JSON.stringify(name)}]=null;\n`);
  }
  return state;
}

function demoState() {
  const out = execFileSync('/bin/bash', [DASH, 'demo'], {
    cwd: ROOT, env: { ...process.env, DASHBOARD_NO_OPEN: '1' }, encoding: 'utf8',
  });
  const match = out.match(/^demo state: (.+)$/m);
  if (!match) throw new Error(`could not locate demo state in: ${out}`);
  return match[1].trim();
}

function luminance(rgb) {
  let values;
  const hex = rgb.trim().match(/^#([0-9a-f]{6})$/i);
  if (hex) values = [0, 2, 4].map(i => parseInt(hex[1].slice(i, i + 2), 16));
  else {
    const m = rgb.match(/[\d.]+/g);
    if (!m || m.length < 3) return null;
    values = m.slice(0, 3).map(Number);
  }
  const c = values.map(x => x / 255).map(x => x <= .04045 ? x / 12.92 : ((x + .055) / 1.055) ** 2.4);
  return .2126 * c[0] + .7152 * c[1] + .0722 * c[2];
}
function contrast(a, b) {
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + .05) / (Math.min(x, y) + .05);
}

(async () => {
  const { chromium } = loadPlaywright();
  assert(fs.existsSync(CHROME), `Chrome executable missing: ${CHROME}`);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mc-browser-'));
  const states = { installed: installedState(tmp), demo: demoState() };
  if (ARTIFACTS) fs.mkdirSync(ARTIFACTS, { recursive: true });
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  try {
    for (const [mode, root] of Object.entries(states)) {
      for (const mobile of [false, true]) {
        const page = await browser.newPage({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1000 } });
        const failures = [];
        page.on('pageerror', e => failures.push(`pageerror:${e.message}`));
        page.on('console', m => { if (m.type() === 'error') failures.push(`console:${m.text()}`); });
        page.on('requestfailed', r => failures.push(`request:${r.url()}:${r.failure() && r.failure().errorText}`));
        await page.addInitScript(() => {
          Object.defineProperty(navigator, 'clipboard', { configurable: true,
            value: { writeText: () => Promise.reject(new Error('audit rejection')) } });
        });
        for (const tab of ['home', 'brief', 'map', 'chats', 'git', 'usage', 'automation']) {
          await page.goto(`${pathToFileURL(path.join(root, 'index.html')).href}#${tab}`, { waitUntil: 'load' });
          await page.waitForTimeout(tab === 'map' ? 300 : 50);
          const metrics = await page.evaluate(() => ({
            html: document.documentElement.scrollWidth,
            body: document.body.scrollWidth,
            viewport: innerWidth,
            main: document.getElementById('mc-main').innerText.length,
            active: (() => { const a=document.querySelector('#mc-nav .mc-tab-active'); if(!a) return null; const r=a.getBoundingClientRect(); return { left:r.left, right:r.right }; })(),
            canvases: document.querySelectorAll('#mc-graph canvas').length,
          }));
          assert(metrics.main > 20, `${mode}/${mobile?'mobile':'desktop'}/${tab}: blank main`);
          assert(metrics.html === metrics.viewport && metrics.body === metrics.viewport,
            `${mode}/mobile/${tab}: document overflow ${metrics.html}/${metrics.body} > ${metrics.viewport}`);
          assert(metrics.active && metrics.active.left >= 0 && metrics.active.right <= metrics.viewport,
            `${mode}/${tab}: active navigation tab is outside the viewport`);
          if (tab === 'map') assert(metrics.canvases > 0, `${mode}/${tab}: Cytoscape canvas missing`);
          if (ARTIFACTS && ((mobile && ['home','git'].includes(tab)) || (!mobile && ['home','map'].includes(tab)))) {
            await page.screenshot({ path: path.join(ARTIFACTS, `${mode}-${mobile?'mobile':'desktop'}-${tab}.png`), fullPage: true });
          }
        }
        await page.goto(`${pathToFileURL(path.join(root, 'index.html')).href}#home`, { waitUntil: 'load' });
        await Promise.all([
          page.waitForNavigation({ waitUntil: 'load' }),
          page.evaluate(() => { sessionStorage.setItem('mc-home-expanded', '1'); location.reload(); }),
        ]);
        await page.evaluate(() => {
          const rejected = { writeText: () => Promise.reject(new Error('audit rejection')) };
          Object.defineProperty(Navigator.prototype, 'clipboard', { configurable: true, get: () => rejected });
          Object.defineProperty(navigator, 'clipboard', { configurable: true, value: rejected });
          window.MC_CLIPBOARD_WRITE = () => Promise.reject(new Error('audit rejection'));
        });
        const clipboardRejects = await page.evaluate(async () => {
          try { await navigator.clipboard.writeText('probe'); return false; }
          catch (_) { return true; }
        });
        assert(clipboardRejects, `${mode}: clipboard rejection seam did not install`);
        const copy = page.locator('.mc-copy').first();
        await copy.click();
        await page.waitForTimeout(100);
        const copyText = await copy.innerText();
        assert(/failed/i.test(copyText), `${mode}: rejected clipboard reported success (${copyText})`);
        const copyBox = await copy.boundingBox();
        const target = mobile ? 44 : 32;
        assert(copyBox && copyBox.width + 0.01 >= target && copyBox.height + 0.01 >= target,
          `${mode}/${mobile?'mobile':'desktop'}: copy target too small (${copyBox && copyBox.width}x${copyBox && copyBox.height})`);
        const strip = await page.locator('.mc-strip-seg').evaluateAll(els => els.map(e => ({ tag:e.tagName, tab:e.tabIndex })));
        assert(strip.length > 0 && strip.every(x => x.tag === 'BUTTON' && x.tab >= 0), `${mode}: status strip is not keyboard operable`);
        for (const theme of ['light', 'dark']) {
          await page.evaluate(t => document.documentElement.setAttribute('data-theme', t), theme);
          const tokens = await page.evaluate(() => {
            const s=getComputedStyle(document.documentElement);
            return { bg:s.getPropertyValue('--mc-bg'), s1:s.getPropertyValue('--mc-surface-1'), s2:s.getPropertyValue('--mc-surface-2'),
              colors:['--mc-fg-muted','--mc-fg-dim','--mc-green','--mc-amber','--mc-red','--mc-blue'].map(k=>[k,s.getPropertyValue(k)]) };
          });
          for (const [name, color] of tokens.colors) for (const bg of [tokens.bg,tokens.s1,tokens.s2])
            assert(contrast(color, bg) >= 4.5, `${theme} ${name} contrast ${contrast(color,bg).toFixed(2)} < 4.5`);
        }
        assert(failures.length === 0, `${mode}: browser failures: ${failures.join(' | ')}`);
        await page.close();
      }
    }
  } finally {
    await browser.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  console.log(`dashboard-browser: ${passed} assertions passed`);
})().catch(err => { console.error(`FAIL: ${err.stack || err}`); process.exit(1); });
