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
// Defect (b) JS-guard coverage: a daily brief older than 2x its cadence but still
// inside a LEGIT (within-horizon) valid_until window must NOT show the stale
// banner — the guard honors product validity over the poll cadence. Composed at
// local midnight today (a real, up-to-24h-old compose epoch), valid until next
// local midnight (the true daily horizon). Anchoring both to local midnight keeps
// the compose epoch <= now and the horizon in the future for ANY time of day/TZ/DST,
// so the round-6 next-local-midnight cap doesn't make this fixture midnight-flaky.
const NOW_S = Math.floor(Date.now() / 1000);
function localMidnightOf(sec) { // 00:00 local on sec's day (DST-correct)
  const d = new Date(sec * 1000);
  return Math.floor(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0).getTime() / 1000);
}
function nextLocalMidnightJS(sec) { // mirrors the page's nextLocalMidnight
  const d = new Date(sec * 1000);
  return Math.floor(new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 0, 0, 0, 0).getTime() / 1000);
}
if (feeds.brief) {
  const composedAt = localMidnightOf(NOW_S);
  feeds.brief.generated_epoch = composedAt;
  feeds.brief.cadence_s = 300;
  feeds.brief.valid_until = nextLocalMidnightJS(composedAt);
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
  // Defect (b): a within-validity brief must not be flagged stale despite a very
  // old compose epoch (the guard honors valid_until, not the poll cadence).
  if (tab === 'brief' && txt.indexOf('Data is older than expected') !== -1) {
    console.error('FAIL: #brief flagged stale while inside its valid_until window');
    fails++; continue;
  }
  console.log('PASS: #' + tab + ' renders (' + txt.length + ' chars' + (marker ? ', contains "' + marker.slice(0, 30) + '"' : '') + ')');
}
// Defect (b) NEGATIVE case: an absurd far-future valid_until (year 2001 compose +
// year 2100 validity) is malformed and must NOT suppress staleness — the guard
// only honors validity within 2 days of the compose epoch, so this brief MUST
// show the stale banner. (Round-2 locked the OPPOSITE assertion; that encoded the
// defect this round fixes.)
(function negativeFarFutureValidity() {
  const negFeeds = JSON.parse(JSON.stringify(feeds));
  negFeeds.brief.generated_epoch = 1000000000;   // year 2001, age >> 2x cadence
  negFeeds.brief.valid_until = 4102444800;        // year 2100, absurdly far future
  negFeeds.brief.cadence_s = 86400;               // nonzero so the stale branch can fire
  resetDom();
  locationShim.hash = '#brief';
  const sandbox = {
    window: { MC: { feeds: negFeeds }, addEventListener() {}, removeEventListener() {} },
    document: documentShim, location: locationShim,
    setInterval() { return 0; }, clearInterval() {}, setTimeout(fn) { if (typeof fn === 'function') fn(); return 0; }, clearTimeout() {},
    Math: Math, Date: Date, JSON: JSON, console: { log() {}, warn() {}, error() {} },
    Array: Array, Object: Object, String: String, Number: Number, isFinite: isFinite, parseInt: parseInt, parseFloat: parseFloat,
    cytoscape() { return { on() {}, destroy() {}, $() { return { select() { return this; } }; } }; },
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  try {
    vm.runInNewContext(scriptBody, sandbox, { timeout: 5000 });
  } catch (e) {
    console.error('FAIL: negative far-future brief render THREW: ' + (e && e.message));
    fails++; return;
  }
  const txt = (byId['mc-main'] && byId['mc-main'].textContent) || '';
  if (txt.indexOf('Data is older than expected') === -1) {
    console.error('FAIL: absurd far-future valid_until suppressed the stale banner (staleness not restored)');
    fails++; return;
  }
  console.log('PASS: absurd far-future valid_until is rejected — brief shows stale banner');
})();

// ER-109 round 6: the validity horizon is next local midnight, NOT a flat 2-day slab.
// A 40h-old brief carrying a valid_until 7h in the future (a ~47h span) was ACCEPTED
// as fresh under the old 48h bound; it must now be REJECTED and show the stale banner.
// valid_until is always > now and always >> nextLocalMidnight(a 40h-old epoch), so the
// verdict is stale for any time of day/TZ.
(function negativeFortySevenHourValidity() {
  const negFeeds = JSON.parse(JSON.stringify(feeds));
  negFeeds.brief.generated_epoch = NOW_S - 40 * 3600;   // 40h old
  negFeeds.brief.valid_until = NOW_S + 7 * 3600;         // 7h out -> 47h span (<=48h)
  negFeeds.brief.cadence_s = 3600;                        // 2x cadence = 2h << 40h age
  resetDom();
  locationShim.hash = '#brief';
  const sandbox = {
    window: { MC: { feeds: negFeeds }, addEventListener() {}, removeEventListener() {} },
    document: documentShim, location: locationShim,
    setInterval() { return 0; }, clearInterval() {}, setTimeout(fn) { if (typeof fn === 'function') fn(); return 0; }, clearTimeout() {},
    Math: Math, Date: Date, JSON: JSON, console: { log() {}, warn() {}, error() {} },
    Array: Array, Object: Object, String: String, Number: Number, isFinite: isFinite, parseInt: parseInt, parseFloat: parseFloat,
    cytoscape() { return { on() {}, destroy() {}, $() { return { select() { return this; } }; } }; },
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  try {
    vm.runInNewContext(scriptBody, sandbox, { timeout: 5000 });
  } catch (e) {
    console.error('FAIL: negative 47h-validity brief render THREW: ' + (e && e.message));
    fails++; return;
  }
  const txt = (byId['mc-main'] && byId['mc-main'].textContent) || '';
  if (txt.indexOf('Data is older than expected') === -1) {
    console.error('FAIL: a 47h-span valid_until on a 40h-old brief suppressed the stale banner (horizon too loose)');
    fails++; return;
  }
  console.log('PASS: ~47h valid_until on a 40h-old brief is rejected — brief shows stale banner');
})();

// ER-109 round 7: valid_until is a HARD expiry across the exact-midnight rollover.
// A brief composed 23:59 local, valid to the next local midnight, must render fresh
// 30s before midnight, then show the stale banner AT midnight (now == valid_until)
// and 5 min after. Pin Date.now() (the page reads nowS() = Date.now()/1000) via a
// proxy so the three boundary clocks are exact regardless of real wall-clock/TZ.
(function hardExpiryAtMidnight() {
  const MID = nextLocalMidnightJS(NOW_S);   // a real local midnight
  const BRIEF_EPOCH = MID - 60;             // composed 23:59 local, valid to MID
  const cases = [
    { offset: -30, expectStale: false, label: '23:59:30 (fresh)' },
    { offset: 0,   expectStale: true,  label: '00:00:00 exactly (stale)' },
    { offset: 300, expectStale: true,  label: '00:05:00 (stale)' },
  ];
  for (const c of cases) {
    const negFeeds = JSON.parse(JSON.stringify(feeds));
    negFeeds.brief.generated_epoch = BRIEF_EPOCH;
    negFeeds.brief.valid_until = MID;
    negFeeds.brief.cadence_s = 300;
    const FixedDate = new Proxy(Date, {
      get(t, p) { return p === 'now' ? () => (MID + c.offset) * 1000 : t[p]; },
      construct(t, a) { return a.length ? new t(...a) : new t((MID + c.offset) * 1000); },
    });
    resetDom();
    locationShim.hash = '#brief';
    const sandbox = {
      window: { MC: { feeds: negFeeds }, addEventListener() {}, removeEventListener() {} },
      document: documentShim, location: locationShim,
      setInterval() { return 0; }, clearInterval() {}, setTimeout(fn) { if (typeof fn === 'function') fn(); return 0; }, clearTimeout() {},
      Math: Math, Date: FixedDate, JSON: JSON, console: { log() {}, warn() {}, error() {} },
      Array: Array, Object: Object, String: String, Number: Number, isFinite: isFinite, parseInt: parseInt, parseFloat: parseFloat,
      cytoscape() { return { on() {}, destroy() {}, $() { return { select() { return this; } }; } }; },
    };
    sandbox.window.window = sandbox.window;
    sandbox.globalThis = sandbox;
    try {
      vm.runInNewContext(scriptBody, sandbox, { timeout: 5000 });
    } catch (e) {
      console.error('FAIL: hard-expiry ' + c.label + ' render THREW: ' + (e && e.message));
      fails++; continue;
    }
    const txt = (byId['mc-main'] && byId['mc-main'].textContent) || '';
    const isStale = txt.indexOf('Data is older than expected') !== -1;
    if (isStale !== c.expectStale) {
      console.error('FAIL: hard-expiry ' + c.label + ' -> stale banner ' + (isStale ? 'shown' : 'absent') + ', expected ' + (c.expectStale ? 'shown' : 'absent'));
      fails++; continue;
    }
    console.log('PASS: hard-expiry ' + c.label + ' -> stale banner ' + (isStale ? 'shown' : 'absent'));
  }
})();

// ER-109 round 6: clock skew (a FUTURE chats generated_epoch) must render the SAME
// untrustworthy state on the Home Chats card AND the "Open work" strip segment as it
// already does on the banner and the strip dot — not stay green. guard()'s g.flag is
// the single source; all consumers read it. Assert via the state CSS class (color is
// the whole point), walking the rendered node tree the DOM shim records on className.
(function negativeSkewHomeConsistency() {
  function collectClass(el, pred, out) {
    if (!el || typeof el !== 'object') return out;
    if (typeof el.className === 'string' && pred(el)) out.push(el);
    (el.children || []).forEach(c => collectClass(c, pred, out));
    return out;
  }
  const has = s => el => el.className.indexOf(s) !== -1;
  const skewFeeds = JSON.parse(JSON.stringify(feeds));
  // ensure chats renders a real card/segment, then push its timestamp into the future
  skewFeeds.chats.ok = true;
  skewFeeds.chats.generated_epoch = NOW_S + 3600;
  if (!skewFeeds.chats.data) skewFeeds.chats.data = {};
  if (!Array.isArray(skewFeeds.chats.data.nodes)) skewFeeds.chats.data.nodes = [{ id: 'a' }];
  resetDom();
  locationShim.hash = '#home';
  const sandbox = {
    window: { MC: { feeds: skewFeeds }, addEventListener() {}, removeEventListener() {} },
    document: documentShim, location: locationShim,
    setInterval() { return 0; }, clearInterval() {}, setTimeout(fn) { if (typeof fn === 'function') fn(); return 0; }, clearTimeout() {},
    Math: Math, Date: Date, JSON: JSON, console: { log() {}, warn() {}, error() {} },
    Array: Array, Object: Object, String: String, Number: Number, isFinite: isFinite, parseInt: parseInt, parseFloat: parseFloat,
    cytoscape() { return { on() {}, destroy() {}, $() { return { select() { return this; } }; } }; },
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  try {
    vm.runInNewContext(scriptBody, sandbox, { timeout: 5000 });
  } catch (e) {
    console.error('FAIL: skew Home render THREW: ' + (e && e.message));
    fails++; return;
  }
  // "Open work" is the first strip segment; its state color lives on the inner glyph,
  // so gather the class names of the whole segment subtree.
  const seg = collectClass(byId['mc-strip'], has('mc-strip-seg '), [])[0]
           || collectClass(byId['mc-strip'], has('mc-strip-seg'), [])[0];
  const headline = collectClass(byId['mc-main'], has('mc-card-headline'), [])[0];
  const segCls = seg ? collectClass(seg, () => true, []).map(e => e.className).join(' ') : '';
  const cardCls = headline ? headline.className : '';
  if (segCls.indexOf('mc-state-amber') === -1) {
    console.error('FAIL: skewed chats feed left the "Open work" strip segment green (got: ' + (segCls || '(none)') + ')');
    fails++; return;
  }
  if (cardCls.indexOf('mc-state-amber') === -1) {
    console.error('FAIL: skewed chats feed left the Home Chats card green (got: ' + (cardCls || '(none)') + ')');
    fails++; return;
  }
  console.log('PASS: clock skew turns the Open work segment AND the Chats card amber (banner/dot/card/segment agree)');
})();

// ER-109 round 5: full-ingest freshness must come from the feed's computed
// full_ingest_stale flag (nightly SLA via mission_control_common.nested_ingest_stale),
// not a re-implemented 1800s threshold. A healthy nightly ingest ~3286s old (past the
// old buggy 30-minute threshold, well inside the 30h SLA) must render NOT-stale; a
// genuinely missed nightly (>30h) must render stale. Both fixtures carry the raw age
// AND the flag a real chat-graph export would stamp for that age, so a renderer that
// regresses to reading last_full_ingest_age_s directly fails the healthy case.
function renderHomeWithChatsCounts(overrides) {
  const f = JSON.parse(JSON.stringify(feeds));
  Object.assign(f.chats.data.counts, { ingest_skipped: false }, overrides);
  resetDom();
  locationShim.hash = '#home';
  const sandbox = {
    window: { MC: { feeds: f }, addEventListener() {}, removeEventListener() {} },
    document: documentShim, location: locationShim,
    setInterval() { return 0; }, clearInterval() {}, setTimeout(fn) { if (typeof fn === 'function') fn(); return 0; }, clearTimeout() {},
    Math: Math, Date: Date, JSON: JSON, console: { log() {}, warn() {}, error() {} },
    Array: Array, Object: Object, String: String, Number: Number, isFinite: isFinite, parseInt: parseInt, parseFloat: parseFloat,
    cytoscape() { return { on() {}, destroy() {}, $() { return { select() { return this; } }; } }; },
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  vm.runInNewContext(scriptBody, sandbox, { timeout: 5000 });
  return (byId['mc-main'] && byId['mc-main'].textContent) || '';
}
(function fullIngestFreshnessHealthy() {
  let txt;
  try {
    txt = renderHomeWithChatsCounts({ last_full_ingest_age_s: 3286, full_ingest_stale: false });
  } catch (e) {
    console.error('FAIL: healthy full-ingest home render THREW: ' + (e && e.message));
    fails++; return;
  }
  if (txt.indexOf('full chat scan is stale') !== -1) {
    console.error('FAIL: healthy nightly ingest (age 3286s, full_ingest_stale=false) rendered stale');
    fails++; return;
  }
  console.log('PASS: healthy nightly full ingest (age 3286s) renders NOT-stale');
})();
(function fullIngestFreshnessMissed() {
  let txt;
  try {
    txt = renderHomeWithChatsCounts({ last_full_ingest_age_s: 111600, full_ingest_stale: true }); // ~31h
  } catch (e) {
    console.error('FAIL: missed full-ingest home render THREW: ' + (e && e.message));
    fails++; return;
  }
  if (txt.indexOf('full chat scan is stale') === -1) {
    console.error('FAIL: genuinely missed nightly ingest (age 111600s, full_ingest_stale=true) did not render stale');
    fails++; return;
  }
  console.log('PASS: genuinely missed nightly full ingest (age ~31h) renders stale');
})();
(function fullIngestFreshnessUnknown() {
  let txt;
  try {
    txt = renderHomeWithChatsCounts({ last_full_ingest_age_s: -60, full_ingest_stale: undefined, full_ingest_state: 'unknown' });
  } catch (e) {
    console.error('FAIL: unknown full-ingest home render THREW: ' + (e && e.message));
    fails++; return;
  }
  if (txt.indexOf('full chat scan freshness unknown') === -1) {
    console.error('FAIL: unknown full-ingest state did not render an honest unknown warning');
    fails++; return;
  }
  console.log('PASS: unknown full-ingest freshness renders an honest warning');
})();

if (fails) { console.error('render-smoke: ' + fails + ' tab(s) FAILED'); process.exit(1); }
console.log('render-smoke: all ' + TABS.length + ' tabs render over fixtures');
process.exit(0);
