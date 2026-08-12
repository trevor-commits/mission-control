# Menu-bar panel redesign (ER-134 surface)

Date: 2026-07-23
Actor: Hermes (desktop), session 20260723_185924_09ac6d
Request: Trevor — completely redesign the Mission Control menu-bar click surface
so the popover is clearer, easier to read, and better organized.

## What changed

### `dashboard/panel.html` (full visual redesign)
- Sticky header: MC mark, "Mission Control" title, live feed-freshness line
  ("Updated 2m ago" / "Feeds stale — updated X ago"), and an overall status pill
  (All clear / N need you / N red jobs).
- Stat strip: Needs-you count, jobs healthy ratio (red/warning wording when not
  healthy), feed age.
- Item cards: kind badge (Decision / Manual / Automation…), severity chip
  (High/Med/Low dot — severity 1|2|3 per `dashboard attention add`), question
  clamped to 4 lines with full text on hover, why clamped to 2 lines.
- Decision options: full-width rows with number keycaps; the recommended option
  is accent-highlighted with a "Suggested" tag; one-click answer via the
  `mcDecide` bridge is unchanged (clipboard fallback unchanged).
- Footer toolbar: Refresh, theme toggle, "Open Mission Control →" (`mcOpenFull`
  bridge unchanged).
- Empty state: green check ring, "All clear — nothing is waiting on you."

### `scripts/mc-panel.swift`
- Popover and webview resized 380x460 → 400x560.
- Menu-bar title is now live: `MC` (label color) when clear, red `MC N` when N
  items need attention, orange `MC !` when only red automation jobs. Tooltip
  carries the same summary plus feed age. Source: the already-written local
  feeds `attention.json` / `decisions.json` / `automation.json` (read-only,
  same 120s refresh cadence as the panel reload).
- Hover preview: hovering the status item ~0.45s opens the popover WITHOUT
  `NSApp.activate` (no focus steal); leaving the icon cancels the pending open.
  Click behavior is unchanged (opens + activates).

## Contracts preserved (test-enforced)
- `parseOptions(text)` extraction shape and behavior; `feeds()` adjacency.
- `mcDecide` / `mcOpenFull` bridges; `data/attention.js` and sibling feed tags;
  `slice(0, 5)` top-5 cap; `attentionFresh` stale fallback → `renderFromDecisions`;
  no `innerHTML`; light default `#f4f5f7`; textContent-only rendering.
- Swift: TAL disabled, RunningBoard activity retained, async `terminationHandler`
  decide bridge (no `waitUntilExit`), exact decision-id regex, NSWorkspace open.

## Evidence
- `scripts/er134-usability.test.sh`: 60/60 PASS (incl. isolated swiftc build of
  the new mc-panel.swift and the parseOptions vm check).
- `scripts/dashboard.test.sh`: 67/67 PASS.
- `scripts/attention-lane.test.sh`: 5/5 PASS.
- `scripts/dashboard-render-smoke.js`: all 8 tabs render.
- `scripts/dashboard-browser.test.js`: 253 assertions passed.
- render_check.py (cloak) over the new panel.html staged with live
  `~/.mission-control/data` feeds, 400x700, light+dark: PASS, zero console
  errors; second pass with empty top5/pinned + all-green jobs (empty state):
  PASS, zero console errors.

## Known data-quality note (pre-existing, not from this change)
- One live decision carries `options: ["only"]` — an upstream collector
  extraction artifact from long prose text. The panel renders it as given (the
  old panel did the same). Fixing the collector's option extraction is a
  separate lane.
