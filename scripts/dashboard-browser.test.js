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

function utcDate(offsetDays) {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + offsetDays))
    .toISOString().slice(0, 10);
}

function assert(ok, message) {
  if (!ok) throw new Error(message);
  passed++;
}

async function waitForText(page, selector, expected) {
  await page.waitForFunction(({ selector: query, expected: text }) => {
    const node = document.querySelector(query);
    return node && (node.textContent || '').includes(text);
  }, { selector, expected });
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
  for (const name of ['usage', 'headroom', 'git', 'chats', 'automation', 'decisions', 'attention', 'brief']) {
    const obj = JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'));
    fs.writeFileSync(path.join(state, 'data', `${name}.json`), JSON.stringify(obj) + '\n');
    fs.writeFileSync(path.join(state, 'data', `${name}.js`),
      `window.MC=window.MC||{feeds:{},feedErrors:{}};window.MC.feeds[${JSON.stringify(name)}]=${JSON.stringify(obj)};\n`);
    fs.writeFileSync(path.join(state, 'data', `${name}.error.js`),
      `window.MC=window.MC||{feeds:{},feedErrors:{}};window.MC.feedErrors[${JSON.stringify(name)}]=null;\n`);
  }
  return state;
}

function writeStateFeed(state, name, obj) {
  fs.writeFileSync(path.join(state, 'data', `${name}.json`), JSON.stringify(obj) + '\n');
  fs.writeFileSync(path.join(state, 'data', `${name}.js`),
    `window.MC=window.MC||{feeds:{},feedErrors:{}};window.MC.feeds[${JSON.stringify(name)}]=${JSON.stringify(obj)};\n`);
}

function syntheticLargeChats() {
  const envelope = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'chats.json'), 'utf8'));
  const nodes = [];
  const edges = [];
  const looseEnds = [];
  const base = Date.now();
  for (let i = 0; i < 321; i++) {
    const provider = i % 2 ? 'claude' : 'codex';
    const id = `bulk-${String(i).padStart(4, '0')}`;
    const key = `${provider}:${id}`;
    nodes.push({
      id, provider,
      repo: i === 320 ? 'repo-b' : `repo-${['a', 'b', 'c'][i % 3]}`,
      title: i === 320 ? 'Map Needle beyond the old cap' : `Synthetic chat ${String(i).padStart(4, '0')}`,
      last_activity: new Date(base - (i + 1) * 60000).toISOString(),
      first_seen_at: new Date(base - (i + 2) * 60000).toISOString(),
      live: false, open_ends: [],
      resume_cmd: `resume ${key}`, view_cmd: `view ${key}`,
    });
    if (i > 0) edges.push({ src: 'codex:bulk-0000', dst: key, type: 'spawned', source: 'synthetic', confidence: 1 });
  }
  for (let i = 0; i < 90; i++) {
    const n = nodes[i + 1];
    looseEnds.push({
      id: `open-${i}`, kind: 'closeout_handoff', source_node: `${n.provider}:${n.id}`,
      title: i === 80 ? 'Open Needle beyond the old cap' : `Synthetic open work ${String(i).padStart(3, '0')}`,
      repo: n.repo, text: `Synthetic handoff ${i}`, action_hint: `finish synthetic handoff ${i}`,
      age_days: 5, severity: 'amber', resolve_cmd: `resolve ${i}`,
    });
  }
  envelope.generated_epoch = Math.floor(Date.now() / 1000);
  envelope.generated_at = new Date().toISOString();
  envelope.data = { counts: { new_today: 321, scan_errors_24h: 0 }, nodes, edges, loose_ends: looseEnds };
  return envelope;
}

