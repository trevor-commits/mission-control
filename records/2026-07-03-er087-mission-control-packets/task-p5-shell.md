# Packet er087-p5-shell — the dashboard page (Trevor-visible; you are the route-up model)

Read the INVARIANTS block below + `docs/MISSION_CONTROL_PLAN.md` §Part B "Shell contract" + "Per-tab v1" + §Part C "Design rules (v1-binding)" + §Hardening renderer guards in your clone. ALL of those bind this packet — the design rules are evidence-based decisions, not suggestions. Plumbing exists: `scripts/dashboard`, fixtures for chats; you add the page + remaining fixtures.

## Goal
Author `dashboard/index.html` + synthetic `dashboard/fixtures/{usage,git,automation}.json` (chats.json exists). Make `bash scripts/dashboard.test.sh --require-shell` green.

## Build exactly
- One self-contained HTML file, three fenced sections in order: `/* === TOKENS === */` (ALL colors/fonts/radii/spacing as `:root` custom properties; dark theme near-black #16181d base, surface steps, Okabe-Ito status set green #009E73 / amber #E69F00 / red #D55E00 / blue #0072B2 desaturated ~15% for dark), `/* === LAYOUT CSS === */` (selectors ONLY on the `mc-*` class vocabulary: mc-strip, mc-card, mc-badge, mc-dot, mc-row, mc-cluster, mc-table, mc-drawer…), `// === RENDERERS ===` (pure functions `render.home/chats/git/usage/automation(feed, el)` reading `window.MC.feeds.*`, DOM via a tiny `h(tag, attrs, ...children)` helper; ALL feed text via `textContent`; the only computed style = bar width via CSS variable).
- Loads: `<script src="data/usage.js"></script>` etc. ×4 — relative paths, NOTHING external, no fonts/CDN/http(s).
- Home (default): global status strip (four segments, worst-state glyph+count, click = jump to tab; right end: page-loaded time, per-feed freshness dots, collector self-health from the automation feed's mission-control row); "Needs attention" merged exception list (max 7, stable-sorted by first-seen, each row: glyph, plain-words problem, one-line action, jump link); four fixed-anatomy summary cards (headline count, 1–2 secondary numbers, data age); "all green" state says so explicitly.
- Tabs (URL-hash routed; 60s `location.reload()` paused when `document.hidden`, plus reload on window focus if stale >60s):
  - Chats: flat rows (title, provider chip, repo, badges `worker`/`audit` + one-line parent, live badge <30 min, open-end count, copyable resume_cmd + view_cmd) with filters (repo dropdown, has-open-ends toggle, provider chips); clustered cards grouped by connected component (root big, members indented by edge type); sub-0.7 edges dashed + copyable unlink_cmd; open-ends >21 days collapse to a stale chip; "N new chats today" pulse on the summary card.
  - Git: summary strip; scan-unfinished-work table (one row per repo: branch colored by remote relationship — synced/ahead/behind/diverged/no-remote — symbols + right-hand ACTION VERB "needs push"/"needs commit"); clean repos collapse to one expandable "N repos clean ✓" line; separate watcher-flags list; groom strip (last run, done/fail counts, DECIDE list).
  - Usage: per-provider bars honoring the feed's confidence field (chip per row: official/estimated/stale), pace line ("62% used, 40% of window gone — ×1.55 hot") when window data present, live reset countdowns ticking client-side (negative → "reset passed — awaiting refresh"), credit rows, waste table, Cursor explicit "no data source" row.
  - Automation: uniform service cards from the automation feed (glyph+color state ✓/!/✕/○ never-ran/⏸ retired/offline-media/degraded; name, last-run age, expandable last error line); unregistered bucket listed.
- Renderer guards (all bind): refuse `schema !== 1` (banner + keep last-good), desaturate + banner when feed age > 2× cadence, negative age → "clock skew" amber, `font-variant-numeric: tabular-nums` on all numbers, low precision, CSS ellipsis truncation only, every panel shows its own data age ("3m ago", absolute on hover).
- Fixtures: synthetic, envelope-valid, exercising every state above (incl. a red job, an offline-media job, a stale feed, hostile emoji/apostrophe titles).

## Acceptance
`bash scripts/dashboard.test.sh --require-shell` exit 0. Browser rendering is verified by the governor after landing — do not claim it.


---

# Shared invariants (pasted by reference into every ER-087 packet — read FIRST)

- python3 stdlib only; any shell must be bash-3.2-compatible; no new dependencies; no network calls at test time.
- Tests: `scripts/<name>.test.sh` convention — mktemp fixtures only, one `PASS:`/`FAIL:` line per case, exit 0 only when all pass, whole suite < 90 seconds.
- YOU RUN WRITE-SANDBOXED: writes outside your clone + /tmp are DENIED. All code MUST honor env overrides for state + source roots, and tests MUST use them with mktemp dirs:
  - `CHAT_GRAPH_HOME` (default `~/.chat-graph`), `MISSION_CONTROL_HOME` (default `~/.mission-control`)
  - collector source roots: `CHAT_GRAPH_CROSS_AGENT_ROOT` (default `~/.cross-agent`), `CHAT_GRAPH_CLAUDE_ROOT` (default `~/.claude/projects`), `CHAT_GRAPH_CODEX_ROOT` (default `~/.codex/sessions`), `CHAT_GRAPH_SESSION_INDEX` (default `~/.codex/session_index.jsonl`), `CHAT_GRAPH_CHAT_SOURCE` (default `~/.codex/scripts/chat-source`)
  - dashboard feeder overrides: `DASHBOARD_CMD_USAGE`, `DASHBOARD_CMD_GIT`, `DASHBOARD_CMD_CHATS`, `DASHBOARD_CMD_AUTOMATION` (each replaces the real feeder command in tests); `AUTOMATION_STATUS_LAUNCHCTL` (replaces `launchctl` binary in tests)
  - Tests never read or write real `$HOME` paths.
- Security (hard, not compressible): state dirs created `chmod 700`; transcript-derived display text passes display-time redaction (mirror the redaction pattern in `scripts/search-transcripts` — grep it in your clone); dashboard renderers use `textContent` only, never `innerHTML`; committed fixtures are SYNTHETIC — no real session ids, no real transcript text, no secrets.
- Scope: do not create or modify ANY file outside your packet's scope glob. No scratch/notes/log files.
- Evidence to return in your final message: (1) full diff, (2) verbatim verify-command output incl. exit code, (3) claims list — done / deliberately untouched / uncertain. Missing evidence = automatic fail.
- Context: read `docs/MISSION_CONTROL_PLAN.md` in your clone — it is the authoritative design. Your packet section names the parts that bind you.
