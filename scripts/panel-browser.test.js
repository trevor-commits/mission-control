#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
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
const PANEL = path.join(ROOT, 'dashboard', 'panel.html');
const CHROME = process.env.MISSION_CONTROL_CHROME ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const NOW = Math.floor(Date.now() / 1000);
const SOURCE = fs.readFileSync(PANEL, 'utf8')
  .replace(/<script src="data\/[^"]+"><\/script>\s*/g, '');
let sequence = 0;
let passed = 0;
let failed = 0;

function envelope(name, data, extra = {}) {
  return Object.assign({
    schema: 1,
    feed: name,
    generated_epoch: NOW,
    cadence_s: name === 'headroom' ? 60 : 300,
    ok: true,
    error: null,
    data,
  }, extra);
}

function state(feeds, feedErrors = {}) {
  return { feeds, feedErrors };
}

function healthyCore() {
  return {
    attention: envelope('attention', { board: [], top5: [], counts: {
      manual: 0, decision: 0, automation: 0, decisions_filtered_out: 0,
    } }),
    decisions: envelope('decisions', { pinned: [], counts: { open: 0, structured_open: 0 } }),
    automation: envelope('automation', {
      jobs: [{ label: 'Collector', state: 'green' }], counts: { green: 1 }, exceptions: 0,
    }),
  };
}

function utcDate(offsetDays) {
  return new Date((NOW + offsetDays * 86400) * 1000).toISOString().slice(0, 10);
}

function quotaRow(extra = {}) {
  return Object.assign({
    id: 'provider:week', provider: 'provider', label: 'Provider', kind: 'quota',
    window_class: 'week', window_label: 'Weekly', remaining_pct: 50,
    active: true, band: 'green', confidence: 'live', health: 'ok', age_s: 0,
    fetched_epoch: NOW, burn_per_hour: 1, resets_epoch: NOW + 3600, source: 'synthetic', detail: {},
  }, extra);
}

function headroom(rows, lowest, extra = {}) {
  return envelope('headroom', { rows, summary: { lowest_quota: lowest } }, extra);
}

function safeJs(value) {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}