async function operatorUxAudit(browser, root) {
  const failures = [];
  const check = (ok, message) => {
    if (!ok) failures.push(message);
    else passed++;
  };
  const block = async (label, fn) => {
    try { await fn(); }
    catch (error) { failures.push(`${label}: ${error.message}`); }
  };
  const url = tab => `${pathToFileURL(path.join(root, 'index.html')).href}#${tab}`;
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(5000);
  try {
    await block('navigation semantics', async () => {
      await page.goto(url('chats'), { waitUntil: 'load' });
      const semantics = await page.evaluate(() => {
        const active = document.querySelector('#mc-nav .mc-tab-active');
        const status = document.getElementById('mc-tab-status');
        return {
          title: document.title,
          current: active && active.getAttribute('aria-current'),
          navLabel: document.getElementById('mc-nav').getAttribute('aria-label'),
          statusRole: status && status.getAttribute('role'),
          statusLive: status && status.getAttribute('aria-live'),
          statusText: status && status.textContent,
        };
      });
      check(semantics.title === 'Chats — Mission Control', `page title does not name the Chats view (${semantics.title})`);
      check(semantics.current === 'page', `active dashboard link lacks aria-current=page (${semantics.current})`);
      check(semantics.navLabel === 'Dashboard sections', `dashboard navigation has no useful accessible label (${semantics.navLabel})`);
      check(semantics.statusRole === 'status' && semantics.statusLive === 'polite' && /Chats/.test(semantics.statusText || ''),
        `tab change announcer is missing or incomplete (${JSON.stringify(semantics)})`);
    });

    await block('Home attention rows use keyboard-native navigation', async () => {
      await page.goto(url('home'), { waitUntil: 'load' });
      const expand = page.getByRole('button', { name: 'Show more details' });
      if (await expand.count()) await expand.click();
      const action = page.locator('.mc-attention .mc-row-click').first();
      check(await action.count() === 1, 'Home has no testable Needs attention destination');
      check(await action.evaluate(node => node.tagName) === 'BUTTON' && await action.getAttribute('type') === 'button',
        'Home Needs attention destination is not a native button');
      await action.focus();
      await action.press('Enter');
      check((await page.evaluate(() => location.hash)) !== '#home', 'Enter did not activate the Home attention destination');
    });

    await block('usage ordering and provenance', async () => {
      await page.goto(url('usage'), { waitUntil: 'load' });
      const now = Math.floor(Date.now() / 1000);
      const dates = { latest: utcDate(0), minus1: utcDate(-1), minus2: utcDate(-2), old: utcDate(-40) };
      await page.evaluate(({ nowEpoch, dates }) => {
        const live = window.MC.feeds.headroom;
        live.generated_epoch = nowEpoch;
        live.generated_at = new Date(nowEpoch * 1000).toISOString();
        live.ok = true;
        live.error = null;
        live.cadence_s = 60;
        live.data.rows = [
          { id:'x_api:month', provider:'x_api', label:'X API', kind:'quota', window_label:'Monthly reads', health:'ok', band:'green', confidence:'live', remaining_pct:92, used_pct:8, age_s:7, fetched_epoch:nowEpoch-7, source:'x-live',
            detail:{ project_usage:12300, project_cap:50000, daily_reads:[
              {date:dates.latest,reads:4}, {date:dates.minus2,reads:3}, {date:dates.minus1,reads:5},
              {date:dates.old,reads:9000}, {date:dates.minus2,reads:-9}, {date:'not-a-date',reads:100},
              {date:dates.minus1,reads:'7'}, {date:dates.minus2,reads:1.5}
            ] } },
          { id:'critical:week', provider:'critical', label:'Critical', kind:'quota', window_label:'Weekly', health:'ok', band:'red', confidence:'live', remaining_pct:2, used_pct:98, age_s:65, fetched_epoch:nowEpoch-465, source:'critical-live' },
          { id:'low:week', provider:'low', label:'Low', kind:'quota', window_label:'Weekly', health:'ok', band:'orange', confidence:'live', remaining_pct:15, used_pct:85, age_s:305, fetched_epoch:nowEpoch-305, source:'low-live' },
          { id:'claude:week', provider:'claude', label:'Claude', kind:'quota', window_label:'Weekly', health:'auth', band:'red', confidence:'stale', remaining_pct:0, used_pct:100, age_s:86400, fetched_epoch:nowEpoch-86400, source:'oauth', note:'no Claude Code OAuth token in Keychain' },
        ];
        const snapshot = window.MC.feeds.usage;
        snapshot.generated_epoch = nowEpoch - 600;
        snapshot.generated_at = new Date((nowEpoch - 600) * 1000).toISOString();
        snapshot.data.providers = [
          { provider:'copilot', window:'monthly', used_pct:40, confidence:'live', health:'ok', source:'snapshot-only' },
          { provider:'unconnected', window:'monthly', used_pct:null, confidence:'unknown', health:'absent', source:'none' },
        ];
        snapshot.data.waste = [];
        window.dispatchEvent(new Event('hashchange'));
      }, { nowEpoch: now, dates });
      await page.waitForTimeout(50);
      const cards = await page.locator('.mc-decision-grid > .mc-card').evaluateAll(els => els.map(el => ({
        title: (el.querySelector('.mc-decision-title') || {}).textContent || '', text: el.innerText,
      })));
      check(cards.length === 6, `usage test expected six provider cards, got ${cards.length}`);
      check(cards[0] && cards[0].title === 'Critical', `critical provider is not first (${cards.map(x => x.title).join(', ')})`);
      check(cards[1] && cards[1].title === 'Low', `low-headroom provider is not second (${cards.map(x => x.title).join(', ')})`);
      const claudeIndex = cards.findIndex(x => x.title === 'Claude');
      check(claudeIndex > 1, `signed-out Claude sorted ahead of live low-headroom providers (${cards.map(x => x.title).join(', ')})`);
      check(cards.some(x => x.title === 'Claude' && /signed out/.test(x.text) && /token wait/i.test(x.text)),
        'signed-out Claude still shows a last-known percent instead of signed out');
      const unconnectedIndex = cards.findIndex(x => /Not captured/.test(x.text));
      const healthySnapshotIndex = cards.findIndex(x => /Copilot/.test(x.title));
      check(unconnectedIndex >= 0 && healthySnapshotIndex >= 0 && unconnectedIndex < healthySnapshotIndex,
        `provider needing setup is not before healthy snapshot provider (${cards.map(x => x.title).join(', ')})`);
      check(cards.some(x => x.title === 'Critical' && /Reading:\s*7m ago/.test(x.text) && /Source:\s*critical-live/.test(x.text) && /Cadence:\s*live · every 1 min/.test(x.text)),
        'live provider card lacks its own reading age, source, or one-minute cadence');
      check(cards.some(x => /Copilot/.test(x.title) && /Reading:\s*10m ago/.test(x.text) && /Cadence:\s*snapshot · every 30 min/.test(x.text)),
        'snapshot fallback card lacks its own reading age or 30-minute cadence');
      check(cards.some(x => x.title === 'X API' && /12,300 of 50,000 posts read this month/.test(x.text) &&
        new RegExp(`7-day activity: 12 reads total · latest ${dates.latest}: 4`).test(x.text)),
        'X API card lacks the validated 7-day total/latest reading alongside monthly usage');
      const usageText = await page.locator('#mc-main').innerText();
      check(/Live provider cards update every 1 minute/.test(usageText) && /snapshot cards update every 30 minutes/.test(usageText),
        'mixed live/snapshot cadence copy is inaccurate or missing');
      check(!/\b\d+[smhd] ago old\b/.test(usageText), `usage renders the duplicated age phrase "ago old"`);
      const usageStrip = await page.getByRole('button', { name: 'Jump to Usage' }).evaluate(el => ({
        state: (el.querySelector('.mc-glyph') || {}).title || '',
        count: (el.querySelector('.mc-num') || {}).textContent || '',
      }));
      check(usageStrip.state === 'red' && usageStrip.count === '3',
        `top Usage indicator ignores live red/amber headroom (${JSON.stringify(usageStrip)})`);
      await page.evaluate(nowEpoch => {
        window.MC.feedErrors.headroom = { ok: false, error: 'new collector failure', generated_epoch: nowEpoch + 1 };
        window.dispatchEvent(new Event('hashchange'));
      }, now);
      await page.waitForTimeout(40);
      const fallbackText = await page.locator('#mc-main').innerText();
      check(!/Critical|Low|X API/.test(fallbackText) && /Copilot|Unconnected/.test(fallbackText),
        'feed-level headroom failure did not replace live cards with snapshot fallbacks');
      check(/Live usage feed is not trusted.*new collector failure/i.test(fallbackText),
        'feed-level headroom failure lacks an operator-visible warning');
    });

    await block('usage reset countdowns stay visible when full, empty, or signed out', async () => {
      await page.goto(url('usage'), { waitUntil: 'load' });
      const now = Math.floor(Date.now() / 1000);
      await page.evaluate(nowEpoch => {
        window.MC.feedErrors = window.MC.feedErrors || {};
        window.MC.feedErrors.headroom = null;
        const live = window.MC.feeds.headroom;
        live.generated_epoch = nowEpoch;
        live.generated_at = new Date(nowEpoch * 1000).toISOString();
        live.ok = true;
        live.error = null;
        live.cadence_s = 60;
        live.data.rows = [
          { id:'empty:week', provider:'empty', label:'Empty', kind:'quota', window_label:'Weekly', window_class:'week',
            health:'ok', band:'red', confidence:'live', remaining_pct:0, used_pct:100, age_s:8,
            fetched_epoch:nowEpoch-8, source:'empty-live', resets_epoch:nowEpoch+3663 },
          { id:'full:week', provider:'full', label:'Full', kind:'quota', window_label:'Weekly', window_class:'week',
            health:'ok', band:'green', confidence:'live', remaining_pct:100, used_pct:0, age_s:8,
            fetched_epoch:nowEpoch-8, source:'full-live', resets_epoch:nowEpoch+7200 },
          { id:'glm:5h', provider:'glm', label:'GLM', kind:'quota', window_label:'5-hour', window_class:'5h',
            health:'ok', band:'green', confidence:'live', remaining_pct:100, used_pct:0, age_s:8,
            fetched_epoch:nowEpoch-8, source:'zai-quota-limit', resets_epoch:null },
          { id:'claude:week', provider:'claude', label:'Claude', kind:'quota', window_label:'Weekly', window_class:'week',
            health:'auth', band:'none', confidence:'stale', remaining_pct:null, used_pct:null, age_s:86400,
            fetched_epoch:nowEpoch-86400, source:'oauth', note:'no Claude Code OAuth token in Keychain',
            resets_epoch:nowEpoch+86400 },
          { id:'moonshot:balance', provider:'moonshot', label:'Moonshot', kind:'balance', window_label:'API balance',
            window_class:'balance', health:'ok', band:'cash', confidence:'live', remaining_pct:null,
            balance_usd:12.42, age_s:8, fetched_epoch:nowEpoch-8, source:'moonshot-balance', resets_epoch:null },
        ];
        window.MC.feeds.usage.data.providers = [];
        window.MC.feeds.usage.data.waste = [];
        window.dispatchEvent(new Event('hashchange'));
      }, now);
      await page.waitForTimeout(50);
      const cards = await page.locator('.mc-decision-grid > .mc-card').evaluateAll(els => els.map(el => ({
        title: (el.querySelector('.mc-decision-title') || {}).textContent || '', text: el.innerText,
      })));
      const countdowns = await page.locator('.mc-countdown').evaluateAll(els => els.map(el => el.textContent || ''));
      check(cards.some(x => x.title === 'Empty' && /\bempty\b/.test(x.text) && /empty — resets in/.test(x.text)),
        'exhausted quota card hides the reset countdown');
      check(cards.some(x => x.title === 'Full' && /\bfull\b/.test(x.text) && /resets in /.test(x.text) && !/empty —/.test(x.text)),
        'full quota card hides the reset countdown');
      check(countdowns.some(t => /full — 5-hour clock starts on next use/.test(t)),
        'unused 5-hour window with no clock does not explain when the countdown starts');
      check(cards.some(x => x.title === 'Claude' && /signed out/.test(x.text) && /resets in /.test(x.text)),
        'signed-out weekly Claude hides a known reset countdown');
      check(countdowns.some(t => /prepaid — no scheduled reset/.test(t)),
        'prepaid balance omits a uniform reset line');
      check(countdowns.every(t => t.trim().length > 0),
        'a usage window rendered a blank reset line');
    });

    await block('large Chats search and persisted filters', async () => {
      await page.goto(url('chats'), { waitUntil: 'load' });
      const search = page.getByLabel('Search chats and open work');
      await search.fill('Synthetic');
      await waitForText(page, '#mc-open-search-status',
        'Showing 50 of 90 matches across 90 open work items');
      check(/Showing 100 of 320 matches across 321 chats/.test(await page.locator('#mc-chat-search-status').innerText()),
        'Chats broad-search count does not distinguish matches shown from matches found');
      check(/Showing 50 of 90 matches across 90 open work items/.test(await page.locator('#mc-open-search-status').innerText()),
        'Open-work broad-search count does not distinguish matches shown from matches found');
      await search.fill('Map Needle beyond the old cap');
      await waitForText(page, '#mc-chat-search-status', '1 match across 321 chats');
      check(await page.locator('.mc-chatrow-title', { hasText: 'Map Needle beyond the old cap' }).count() === 1,
        'Chats search cannot reach a chat beyond the old 100-row cap');
      check(/1 match across 321 chats/.test(await page.locator('#mc-chat-search-status').innerText()),
        'Chats search does not expose a visible result/total count');
      await search.fill('Open Needle beyond the old cap');
      await waitForText(page, '#mc-open-search-status', '1 match across 90 open work items');
      check(await page.locator('.mc-row-problem', { hasText: 'Open Needle beyond the old cap' }).count() === 1,
        'Open-work search cannot reach an item beyond the old 50-row cap');
      check(/1 match across 90 open work items/.test(await page.locator('#mc-open-search-status').innerText()),
        'Open-work search does not expose a visible result/total count');

      await search.fill('Needle');
      await waitForText(page, '#mc-open-search-status', '1 match across 90 open work items');
      await page.locator('#mc-chat-repo-filter').selectOption('repo-b');
      const openOnly = page.getByRole('button', { name: 'Only chats with unfinished work' });
      await openOnly.click();
      const claudeFilter = page.getByRole('button', { name: 'Claude', exact: true });
      await claudeFilter.click();
      const chatClickControls = await page.locator('#mc-main .mc-chip-btn').evaluateAll(els => els.map(el => ({
        tag:el.tagName, type:el.getAttribute('type'), pressed:el.getAttribute('aria-pressed'),
      })));
      check(chatClickControls.length > 0 && chatClickControls.every(x => x.tag === 'BUTTON' && x.type === 'button'),
        `Chats filter/focus controls are not native buttons (${JSON.stringify(chatClickControls)})`);
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'load' }),
        page.reload({ waitUntil: 'load' }),
      ]);
      check(await page.getByLabel('Search chats and open work').inputValue() === 'Needle', 'Chats query did not survive reload');
      check(await page.locator('#mc-chat-repo-filter').inputValue() === 'repo-b', 'Chats repo filter did not survive reload');
      check(await page.getByRole('button', { name: 'Only chats with unfinished work' }).getAttribute('aria-pressed') === 'true',
        'Chats unfinished-only filter did not survive reload');
      check(await page.getByRole('button', { name: 'Claude', exact: true }).getAttribute('aria-pressed') === 'false',
        'Chats provider filter did not survive reload');

      await page.getByLabel('Search chats and open work').fill('');
      await page.locator('#mc-chat-repo-filter').selectOption('');
      if (await page.getByRole('button', { name: 'Only chats with unfinished work' }).getAttribute('aria-pressed') === 'true') await openOnly.click();
      if (await page.getByRole('button', { name: 'Claude', exact: true }).getAttribute('aria-pressed') === 'false') await claudeFilter.click();
      await page.evaluate(() => window.scrollTo(0, 900));
      const before = await page.evaluate(() => scrollY);
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'load' }),
        page.reload({ waitUntil: 'load' }),
      ]);
      await page.waitForTimeout(80);
      const after = await page.evaluate(() => scrollY);
      check(before > 500 && after > 500 && Math.abs(after - before) < 160,
        `scroll context did not survive reload (${before} -> ${after})`);
    });

    await block('large Map search and native controls', async () => {
      await page.goto(url('map'), { waitUntil: 'load' });
      const search = page.getByLabel('Search map chats');
      await search.fill('Synthetic chat');
      await waitForText(page, '#mc-map-search-status',
        'Showing 260 of 320 matches across 321 connected chats');
      check(/Showing 260 of 320 matches across 321 connected chats/.test(await page.locator('#mc-map-search-status').innerText()),
        'Map broad-search count does not distinguish matches shown from matches found');
      await search.fill('Map Needle beyond the old cap');
      await waitForText(page, '#mc-map-search-status', '1 match across 321 connected chats');
      check(/1 match across 321 connected chats/.test(await page.locator('#mc-map-search-status').innerText()),
        'Map search does not expose a visible result/total count');
      await page.locator('#mc-map-repo-filter').selectOption('repo-b');
      await search.press('Enter');
      await page.waitForTimeout(80);
      check(await page.locator('.mc-side-title', { hasText: 'Map Needle beyond the old cap' }).count() === 1,
        'Map search cannot focus a chat beyond the old 260-node cap');
      const clickControls = await page.locator('#mc-main .mc-chip-btn').evaluateAll(els => els.map(el => ({ tag:el.tagName, type:el.getAttribute('type') })));
      check(clickControls.length > 0 && clickControls.every(x => x.tag === 'BUTTON' && x.type === 'button'),
        `Map chip controls are not native buttons (${JSON.stringify(clickControls)})`);
      const sideConnections = await page.locator('.mc-side-conn').evaluateAll(els => els.map(el => el.tagName));
      check(sideConnections.length > 0 && sideConnections.every(tag => tag === 'BUTTON'),
        `Map connection controls are not native buttons (${sideConnections.join(',')})`);

      await Promise.all([
        page.waitForNavigation({ waitUntil: 'load' }),
        page.reload({ waitUntil: 'load' }),
      ]);
      await page.waitForTimeout(120);
      check(await page.getByLabel('Search map chats').inputValue() === 'Map Needle beyond the old cap', 'Map query did not survive reload');
      check(await page.locator('#mc-map-repo-filter').inputValue() === 'repo-b', 'Map repo filter did not survive reload');
      check(await page.getByRole('button', { name: /show all/i }).count() === 1, 'Map focused-chat context did not survive reload');
    });

    await block('typing pauses disruptive refresh, then idle focus refreshes', async () => {
      const typingPage = await browser.newPage({ viewport: { width: 1200, height: 800 } });
      typingPage.setDefaultTimeout(5000);
      try {
        await typingPage.addInitScript(() => {
          const realNow = Date.now.bind(Date);
          Date.now = () => Number(sessionStorage.getItem('mc-browser-now') || realNow());
        });
        await typingPage.goto(url('chats'), { waitUntil: 'load' });
        const input = typingPage.getByLabel('Search chats and open work');
        await input.fill('typing in progress');
        await input.focus();
        await typingPage.evaluate(() => {
          window.__mcPageMarker = 'still-here';
          sessionStorage.setItem('mc-browser-now', String(Date.now() + 120000));
          window.MC_refreshGate.noteInteraction();
          window.dispatchEvent(new Event('focus'));
        });
        await typingPage.waitForTimeout(40);
        check(await typingPage.evaluate(() => window.__mcPageMarker) === 'still-here',
          'stale-page refresh reloaded while the operator was typing');
        const idleGate = await typingPage.evaluate(() => {
          sessionStorage.setItem('mc-browser-now', String(Date.now() + 16000));
          return {
            active: window.MC_refreshGate.interactionActive(),
            focused: document.activeElement && document.activeElement.id,
          };
        });
        check(idleGate.active === false && idleGate.focused === 'mc-chat-search',
          `idle focused search remained an active interaction (${JSON.stringify(idleGate)})`);
        await Promise.all([
          typingPage.waitForNavigation({ waitUntil: 'load' }),
          typingPage.evaluate(() => window.MC_refreshGate.request()),
        ]);
        check(await typingPage.evaluate(() => window.__mcPageMarker) == null,
          'focused but idle search suppressed the deferred refresh indefinitely');
      } finally { await typingPage.close(); }
    });

    await block('Git and Automation disclosure semantics', async () => {
      await page.goto(url('git'), { waitUntil: 'load' });
      const gitDisclosure = page.locator('.mc-collapse').first();
      check(await gitDisclosure.evaluate(el => el.tagName) === 'BUTTON', 'Git disclosure is not a native button');
      check(await gitDisclosure.getAttribute('aria-expanded') === 'false', 'Git disclosure lacks collapsed aria-expanded state');
      await gitDisclosure.click();
      check(await gitDisclosure.getAttribute('aria-expanded') === 'true', 'Git disclosure does not expose expanded state');
      await Promise.all([page.waitForNavigation({ waitUntil: 'load' }), page.reload({ waitUntil: 'load' })]);
      check(await page.locator('.mc-collapse').first().getAttribute('aria-expanded') === 'true', 'Git disclosure state did not survive reload');

      await page.goto(url('automation'), { waitUntil: 'load' });
      const automationDisclosure = page.locator('.mc-collapse').first();
      check(await automationDisclosure.evaluate(el => el.tagName) === 'BUTTON', 'Automation disclosure is not a native button');
      check(await automationDisclosure.getAttribute('aria-controls') != null, 'Automation disclosure lacks aria-controls');
      await automationDisclosure.click();
      check(await automationDisclosure.getAttribute('aria-expanded') === 'true', 'Automation disclosure does not expose expanded state');
      await Promise.all([page.waitForNavigation({ waitUntil: 'load' }), page.reload({ waitUntil: 'load' })]);
      check(await page.locator('.mc-collapse').first().getAttribute('aria-expanded') === 'true', 'Automation disclosure state did not survive reload');
    });
  } finally {
    await page.close();
  }
  if (failures.length) throw new Error(`operator UX regressions:\n- ${failures.join('\n- ')}`);
}

