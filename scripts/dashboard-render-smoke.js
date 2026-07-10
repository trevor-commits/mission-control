#!/usr/bin/env node
// Headless render smoke test for dashboard/index.html (ER-087 FIX 1).
// The shell suite only greps the page for text — it NEVER runs the renderers, so a
// throwing or blanked renderer shipped green (proven by mutation). This drives the
// page's real render dispatch under a minimal DOM shim, once per tab, over the
// committed fixtures, and asserts each renderer executes AND emits the fixture's
// actual content. A renderer that throws or produces an empty panel fails here.
//
// Usage: node scripts/dashboard-render-smoke.js [repo-root]   (exit 0 = all tabs render)
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const REPO = process.argv[2] || path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(REPO, 'dashboard', 'index.html'), 'utf8');

// extract the single inline <script> IIFE (the renderers). The 4 data/*.js loaders
// are separate <script src> tags we replace with fixtures below.
const m = html.match(/<script>\s*\n([\s\S]*?)<\/script>/);
if (!m) { console.error('FAIL: could not find inline <script> in index.html'); process.exit(1); }
const scriptBody = m[1];

// --- minimal DOM shim -------------------------------------------------------
function makeEl(tag) {
  const el = {
    tag: tag, children: [], _text: '', className: '', id: '', title: '',
    style: {}, attrs: {}, value: '',
    appendChild(c) { if (c != null) this.children.push(c); return c; },
    append() { for (const a of arguments) this.appendChild(a); },
    setAttribute(k, v) { this.attrs[k] = v; },
    getAttribute(k) { return this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    addEventListener() {}, removeEventListener() {},
    querySelector() { return null; }, querySelectorAll() { return []; },
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    remove() {}, focus() {}, click() {}, insertBefore(c) { this.appendChild(c); return c; },
  };
  Object.defineProperty(el, 'textContent', {
    get() { return this._text + this.children.map(c => (c && c.textContent) || '').join(''); },
    set(v) { this._text = String(v == null ? '' : v); this.children = []; },
  });
  Object.defineProperty(el, 'innerText', {
    get() { return this.textContent; }, set(v) { this.textContent = v; },
  });
  Object.defineProperty(el, 'firstChild', { get() { return this.children[0] || null; } });
  return el;
}
function makeTextNode(s) { return { nodeType: 3, textContent: String(s == null ? '' : s) }; }

let byId = {};
function resetDom() { byId = { 'mc-main': makeEl('div'), 'mc-nav': makeEl('div'), 'mc-strip': makeEl('div') }; }

const documentShim = {
  createElement: makeEl,
  createTextNode: makeTextNode,
  getElementById(id) { if (!byId[id]) byId[id] = makeEl('div'); return byId[id]; },
  addEventListener() {}, removeEventListener() {},
  hidden: false, body: makeEl('body'),
};
const locationShim = { hash: '', reload() {}, href: 'file:///mc' };
const ACTIVATION_EPOCH = Date.UTC(2099, 11, 31, 23, 59, 0) / 1000;
const ACTIVATION_STALE_LABEL = new Date(ACTIVATION_EPOCH * 1000).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' });
const TOKEN_PREFIX_ONLY = 'sk-ant-oat01-';
const TOKEN_SECRET_SUFFIX = 'uniqueSyntheticBody987654321';

// --- fixtures as window.MC.feeds -------------------------------------------
const FIX = path.join(REPO, 'dashboard', 'fixtures');
const feeds = {};
for (const name of ['usage', 'git', 'chats', 'automation', 'decisions', 'brief']) {
  const p = path.join(FIX, name + '.json');
  if (!fs.existsSync(p)) { console.error('FAIL: missing fixture ' + p); process.exit(1); }
  feeds[name] = JSON.parse(fs.readFileSync(p, 'utf8'));
}
if (feeds.chats && feeds.chats.data && feeds.chats.data.counts) {
  feeds.chats.data.counts.ingest_skipped = true;
}
if (feeds.automation && feeds.automation.data && Array.isArray(feeds.automation.data.jobs)) {
  feeds.automation.data.jobs.forEach(j => {
    if (j.label === 'Usage Snapshot') j.state = 'yellow';
    else if (j.label === 'Morning Brief') {
      j.state = 'awaiting-activation';
      j.loaded = false;
      j.run_cmd = null;
      // A stale precomputed timestamp must never override activation state.
      j.next_run_epoch = ACTIVATION_EPOCH;
      // Exercise display-time substring redaction for both documentation-only
      // prefixes and full tokens; neither prefix nor suffix may survive.
      j.err_log_tail = 'docs ' + TOKEN_PREFIX_ONLY + ' full ' + TOKEN_PREFIX_ONLY + TOKEN_SECRET_SUFFIX;
    }
    else if (j.state === 'red' || j.state === 'degraded') j.state = 'green';
  });
}

// expected content markers pulled from the ACTUAL fixtures (robust to fixture edits)
function firstStr(obj, keys) {
  const d = (obj && obj.data) || {};
  for (const k of keys) {
    const arr = d[k];
    // order mirrors what the renderers actually display: automation shows jb.label
    // (human name in this tool's schema), chats title, git repo, usage provider/name
    if (Array.isArray(arr)) for (const it of arr) for (const kk of ['label', 'title', 'repo', 'provider', 'name']) {
      if (it && typeof it[kk] === 'string' && it[kk].trim()) return it[kk];
    }
  }
  return null;
}
function newestChatTitle(feed) {
  const nodes = (((feed || {}).data || {}).nodes || []).slice();
  nodes.sort((a, b) => Date.parse(b.last_activity || '') - Date.parse(a.last_activity || ''));
  const n = nodes.find(x => x && x.title);
  return n && n.title;
}
const markers = {
  brief: ((feeds.brief || {}).data || {}).brief_id,
  map: newestChatTitle(feeds.chats),
  chats: firstStr(feeds.chats, ['nodes']),
  git: firstStr(feeds.git, ['repos', 'repositories']),
  usage: firstStr(feeds.usage, ['providers']),
  automation: firstStr(feeds.automation, ['jobs']),
};

// --- run the IIFE once per tab ---------------------------------------------
// The map tab uses Cytoscape in the browser. A tiny stub is enough to prove the
// real graph path builds elements and wires handlers without loading the vendor.
const TABS = ['home', 'brief', 'map', 'chats', 'git', 'usage', 'automation'];
let fails = 0;
for (const tab of TABS) {
  resetDom();
  locationShim.hash = '#' + tab;
  const cyCalls = [];
  function cytoscapeStub(opts) {
    cyCalls.push(opts || {});
    return {
      on() {},
      destroy() {},
      $(selector) { return { selector, select() { return this; } }; },
    };
  }
  const sandbox = {
    window: { MC: { feeds: JSON.parse(JSON.stringify(feeds)) }, addEventListener() {}, removeEventListener() {} },
    document: documentShim, location: locationShim,
    setInterval() { return 0; }, clearInterval() {}, setTimeout(fn) { if (typeof fn === 'function') fn(); return 0; }, clearTimeout() {},
    Math: Math, Date: Date, JSON: JSON, console: { log() {}, warn() {}, error() {} },
    Array: Array, Object: Object, String: String, Number: Number, isFinite: isFinite, parseInt: parseInt, parseFloat: parseFloat,
    cytoscape: cytoscapeStub,
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  try {
    vm.runInNewContext(scriptBody, sandbox, { timeout: 5000 });
  } catch (e) {
    console.error('FAIL: renderer for #' + tab + ' THREW: ' + (e && e.message));
    fails++; continue;
  }
  const main = byId['mc-main'];
  const txt = (main && main.textContent) || '';
  if (!txt.trim()) { console.error('FAIL: #' + tab + ' rendered EMPTY mc-main'); fails++; continue; }
  const stripTxt = (byId['mc-strip'] && byId['mc-strip'].textContent) || '';
  if (tab === 'home' && !/Usage\s*2/.test(stripTxt)) {
    console.error('FAIL: strip does not count normalized usage used_pct rows (strip="' + stripTxt + '")');
    fails++; continue;
  }
  if (tab === 'map') {
    const els = (cyCalls[0] && cyCalls[0].elements) || [];
    const hasNode = els.some(e => e && e.data && !e.data.source && e.data.id);
    const hasEdge = els.some(e => e && e.data && e.data.source && e.data.target);
    if (!cyCalls.length || !hasNode || !hasEdge) {
      console.error('FAIL: #map did not build Cytoscape node+edge elements');
      fails++; continue;
    }
  }
  const marker = markers[tab];
  if (marker && txt.indexOf(marker) === -1) {
    console.error('FAIL: #' + tab + ' output missing expected fixture content "' + marker + '"');
    fails++; continue;
  }
  // sweep FIX 5: if the chats feed carries scan_errors_24h>0, Home must surface it
  // (copy-independent: the count must appear next to a "couldn't be read" phrase).
  if (tab === 'home') {
    const se = ((feeds.chats.data || {}).counts || {}).scan_errors_24h || 0;
    var readMiss = txt.indexOf("couldn't be read") !== -1 || txt.indexOf('couldn’t be read') !== -1;
    if (se > 0 && !readMiss) {
      console.error('FAIL: #home does not surface scan_errors_24h (' + se + ') from the chats feed');
      fails++; continue;
    }
    if (txt.indexOf('chat refresh skipped') === -1) {
      console.error('FAIL: #home does not surface ingest_skipped=true from the chats feed');
      fails++; continue;
    }
    if (txt.indexOf('Usage Snapshot') === -1) {
      console.error('FAIL: #home does not surface yellow automation jobs');
      fails++; continue;
    }
    if (txt.indexOf('Morning Brief') === -1 || txt.indexOf('Read the full brief') === -1) {
      console.error('FAIL: #home is missing the Morning Brief summary');
      fails++; continue;
    }
    if (txt.indexOf('Decisions waiting for you') === -1 ||
        txt.indexOf('Choose the rollout window') === -1 ||
        txt.indexOf('Copy dismiss command') === -1) {
      console.error('FAIL: #home is missing the pinned transactional decision queue');
      fails++; continue;
    }
    if (txt.indexOf('Session monitor') === -1 || txt.indexOf('Recent activity') === -1) {
      console.error('FAIL: #home is missing the session monitor or activity heatmap sections');
      fails++; continue;
    }
    if (txt.indexOf('Reopen this chat') === -1 || txt.indexOf('Read transcript') === -1) {
      console.error('FAIL: #home session monitor is missing a plain action label');
      fails++; continue;
    }
  }
  if (tab === 'map' && txt.indexOf('Why you are seeing this') === -1) {
    console.error('FAIL: #map is missing the side-panel scope explanation');
    fails++; continue;
  }
  if (tab === 'map' && txt.indexOf('Recent chat journal') === -1) {
    console.error('FAIL: #map is missing the recent chat journal');
    fails++; continue;
  }
  if (tab === 'map' && txt.indexOf('Show connections') === -1) {
    console.error('FAIL: #map recent chat journal is missing the connection action');
    fails++; continue;
  }
  if (tab === 'chats' && (txt.indexOf('Open work') === -1 || txt.indexOf('Hide until refresh') === -1 || txt.indexOf('Reopen this chat') === -1 || txt.indexOf('Read transcript') === -1)) {
    console.error('FAIL: #chats is missing the Open work list, temporary-hide action, or plain chat action labels');
    fails++; continue;
  }
  if (tab === 'usage' && txt.indexOf('Decision cards') === -1) {
    console.error('FAIL: #usage is missing the decision-card section');
    fails++; continue;
  }
  if (tab === 'automation' &&
      (txt.indexOf('Outcome Extractor') === -1 ||
       txt.indexOf('Next run:') === -1 || txt.indexOf('Run history:') === -1 ||
       txt.indexOf('failure streak 2') === -1 || txt.indexOf('Run now') === -1 ||
       txt.indexOf('Status: awaiting activation') === -1 ||
       txt.indexOf('Next run: available after activation') === -1 ||
       txt.indexOf('retries 06:47 and 06:54') === -1 ||
       txt.indexOf(ACTIVATION_STALE_LABEL) !== -1 ||
       txt.indexOf(TOKEN_PREFIX_ONLY) !== -1 || txt.indexOf(TOKEN_SECRET_SUFFIX) !== -1 ||
       txt.indexOf('«REDACTED-SECRET»') === -1)) {
    console.error('FAIL: #automation is missing next-run, distinct history, streak, Run now, or activation fields');
    fails++; continue;
  }
  if (tab === 'brief' &&
      (txt.indexOf('NEEDS YOU') === -1 || txt.indexOf('What happened') === -1 ||
       txt.indexOf('Open work changes') === -1 || txt.indexOf('Confirmed') === -1)) {
    console.error('FAIL: #brief is missing ordered sections or visible trust labels');
    fails++; continue;
  }
  console.log('PASS: #' + tab + ' renders (' + txt.length + ' chars' + (marker ? ', contains "' + marker.slice(0, 30) + '"' : '') + ')');
}
if (fails) { console.error('render-smoke: ' + fails + ' tab(s) FAILED'); process.exit(1); }
console.log('render-smoke: all ' + TABS.length + ' tabs render over fixtures');
process.exit(0);