function luminance(color) {
  let values;
  const hex = String(color).trim().match(/^#([0-9a-f]{6})$/i);
  if (hex) values = [0, 2, 4].map(i => parseInt(hex[1].slice(i, i + 2), 16));
  else {
    const match = String(color).match(/[\d.]+/g);
    if (!match || match.length < 3) throw new Error(`cannot parse color ${color}`);
    values = match.slice(0, 3).map(Number);
  }
  const linear = values.map(value => value / 255)
    .map(value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4);
  return .2126 * linear[0] + .7152 * linear[1] + .0722 * linear[2];
}

function contrast(a, b) {
  const x = luminance(a);
  const y = luminance(b);
  return (Math.max(x, y) + .05) / (Math.min(x, y) + .05);
}

async function main() {
  assert(fs.existsSync(CHROME), `Chrome executable missing: ${CHROME}`);
  const { chromium } = loadPlaywright();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mc-panel-browser-'));
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });

  async function withPanel(mc, options, inspect) {
    const context = await browser.newContext({
      viewport: { width: 430, height: 900 },
      reducedMotion: options.reducedMotion || 'no-preference',
    });
    const page = await context.newPage();
    page.setDefaultTimeout(3000);
    const browserErrors = [];
    page.on('pageerror', error => browserErrors.push(`pageerror:${error.message}`));
    page.on('console', message => {
      if (message.type() === 'error') browserErrors.push(`console:${message.text()}`);
    });
    const bootstrap = `<script>${options.before || ''}\nwindow.MC=${safeJs(mc)};<\/script>`;
    const html = SOURCE.replace('<style>', `${bootstrap}\n<style>`);
    const file = path.join(tmp, `panel-${++sequence}.html`);
    fs.writeFileSync(file, html);
    try {
      await page.goto(pathToFileURL(file).href, { waitUntil: 'load' });
      await page.waitForTimeout(40);
      await inspect(page);
      assert.deepStrictEqual(browserErrors, [], browserErrors.join(' | '));
    } finally {
      await context.close();
    }
  }

  async function test(name, body) {
    try {
      await body();
      passed++;
      console.log(`ok - ${name}`);
    } catch (error) {
      failed++;
      console.error(`not ok - ${name}: ${error.message}`);
    }
  }

  try {
    await test('fresh complete Attention, Decisions, and Automation may report All clear', async () => {
      await withPanel(state(healthyCore()), {}, async page => {
        assert.strictEqual(await page.locator('#status-text').innerText(), 'All clear');
        assert.match(await page.locator('#list').innerText(), /All clear/);
      });
    });

    // Registry drift is routine on this Mac (57 untracked launchd jobs vs 17
    // tracked, 2026-08-19). Failing closed on it blanked every job state and hid
    // a live red job behind "Status incomplete".
    await test('registry drift still reports job health, including a red job', async () => {
      const good = healthyCore();
      const drifted = Object.assign({}, good, { automation: envelope('automation', {
        jobs: [{ label: 'Mobile Connect', state: 'red' }],
        counts: { red: 1 }, exceptions: 1,
        unregistered: ['untracked.one', 'untracked.two'],
      }) });
      await withPanel(state(drifted), {}, async page => {
        const pill = await page.locator('#status-pill').getAttribute('class');
        assert.ok(/warn|bad/.test(pill), `drift must not read clear, got ${pill}`);
        assert.match(await page.locator('#status-text').innerText(), /red job/i);
        assert.strictEqual(await page.locator('#stat-jobs').innerText(), '0/1');
        const list = await page.locator('#list').innerText();
        assert.ok(!/Status incomplete/.test(list), 'drift must not blank job health');
      });
    });

    // When something genuinely cannot be verified, say which feed and what to run.
    await test('unverifiable status names the failing feed and the repair command', async () => {
      const good = healthyCore();
      const errors = { decisions: { ok: false, error: 'decision queue timed out after 30s', generated_epoch: NOW } };
      await withPanel(state(good, errors), {}, async page => {
        const list = await page.locator('#list').innerText();
        assert.match(list, /Status incomplete/);
        assert.match(list, /decisions/);
        assert.match(list, /dashboard collect decisions --force/);
      });
    });

    await test('missing, malformed, stale, error, and partial core feeds fail closed', async () => {
      const good = healthyCore();
      const cases = [
        ['missing attention', { decisions: good.decisions, automation: good.automation }, {}],
        ['malformed attention', Object.assign({}, good, { attention: envelope('attention', { board: [], top5: [] }) }), {}],
        ['torn attention counts', Object.assign({}, good, { attention: envelope('attention', {
          board: [], top5: [], counts: { manual: 1, decision: 0, automation: 0, decisions_filtered_out: 0 },
        }) }), {}],
        ['stale attention', Object.assign({}, good, { attention: envelope('attention', {
          board: [], top5: [], counts: { manual: 0, decision: 0, automation: 0, decisions_filtered_out: 0 },
        }, { generated_epoch: NOW - 901 }) }), {}],
        ['attention error sidecar', good, { attention: { ok: false, error: 'new failure', generated_epoch: NOW } }],
        ['missing decisions', { attention: good.attention, automation: good.automation }, {}],
        ['malformed decisions', Object.assign({}, good, { decisions: envelope('decisions', {}) }), {}],
        ['malformed decision entry', Object.assign({}, good, { decisions: envelope('decisions', {
          pinned: [null], counts: { open: 1, structured_open: 1 },
        }) }), {}],
        ['torn decision counts', Object.assign({}, good, { decisions: envelope('decisions', {
          pinned: [], counts: { open: 4, structured_open: 4 },
        }) }), {}],
        ['stale decisions', Object.assign({}, good, { decisions: envelope('decisions', {
          pinned: [], counts: { open: 0, structured_open: 0 },
        }, { generated_epoch: NOW - 901 }) }), {}],
        ['errored decisions', Object.assign({}, good, {
          decisions: envelope('decisions', null, { ok: false, error: 'collector failed' }),
        }), {}],
        ['decision error sidecar', good, { decisions: { ok: false, error: 'new failure', generated_epoch: NOW } }],
        ['partial decisions', Object.assign({}, good, { decisions: envelope('decisions', {
          pinned: [], counts: { open: 0, structured_open: 0 }, partial: true,
        }) }), {}],
        ['missing automation', { attention: good.attention, decisions: good.decisions }, {}],
        ['malformed automation', Object.assign({}, good, { automation: envelope('automation', {}) }), {}],
        ['malformed automation entry', Object.assign({}, good, { automation: envelope('automation', {
          jobs: [null], counts: {}, exceptions: 0,
        }) }), {}],
        ['torn automation counts', Object.assign({}, good, { automation: envelope('automation', {
          jobs: [{ label: 'Collector', state: 'green' }], counts: { green: 1, red: 1 }, exceptions: 1,
        }) }), {}],
        ['stale automation', Object.assign({}, good, { automation: envelope('automation', {
          jobs: [], counts: {}, exceptions: 0,
        }, { generated_epoch: NOW - 901 }) }), {}],
        ['errored automation', Object.assign({}, good, {
          automation: envelope('automation', null, { ok: false, error: 'collector failed' }),
        }), {}],
        ['automation error sidecar', good, { automation: { ok: false, error: 'new failure', generated_epoch: NOW } }],
        ['partial automation', Object.assign({}, good, { automation: envelope('automation', {
          jobs: [], counts: {}, exceptions: 0, partial: true,
        }) }), {}],
        ['unknown automation state', Object.assign({}, good, { automation: envelope('automation', {
          jobs: [{ label: 'Unknown job', state: 'mystery' }], counts: {}, exceptions: 0,
        }) }), {}],
        ['malformed unregistered value', Object.assign({}, good, { automation: envelope('automation', {
          jobs: [{ label: 'Collector', state: 'green' }], counts: { green: 1 }, exceptions: 0,
          unregistered: 'not-a-list',
        }) }), {}],
        ['automation launchctl parse gap', Object.assign({}, good, { automation: envelope('automation', {
          jobs: [{ label: 'Collector', state: 'green' }], counts: { green: 1 }, exceptions: 0,
          launchctl_note: 'launchctl output incomplete',
        }) }), {}],
      ];
      const falseClears = [];
      const runtimeFailures = [];
      for (const [name, feeds, errors] of cases) {
        try {
          await withPanel(state(feeds, errors), {}, async page => {
            const text = await page.locator('#status-text, #list').allInnerTexts();
            const pillClass = await page.locator('#status-pill').getAttribute('class');
            if (/All clear/i.test(text.join(' ')) || !/warn|bad/.test(pillClass || '')) falseClears.push(name);
          });
        } catch (error) {
          runtimeFailures.push(`${name}: ${error.message}`);
        }
      }
      assert.deepStrictEqual(falseClears, [], `${falseClears.join(', ')} reported clear`);
      assert.deepStrictEqual(runtimeFailures, [], runtimeFailures.join(' | '));
    });

    await test('fresh empty Attention cannot hide an open Decisions item', async () => {
      const decision = { id: 'decision:111111111111111111111111', title: 'Choose the rollout' };
      await withPanel(state({
        attention: healthyCore().attention,
        decisions: envelope('decisions', { pinned: [decision], counts: { open: 1, structured_open: 1 } }),
        automation: healthyCore().automation,
      }), {}, async page => {
        assert.notStrictEqual(await page.locator('#status-text').innerText(), 'All clear');
        assert.match(await page.locator('#list').innerText(), /Choose the rollout/);
      });
    });

    await test('answered-pending decisions remain read-only receipts and do not inflate Needs-you metrics', async () => {
      const receipt = {
        id: 'decision:333333333333333333333333',
        question: 'Choose the recorded rollout window',
        options: ['Proceed', 'Wait'],
        recommended: 1,
        answer_pending: { choice: 2 },
      };
      await withPanel(state({
        attention: healthyCore().attention,
        decisions: envelope('decisions', { pinned: [receipt], counts: { open: 1, structured_open: 1 } }),
        automation: healthyCore().automation,
      }), {}, async page => {
        assert.strictEqual(await page.locator('#title').textContent(), 'Awaiting owner consumption');
        assert.match(await page.locator('#list').innerText(), /Awaiting owner consumption · choice 2 recorded/);
        assert.strictEqual(await page.locator('#list button').count(), 0, 'pending receipt exposed an action');
        assert.strictEqual(await page.locator('#stat-needs').innerText(), '0');
        assert.strictEqual(await page.locator('#status-text').innerText(), 'Answers recorded');
      });
    });

    await test('default Active view keeps active and critical or exhausted providers visible', async () => {
      const active = quotaRow({ id: 'active:week', provider: 'active', label: 'Active Provider' });
      const exhausted = quotaRow({ id: 'empty:week', provider: 'empty', label: 'Exhausted Provider',
        active: false, remaining_pct: 0, band: 'red', burn_per_hour: 0 });
      const feeds = Object.assign(healthyCore(), {
        headroom: headroom([active, exhausted], {
          id: exhausted.id, label: exhausted.label, window_label: exhausted.window_label,
          remaining_pct: exhausted.remaining_pct, band: exhausted.band,
        }),
      });
      await withPanel(state(feeds), {}, async page => {
        const names = await page.locator('.hr-name').allInnerTexts();
        assert.deepStrictEqual(names, ['Exhausted Provider', 'Active Provider']);
        const exhaustedCd = await page.locator('.hr-card', { hasText: 'Exhausted Provider' }).locator('.hr-wcd').innerText();
        assert.match(exhaustedCd, /empty — resets in/, 'exhausted quota hides the waiting countdown');
        assert.ok(await page.locator('.hr-card', { hasText: 'Exhausted Provider' }).locator('.hr-wcd.wait').count() > 0,
          'exhausted countdown is not marked as waiting');
      });
    });

    await test('every usage window keeps a uniform reset line, including full, empty, and signed-out rows', async () => {
      const empty = quotaRow({ id: 'empty:week', provider: 'empty', label: 'Empty', remaining_pct: 0,
        band: 'red', active: false, burn_per_hour: 0, resets_epoch: NOW + 3663 });
      const full = quotaRow({ id: 'full:week', provider: 'full', label: 'Full', remaining_pct: 100,
        active: false, burn_per_hour: 0, resets_epoch: NOW + 7200 });
      const unusedFive = quotaRow({ id: 'glm:5h', provider: 'glm', label: 'GLM', window_class: '5h',
        window_label: '5-hour', remaining_pct: 100, active: false, burn_per_hour: 0, resets_epoch: null });
      const signed = quotaRow({ id: 'claude:week', provider: 'claude', label: 'Claude', health: 'auth',
        remaining_pct: null, used_pct: null, band: 'none', confidence: 'stale', active: false,
        burn_per_hour: null, resets_epoch: NOW + 86400 });
      const prepaid = quotaRow({ id: 'moonshot:balance', provider: 'moonshot', label: 'Moonshot',
        kind: 'balance', window_class: 'balance', window_label: 'API balance', remaining_pct: null,
        balance_usd: 12.42, band: 'cash', active: false, burn_per_hour: null, resets_epoch: null });
      const feeds = Object.assign(healthyCore(), {
        headroom: headroom([empty, full, unusedFive, signed, prepaid], {
          id: empty.id, label: empty.label, window_label: empty.window_label,
          remaining_pct: empty.remaining_pct, band: empty.band,
        }),
      });
      await withPanel(state(feeds), { before: 'try{localStorage.setItem("mc-hr-view","all")}catch(e){}' }, async page => {
        const cds = await page.locator('.hr-wcd').allInnerTexts();
        assert.ok(cds.some(t => /empty — resets in/.test(t)), `missing empty countdown: ${JSON.stringify(cds)}`);
        assert.ok(cds.some(t => /^resets in /.test(t) && !/empty —/.test(t)), `missing full countdown: ${JSON.stringify(cds)}`);
        assert.ok(cds.some(t => /full — 5-hour clock starts on next use/.test(t)), `missing unused 5h copy: ${JSON.stringify(cds)}`);
        assert.ok(cds.some(t => /prepaid — no scheduled reset/.test(t)), `missing prepaid copy: ${JSON.stringify(cds)}`);
        const claude = await page.locator('.hr-card', { hasText: 'Claude' }).innerText();
        assert.match(claude, /signed out/);
        assert.match(claude, /resets in /);
        assert.strictEqual(await page.locator('#hr-list .hr-wcd').count(), 5, 'a window dropped its reset line');
      });
    });

    await test('AI bottleneck stat refuses stale feed and non-live summary rows', async () => {
      const staleRow = quotaRow({ id: 'stale:week', provider: 'stale', label: 'Stale Low',
        remaining_pct: 1, confidence: 'stale', active: false });
      const liveRow = quotaRow({ id: 'live:week', provider: 'live', label: 'Live High', remaining_pct: 60 });
      const summary = { id: staleRow.id, label: staleRow.label, window_label: staleRow.window_label,
        remaining_pct: staleRow.remaining_pct, band: staleRow.band };
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([staleRow, liveRow], summary),
      })), {}, async page => {
        assert.strictEqual(await page.locator('#stat-ai').innerText(), '60%', 'live sibling was blanked by a stale summary');
      });
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([liveRow], { id: liveRow.id, label: liveRow.label,
          window_label: liveRow.window_label, remaining_pct: liveRow.remaining_pct, band: liveRow.band },
          { generated_epoch: NOW - 301 }),
      })), {}, async page => {
        assert.strictEqual(await page.locator('#stat-ai').innerText(), '–', 'stale feed summary reached the stat');
      });
      const actualLow = quotaRow({ id: 'actual:week', provider: 'actual', label: 'Actual Low', remaining_pct: 10 });
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([actualLow, liveRow], { id: liveRow.id, label: liveRow.label,
          window_label: liveRow.window_label, remaining_pct: liveRow.remaining_pct, band: liveRow.band }),
      })), {}, async page => {
        assert.strictEqual(await page.locator('#stat-ai').innerText(), '10%', 'actual lowest live row did not reach the stat');
      });
    });

    await test('AI bottleneck stat requires one fresh fetched row and bounded percentages', async () => {
      function lowFor(row) {
        return { id: row.id, label: row.label, window_label: row.window_label,
          remaining_pct: row.remaining_pct, band: row.band };
      }
      const valid = quotaRow({ id: 'valid:week', remaining_pct: 40 });
      const duplicate = quotaRow({ id: valid.id, provider: 'duplicate', label: 'Duplicate', remaining_pct: 40 });
      const missingFetch = quotaRow({ id: 'missing:week', remaining_pct: 30, fetched_epoch: null });
      const staleFetch = quotaRow({ id: 'old:week', remaining_pct: 20, fetched_epoch: NOW - 301 });
      const invalidPct = quotaRow({ id: 'invalid:week', remaining_pct: -1 });
      const cases = [
        [[valid], lowFor(valid)],
        [[valid, duplicate], lowFor(valid)],
        [[missingFetch], lowFor(missingFetch)],
        [[staleFetch], lowFor(staleFetch)],
        [[invalidPct], lowFor(invalidPct)],
      ];
      const values = [];
      for (const [rows, low] of cases) {
        await withPanel(state(Object.assign(healthyCore(), {
          headroom: headroom(rows, low),
        })), {}, async page => { values.push(await page.locator('#stat-ai').innerText()); });
      }
      assert.deepStrictEqual(values, ['40%', '40%', '–', '–', '–']);
    });

    await test('malformed headroom update clears the prior stat without a runtime error', async () => {
      const valid = quotaRow({ id: 'valid:week', remaining_pct: 10, band: 'red' });
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([valid], { id: valid.id, label: valid.label,
          window_label: valid.window_label, remaining_pct: valid.remaining_pct, band: valid.band }),
      })), {}, async page => {
        assert.strictEqual(await page.locator('#stat-ai').innerText(), '10%');
        await page.evaluate(() => window.MC_updateHeadroom({
          schema: 1, feed: 'headroom', generated_epoch: Math.floor(Date.now() / 1000), cadence_s: 60,
          ok: true, error: null, data: { rows: [null], summary: { lowest_quota: null } },
        }));
        assert.strictEqual(await page.locator('#stat-ai').innerText(), '–');
        assert.match(await page.locator('#hr-list').innerText(), /collector not running/i);
      });
    });

    // Trevor's landing view: two labelled bars with live countdowns, everything
    // else behind the caret. Before this the panel opened on four stat tiles that
    // read "-" whenever a feeder hiccuped.
    await test('panel opens on the tightest 5-hour and weekly windows with countdowns', async () => {
      const rows = [
        quotaRow({ id: 'a:5h', provider: 'a', label: 'Alpha', window_class: '5h',
          window_label: '5-hour', remaining_pct: 62, resets_epoch: NOW + 5400 }),
        quotaRow({ id: 'a:week', provider: 'a', label: 'Alpha', window_class: 'week',
          window_label: 'Weekly', remaining_pct: 71, resets_epoch: NOW + 90000 }),
        // Tighter weekly on another provider: the brief must prefer this one.
        quotaRow({ id: 'b:week', provider: 'b', label: 'Beta', window_class: 'week',
          window_label: 'Weekly', remaining_pct: 4, band: 'red', resets_epoch: NOW + 7200 }),
      ];
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom(rows, { id: 'b:week', label: 'Beta', window_label: 'Weekly',
          remaining_pct: 4, band: 'red' }),
      })), {}, async page => {
        const brief = page.locator('#hr-brief');
        assert.strictEqual(await brief.locator('.hr-brow').count(), 2, 'expected exactly two lines');
        const text = await brief.innerText();
        assert.match(text, /Alpha · 5-hour/, 'five-hour line missing');
        assert.match(text, /Beta · Weekly/, 'weekly line must show the tightest provider');
        assert.ok(!/Alpha · Weekly/.test(text), 'a looser weekly window must not win');
        // Every brief line carries a live reset countdown, same as the detail list.
        assert.strictEqual(await brief.locator('.hr-wcd').count(), 2);
        for (const cd of await brief.locator('.hr-wcd').allInnerTexts()) {
          assert.match(cd, /resets in /, `brief line lost its countdown: ${cd}`);
        }
        // Providers and jobs are never hidden behind a caret. What collapses is
        // the per-provider specifics, one card at a time.
        assert.strictEqual(await page.locator('#hr-toggle').count(), 0, 'outer caret must not exist');
        assert.ok(await page.locator('#hr-list').isVisible(), 'provider list must always be visible');
        assert.ok(await page.locator('#stats').isVisible(), 'job stats must always be visible');
        assert.ok(await page.locator('#hr-list .hr-card').count() >= 1, 'provider list is empty');
      });
    });

    // A repair pass that silently died must not look like one that ran clean.
    await test('self-check receipt is shown, and its absence is flagged', async () => {
      const withJobs = extra => envelope('automation', Object.assign({
        jobs: [{ label: 'Collector', state: 'green' }], counts: { green: 1 }, exceptions: 0,
      }, extra));

      await withPanel(state(Object.assign(healthyCore(), {
        automation: withJobs({ self_check: { last_run_epoch: NOW - 7200, planned: 2, repaired: 2, dry_run: false } }),
      })), {}, async page => {
        const line = await page.locator('#hr-selfcheck').innerText();
        assert.match(line, /Self-check 2h ago/);
        assert.match(line, /repaired 2/);
        assert.ok(!/warn/.test(await page.locator('#hr-selfcheck').getAttribute('class')));
      });

      // Never run at all.
      await withPanel(state(Object.assign(healthyCore(), { automation: withJobs({}) })), {}, async page => {
        assert.match(await page.locator('#hr-selfcheck').innerText(), /never run/i);
        assert.match(await page.locator('#hr-selfcheck').getAttribute('class'), /warn/);
      });

      // Ran, then stopped running -- the failure mode that went unnoticed before.
      await withPanel(state(Object.assign(healthyCore(), {
        automation: withJobs({ self_check: { last_run_epoch: NOW - 4 * 86400, planned: 0, repaired: 0, dry_run: false } }),
      })), {}, async page => {
        assert.match(await page.locator('#hr-selfcheck').innerText(), /Self-check 4d ago/);
        assert.match(await page.locator('#hr-selfcheck').getAttribute('class'), /warn/);
      });
    });

    await test('brief states plainly when no live window exists', async () => {
      const dark = quotaRow({ id: 'a:week', health: 'auth', confidence: 'stale',
        remaining_pct: null, age_s: 650360 });
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([dark], null),
      })), {}, async page => {
        assert.match(await page.locator('#hr-brief').innerText(), /No live 5-hour or weekly window/);
      });
    });

    await test('provider disclosure is a native button with wired expanded state', async () => {
      const row = quotaRow({ detail: { plan: 'Synthetic Pro' }, note: 'Synthetic details' });
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([row], { id: row.id, label: row.label, window_label: row.window_label,
          remaining_pct: row.remaining_pct, band: row.band }),
      })), {}, async page => {
        const disclosure = page.locator('.hr-disclosure').first();
        assert.strictEqual(await disclosure.evaluate(node => node.tagName), 'BUTTON');
        assert.strictEqual(await disclosure.getAttribute('aria-expanded'), 'false');
        const controls = await disclosure.getAttribute('aria-controls');
        assert(controls && await page.locator(`#${controls}`).count() === 1, 'aria-controls target is missing');
        await disclosure.press('Enter');
        assert.strictEqual(await disclosure.getAttribute('aria-expanded'), 'true');
        assert.match(await page.locator(`#${controls}`).innerText(), /Synthetic Pro/);
      });
    });

    // The panel re-renders every 3s and reloads every 120s. Without persistence an
    // opened provider detail slams shut almost immediately, which makes the only
    // remaining collapse unusable.
    await test('an opened provider detail survives a re-render', async () => {
      const row = quotaRow({ detail: { plan: 'Synthetic Pro' } });
      const feed = headroom([row], { id: row.id, label: row.label, window_label: row.window_label,
        remaining_pct: row.remaining_pct, band: row.band });
      await withPanel(state(Object.assign(healthyCore(), { headroom: feed })), {}, async page => {
        const disclosure = page.locator('.hr-disclosure').first();
        assert.strictEqual(await disclosure.getAttribute('aria-expanded'), 'false');
        await disclosure.click();
        assert.strictEqual(await disclosure.getAttribute('aria-expanded'), 'true');

        // Exactly what the 3s timer does: push the feed again and re-render.
        await page.evaluate(f => window.MC_updateHeadroom(f), feed);
        assert.strictEqual(await page.locator('.hr-disclosure').first().getAttribute('aria-expanded'),
          'true', 'detail closed itself on re-render');
        assert.match(await page.locator('#hr-list').innerText(), /Synthetic Pro/);

        // Closing must stick too, not just opening.
        await page.locator('.hr-disclosure').first().click();
        await page.evaluate(f => window.MC_updateHeadroom(f), feed);
        assert.strictEqual(await page.locator('.hr-disclosure').first().getAttribute('aria-expanded'),
          'false', 'detail reopened itself on re-render');
      });
    });

    await test('provider detail summarizes only validated seven-day read activity', async () => {
      const row = quotaRow({ id: 'x-api:month', provider: 'x_api', label: 'X API',
        window_class: 'month', window_label: 'Monthly reads', value_label: '1,234 reads',
        detail: { project_cap: 50000, daily_reads: [
          { date: utcDate(-6), reads: 12 },
          { date: utcDate(-1), reads: 34 },
          { date: utcDate(-1), reads: 35 },
          { date: utcDate(-40), reads: 9000 },
          { date: '2026-02-30', reads: 9000 },
          { date: 'not-a-date', reads: 9000 },
          { date: '2026-08-06', reads: -1 },
          { date: '2026-08-05', reads: 2.5 },
          { date: '2026-08-04', reads: '10' },
          null,
        ] } });
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([row], { id: row.id, label: row.label, window_label: row.window_label,
          remaining_pct: row.remaining_pct, band: row.band }),
      })), {}, async page => {
        const disclosure = page.locator('.hr-disclosure').first();
        await disclosure.press('Enter');
        const controls = await disclosure.getAttribute('aria-controls');
        const detail = await page.locator(`#${controls}`).innerText();
        assert.match(detail, /Monthly cap\s+50,000 reads/);
        assert.match(detail, new RegExp(`7-day activity\\s+47 reads total · latest ${utcDate(-1)}: 35`));
        assert.doesNotMatch(detail, /9,000/);
      });
    });

    await test('headroom tabs and icon-only controls have programmatic labels', async () => {
      const row = quotaRow();
      await withPanel(state(Object.assign(healthyCore(), {
        headroom: headroom([row], { id: row.id, label: row.label, window_label: row.window_label,
          remaining_pct: row.remaining_pct, band: row.band }),
      })), {}, async page => {
        const tablist = page.locator('#hr-tabs');
        assert.strictEqual(await tablist.getAttribute('role'), 'tablist');
        assert(await tablist.getAttribute('aria-label'), 'tablist has no accessible label');
        const tabs = page.locator('.hr-tab');
        assert.strictEqual(await tabs.count(), 6);
        for (let i = 0; i < await tabs.count(); i++) {
          const tab = tabs.nth(i);
          assert.strictEqual(await tab.getAttribute('role'), 'tab');
          assert(await tab.getAttribute('aria-label'), `tab ${i} has no accessible label`);
          assert.strictEqual(await tab.getAttribute('aria-controls'), 'hr-list');
        }
        for (const selector of ['#hr-motion', '#hr-pin', '#theme']) {
          assert(await page.locator(selector).getAttribute('aria-label'), `${selector} has no accessible label`);
        }
        await tabs.first().focus();
        await tabs.first().press('ArrowRight');
        assert.strictEqual(await page.locator('.hr-tab[aria-selected="true"]').innerText(), 'Low');
        assert.strictEqual(await page.evaluate(() => document.activeElement && document.activeElement.textContent), 'Low');
      });
    });

    await test('operational labels are at least 12px and color tokens meet WCAG AA', async () => {
      const active = quotaRow({ id: 'active:a', provider: 'active', label: 'Active Provider',
        provenance: 'synthetic', detail: { local_estimate: { tokens_used: 12, burn_tpm: 2 } } });
      const activeMonthly = quotaRow({ id: 'active:b', provider: 'active', label: 'Active Provider',
        window_label: 'Monthly', window_class: 'month', remaining_pct: 70 });
      const critical = quotaRow({ id: 'critical:b', provider: 'critical', label: 'Critical Provider',
        active: false, remaining_pct: 2, band: 'red', confidence: 'stale',
        window_label: 'Monthly', window_class: 'month' });
      const decision = { id: 'decision:111111111111111111111111', question: 'Choose a safe path',
        options: ['Proceed', 'Wait'], recommended: 1, provenance: 'synthetic', trust: 'structured' };
      const feeds = Object.assign(healthyCore(), {
        decisions: envelope('decisions', { pinned: [decision], counts: { open: 1, structured_open: 1 } }),
        automation: healthyCore().automation,
        headroom: headroom([active, activeMonthly, critical], { id: active.id, label: active.label,
          window_label: active.window_label, remaining_pct: active.remaining_pct, band: active.band }),
      });
      await withPanel(state(feeds), {}, async page => {
        const selectors = ['.mark', '.sub', '.pill', '.stat .lbl', '.section-head', '.badge', '.sev',
          '.opt .key', '.opt .tag', '.meta', '.hr-head .t', '.hr-tab', '.hr-wname', '.hr-wval',
          '.hr-wcd', '.hr-note-line', '.hr-name', '.hr-win', '.hr-flag', '.hr-val .unit',
      '.hr-bname', '.hr-bage', '.hr-selfcheck',
          '.hr-sub', '.hr-detail', '.tbtn'];
        const sizes = await page.evaluate(list => list.map(selector => {
          const node = document.querySelector(selector);
          return { selector, size: node ? parseFloat(getComputedStyle(node).fontSize) : null };
        }), selectors);
        for (const item of sizes) {
          assert.notStrictEqual(item.size, null, `${item.selector} fixture missing`);
          assert(item.size >= 12, `${item.selector} is ${item.size}px`);
        }
        for (const theme of ['light', 'dark']) {
          const tokens = await page.evaluate(value => {
            document.documentElement.setAttribute('data-theme', value);
            const style = getComputedStyle(document.documentElement);
            const get = name => style.getPropertyValue(name).trim();
            return { bg: get('--bg'), card: get('--card'), card2: get('--card-2'),
              accentSoft: get('--accent-soft'), greenSoft: get('--green-soft'), redSoft: get('--red-soft'), amberSoft: get('--amber-soft'),
              muted: get('--muted'), faint: get('--faint'), accent: get('--accent-fg'), green: get('--green'), red: get('--red'), amber: get('--amber'),
              hrGreen: get('--hr-green'), hrYellow: get('--hr-yellow'), hrOrange: get('--hr-orange'), hrRed: get('--hr-red'), hrCash: get('--hr-cash') };
          }, theme);
          const pairs = [
            ['muted/bg', tokens.muted, tokens.bg], ['muted/card', tokens.muted, tokens.card],
            ['muted/card2', tokens.muted, tokens.card2], ['faint/bg', tokens.faint, tokens.bg],
            ['faint/card', tokens.faint, tokens.card], ['green/soft', tokens.green, tokens.greenSoft],
            ['red/soft', tokens.red, tokens.redSoft], ['amber/soft', tokens.amber, tokens.amberSoft],
            ['accent/soft', tokens.accent, tokens.accentSoft], ['hr-green/card', tokens.hrGreen, tokens.card],
            ['hr-yellow/card', tokens.hrYellow, tokens.card], ['hr-orange/card', tokens.hrOrange, tokens.card],
            ['hr-red/card', tokens.hrRed, tokens.card], ['hr-cash/card', tokens.hrCash, tokens.card],
          ];
          for (const [name, fg, bg] of pairs) {
            assert(contrast(fg, bg) >= 4.5, `${theme} ${name} contrast ${contrast(fg, bg).toFixed(2)} < 4.5`);
          }
        }
      });
    });

    await test('reduced motion creates no canvas or RAF unless explicitly overridden', async () => {
      const row = quotaRow({ burn_per_hour: 3 });
      const feeds = state(Object.assign(healthyCore(), {
        headroom: headroom([row], { id: row.id, label: row.label, window_label: row.window_label,
          remaining_pct: row.remaining_pct, band: row.band }),
      }));
      const rafProbe = 'window.__rafCalls=0;var __nativeRaf=window.requestAnimationFrame.bind(window);window.requestAnimationFrame=function(cb){window.__rafCalls++;return __nativeRaf(cb);};';
      await withPanel(feeds, { reducedMotion: 'reduce', before: rafProbe }, async page => {
        assert.strictEqual(await page.locator('.hr-bricks').count(), 0, 'reduced motion created a canvas');
        assert.strictEqual(await page.evaluate(() => window.__rafCalls), 0, 'reduced motion scheduled RAF');
        assert.strictEqual(await page.locator('#hr-motion').getAttribute('aria-pressed'), 'false');
      });
      await withPanel(feeds, { reducedMotion: 'reduce',
        before: `${rafProbe}try{localStorage.setItem('mc-hr-motion','on')}catch(e){}` }, async page => {
        assert(await page.locator('.hr-bricks').count() > 0, 'explicit motion override did not create a canvas');
        assert(await page.evaluate(() => window.__rafCalls) > 0, 'explicit motion override did not schedule RAF');
        assert.strictEqual(await page.locator('#hr-motion').getAttribute('aria-pressed'), 'true');
      });
    });
  } finally {
    await browser.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }

  console.log(`panel-browser: ${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
}

main().catch(error => {
  console.error(`FAIL: ${error.stack || error}`);
  process.exit(1);
});