function demoState() {
  const out = execFileSync('/bin/bash', [DASH, 'demo'], {
    cwd: ROOT, env: { ...process.env, DASHBOARD_NO_OPEN: '1' }, encoding: 'utf8',
  });
  const match = out.match(/^demo state: (.+)$/m);
  if (!match) throw new Error(`could not locate demo state in: ${out}`);
  return match[1].trim();
}

function homePendingState(tmp, name) {
  const root = installedState(path.join(tmp, name));
  const now = Math.floor(Date.now() / 1000);
  for (const feed of ['usage', 'headroom', 'git', 'chats', 'automation', 'decisions', 'attention', 'brief']) {
    const feedPath = path.join(root, 'data', `${feed}.json`);
    const envelope = JSON.parse(fs.readFileSync(feedPath, 'utf8'));
    envelope.generated_epoch = now;
    envelope.generated_at = new Date(now * 1000).toISOString();
    if (feed === 'usage') envelope.data.providers = [];
    if (feed === 'git') envelope.data.repos = [];
    if (feed === 'chats') {
      envelope.data.nodes = [];
      envelope.data.edges = [];
      envelope.data.loose_ends = [];
      envelope.data.stale_providers = [];
      envelope.data.counts = {};
    }
    if (feed === 'automation') envelope.data.jobs = [];
    writeStateFeed(root, feed, envelope);
  }
  const decisionsPath = path.join(root, 'data', 'decisions.json');
  const decisions = JSON.parse(fs.readFileSync(decisionsPath, 'utf8'));
  for (const row of decisions.data.pinned || []) {
    row.answer_pending = { choice: 1, choice_label: 'Recorded choice' };
  }
  fs.writeFileSync(decisionsPath, JSON.stringify(decisions) + '\n');
  fs.writeFileSync(path.join(root, 'data', 'decisions.js'),
    `window.MC=window.MC||{feeds:{},feedErrors:{}};window.MC.feeds.decisions=${JSON.stringify(decisions)};\n`);
  return root;
}

function staleBriefHomeState(root) {
  const attentionPath = path.join(root, 'data', 'attention.json');
  const attention = JSON.parse(fs.readFileSync(attentionPath, 'utf8'));
  attention.data.board = [];
  attention.data.top5 = [];
  attention.data.counts = { manual: 0, decision: 0, automation: 0, decisions_filtered_out: 0 };
  writeStateFeed(root, 'attention', attention);
  const briefPath = path.join(root, 'data', 'brief.json');
  const brief = JSON.parse(fs.readFileSync(briefPath, 'utf8'));
  brief.data.stale_required_inputs = ['git'];
  writeStateFeed(root, 'brief', brief);
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
  const attentionState = homePendingState(tmp, 'home-attention');
  const staleBriefState = homePendingState(tmp, 'home-stale-brief');
  staleBriefHomeState(staleBriefState);
  const operatorState = installedState(path.join(tmp, 'operator-audit'));
  writeStateFeed(operatorState, 'chats', syntheticLargeChats());
  const operatorGit = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'git.json'), 'utf8'));
  operatorGit.data.repos.push({ repo:'Synthetic clean repo', branch:'main', remote:'synced', dirty:false,
    ahead:0, behind:0, branches:[], decision_rows:[], branch_facts:[], worktrees:[] });
  writeStateFeed(operatorState, 'git', operatorGit);
  const operatorAutomation = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'automation.json'), 'utf8'));
  operatorAutomation.data.jobs[0].err_log_tail = 'synthetic failure detail';
  writeStateFeed(operatorState, 'automation', operatorAutomation);
  if (ARTIFACTS) fs.mkdirSync(ARTIFACTS, { recursive: true });
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  try {
    await operatorUxAudit(browser, operatorState);
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
          if (tab === 'map' && !mobile) {
            const mapLabel = await page.evaluate(() => {
              const container = document.querySelector('.mc-graph');
              const cy = container && container._cyreg && container._cyreg.cy;
              if (!cy) return { error: 'missing cytoscape' };
              let target = cy.nodes()[0];
              cy.nodes().forEach((n) => {
                const label = String(n.data('label') || '');
                if (label.toLowerCase().indexOf('hermes') >= 0) target = n;
              });
              target.select();
              const zoom = cy.zoom();
              const modelFont = parseFloat(target.style('font-size'));
              const renderedFont = modelFont * zoom;
              return { zoom, modelFont, renderedFont, label: target.data('label') };
            });
            assert(!mapLabel.error, `${mode}/desktop/map: ${mapLabel.error}`);
            assert(mapLabel.renderedFont > 0 && mapLabel.renderedFont <= 12,
              `${mode}/desktop/map: selected label renders at ${mapLabel.renderedFont}px (zoom ${mapLabel.zoom})`);
          }
          if (tab === 'git' && mobile) {
            const gitCards = await page.evaluate(() => Array.from(
              document.querySelectorAll('.mc-git-mobile-table')).map(table => ({
                client: table.clientWidth,
                scroll: table.scrollWidth,
                rows: table.querySelectorAll('tr:not(:first-child)').length,
                labeled: Array.from(table.querySelectorAll('tr:not(:first-child) td'))
                  .every(cell => cell.getAttribute('data-label')),
              })));
            assert(gitCards.length >= 4,
              `${mode}/mobile/git: expected all Git detail tables (found ${gitCards.length})`);
            assert(gitCards.every(table => table.scroll <= table.client && table.rows > 0 && table.labeled),
              `${mode}/mobile/git: critical fields require horizontal scrolling or lack labels`);
          }
          if (tab === 'git' && !mobile) {
            const lifecycle = await page.evaluate(() => {
              const wrap = document.querySelector('.mc-table-scroll');
              const table = document.querySelector('.mc-git-lifecycle-table');
              if (!wrap || !table) return { error: 'missing lifecycle table wrapper' };
              const merge = Array.from(table.querySelectorAll('td[data-label="Merge"]'))
                .map((cell) => cell.textContent.trim());
              return {
                wrapClient: wrap.clientWidth,
                wrapScroll: wrap.scrollWidth,
                tableDisplay: getComputedStyle(table).display,
                merge,
              };
            });
            assert(!lifecycle.error, `${mode}/desktop/git: ${lifecycle.error}`);
            assert(lifecycle.tableDisplay === 'table',
              `${mode}/desktop/git: lifecycle table display is ${lifecycle.tableDisplay}`);
            assert(lifecycle.wrapScroll > lifecycle.wrapClient,
              `${mode}/desktop/git: lifecycle table should scroll (${lifecycle.wrapScroll} > ${lifecycle.wrapClient})`);
            assert(lifecycle.merge.some((text) => text === 'merge to main'),
              `${mode}/desktop/git: merge condition text missing from lifecycle table`);
          }
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
    const attentionPage = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    await attentionPage.goto(
      `${pathToFileURL(path.join(attentionState, 'index.html')).href}#home`,
      { waitUntil: 'load' });
    const attentionTitle = await attentionPage.locator('.mc-glance-title').innerText();
    assert(attentionTitle === 'Needs you',
      `home/manual attention: global heading did not require action (${attentionTitle})`);
    const attentionHeroNeeds = await attentionPage.locator('.mc-hero-stat').filter({
      has: attentionPage.getByText('Needs you', { exact: true }),
    }).locator('.mc-hero-stat-num').innerText();
    assert(attentionHeroNeeds === '1',
      `home/manual attention: guard rejected or hid the manual item (${attentionHeroNeeds})`);
    assert(await attentionPage.getByText('Review morning brief delivery').count() === 1,
      'home/manual attention: valid manual item is not visible');
    const expandHome = attentionPage.getByRole('button', { name: 'Show more details' });
    await expandHome.click();
    const pendingDecisionSection = attentionPage.locator('section.mc-attention').filter({
      has: attentionPage.getByRole('heading', { name: 'Awaiting owner consumption', exact: true }),
    });
    assert(await pendingDecisionSection.count() === 1,
      'home/manual attention: answered-pending decision section is not visible');
    assert(await pendingDecisionSection.locator('.mc-opt, .mc-copy').count() === 0,
      'home/manual attention: answered-pending decisions expose action or copy buttons');
    await attentionPage.close();
    const briefAttentionPage = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    await briefAttentionPage.goto(
      `${pathToFileURL(path.join(staleBriefState, 'index.html')).href}#home`,
      { waitUntil: 'load' });
    const staleBriefAttention = await briefAttentionPage.evaluate(() => ({
      board: window.MC.feeds.attention.data.board.length,
      top5: window.MC.feeds.attention.data.top5.length,
    }));
    assert(staleBriefAttention.board === 0 && staleBriefAttention.top5 === 0,
      `home/stale brief: competing attention board is not empty (${JSON.stringify(staleBriefAttention)})`);
    assert(await briefAttentionPage.getByText('Review morning brief delivery').count() === 0,
      'home/stale brief: manual attention item is still visible');
    const briefAttentionTitle = await briefAttentionPage.locator('.mc-glance-title').innerText();
    assert(briefAttentionTitle === 'Needs you',
      `home/stale brief: global heading did not require action (${briefAttentionTitle})`);
    await briefAttentionPage.close();
  } finally {
    await browser.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  console.log(`dashboard-browser: ${passed} assertions passed`);
})().catch(err => { console.error(`FAIL: ${err.stack || err}`); process.exit(1); });
