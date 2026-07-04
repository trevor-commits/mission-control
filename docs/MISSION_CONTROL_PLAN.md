<!-- Canonical plan (ER-087). Updated 2026-07-02 second planning pass (Claude session 1ef98716-30bb-4530-80e0-6b2f3fa74f79): hardening addenda (live-data red-team), build choreography (9 audit-loop packets), evidence rules, assurance stack. Supersedes the first-pass copy; groom-feed row from audit commit 3cf0f76 retained. -->

# Chat-Graph + Mission-Control Dashboard — Plan

## Context

Trevor has many AI chats that relate to each other — a chat gets audited by one or more other chats, chats spawn worker chats, and some chats work the same issue without ever mentioning each other. Nothing today records those relationships: the transcript-index work (ER-074, in flight) makes all chats *searchable* but models no links; spawn/audit/mailbox provenance exists but is scattered across `~/.cross-agent/` files and title conventions. Separately, status is fragmented across ~8 surfaces (usage snapshot, repo-state watcher, nightly review, delegation digests, scan-unfinished-work, worktree sweep, Telegram bridge, Hermes CLI).

Goal: (1) a **chat-graph layer** that records how chats connect (auto-inferred + manual override) and what each still owes; (2) one **local web "mission control" dashboard** with four tabs — Chat map + open work, Git health, Usage/spend, Automation health — fed by the existing tools; (3) an **in-depth research pass** on how others build agent-ops dashboards, feeding the visual design.

Decisions locked with Trevor: local web app; auto + manual link capture; all four tabs in v1. Execution round (2026-07-02 second pass): audit EVERY build packet with the delegate-audit-loop + final cross-model review + fresh-eyes audit chat; FULL chat history on first scan (measured ~2–8 min); phases run straight through with a plain-words gate report at each boundary, stopping only on a two-strike blocker. Phase 0 (capture: register row, plan promoted to `docs/MISSION_CONTROL_PLAN.md`, research note, source cards) is already DONE and pushed.

## Existing assets (reuse, don't rebuild)

| Asset | Path | Role here |
|---|---|---|
| Transcript index (ER-074, in flight — **DB not yet on this host**, verified 2026-07-02; sandbox-only so far) | target `~/.transcript-index/index.db`, plan `docs/UNIFIED_TRANSCRIPT_SEARCH_PLAN.md` | Future session corpus + semantic layer; graph ATTACHes read-only, feature-detected; v1 has ZERO dependency on it |
| `chat-source` | `~/.codex/scripts/chat-source` | 6-provider id→title/repo/path resolver — node metadata ground truth |
| Spawn handshakes | `~/.cross-agent/handshake/<nonce>.txt` + `Spawned-by:`/`Spawned-child:` markers | `spawned` edges, proof-grade |
| Delegation loops | `~/.cross-agent/delegations/<id>/state.json` | governor→worker edges + rounds |
| Mailbox | `~/.cross-agent/mailbox/<to>/{inbox,read}/*.json` | `signaled` edges |
| Title conventions | `Audit: <name>`, `worker:<src> - <purpose>` (GR-120) | `audits`/`spawned` edge hints |
| Usage tools (ER-078) | `scripts/usage-snapshot` (JSON + `--html`), `scripts/usage-router`, `~/.usage-snapshot/history.jsonl` | Usage tab feed |
| Repo-state watcher | `~/.local/state/repo-state-watcher/` (dashboard.html + last-scan.tsv) | Git tab feed |
| Repo-groom (ER-086, built 2026-07-02 in a parallel lane) | `~/Coding Projects/repo-state-watcher/bin/repo-groom`; report `~/.local/state/repo-state-watcher/groom-last.txt`; timer `com.gillette.repo-groom` every 3h | Git tab feed: last groom run, DONE/FAIL actions, standing DECIDE list (stale unmerged awaiting Trevor). Dashboard DISPLAYS groom state, never re-implements cleanup (added by audit commit `3cf0f76`); groom's timer also gets a jobs.json row |
| `scan-unfinished-work --json` | `scripts/scan-unfinished-work` | Git tab + open-work feed |
| `worktree-sweep.sh` | `scripts/worktree-sweep.sh` | Git tab (worktree classes) |
| Nightly review | `scripts/nightly-review.sh` → `~/.claude/nightly-review/reports/*.md` | Open-work + automation feeds |
| Delegation audit (ER-082) | `~/.delegation-audit/digests/*.md`, verdicts.jsonl | Usage-waste + automation feeds |
| todo.md / ER register / implementation-packets | repo root + `records/` | Open-work feed |
| session-intake-closeout skill | `~/.claude/skills/session-intake-closeout/` | Closeout blocks → per-chat open ends |

## Security posture (inherited from ER-074 — not compressed)

Transcripts contain live secrets (2026-06-30 Hermes audit found real API keys in transcript tooling output). Therefore: all new state dirs (`~/.chat-graph/`, dashboard output dir) are `chmod 700`, never committed to git, never synced to cloud. Any transcript-derived text shown on the dashboard (titles, first prompts, open-end snippets) runs through the same display-time redaction layer `search-transcripts` uses. The dashboard is served/opened locally only — never exposed on the network (bind 127.0.0.1 if a server exists at all).

## Design

### Part A — chat-graph data layer

**One new python3-stdlib CLI `scripts/chat-graph` owning a separate SQLite DB `~/.chat-graph/graph.db`** (dir chmod 700 — caches titles/prompts/closeout text, inherits transcript sensitivity). NOT a table inside the transcript index: that DB is owned by an in-flight lane that treats it as rebuildable (`--rebuild`, archive-after-parity), and manual links are the one thing that can't be re-derived — they need a single-owner file. Cross-DB joins recovered at query time via read-only `ATTACH` of `~/.transcript-index/index.db`, feature-detected (table-existence checks), never written.

**Schema (5 tables):** `sessions` (provider+session_id PK, cached title/repo/first_prompt/last_activity via `chat-source`, closeout_seen, open_end_count) · `edges` (src, dst, `type` audits|spawned|continues|signaled|references|same_issue|governs|related_manual, `source` = which collector, confidence, evidence JSON, `status` active|suppressed, PK includes type+source) · `session_topics` (session ↔ ER/GR code — clusters come from here, not pairwise edges) · `open_ends` (kind, text, text_hash, resolved_at — auto-resolves when signal disappears) · `collector_state` (per-collector cursors). Two make-or-break semantics: **upsert never writes `status`** → `unlink` (sets suppressed, pre-inserts suppressed row if none) provably survives every re-ingest (mandatory self-test); `audits` direction = auditor→audited so "all auditors of X" = `WHERE dst=X`.

**Collectors (one `chat-graph ingest`):**

| Source read | Edge produced | Confidence | v1? |
|---|---|---|---|
| `~/.cross-agent/delegations/*/state.json` | spawned (governor→worker) | 1.0 verified / 0.8 | v1 |
| `~/.cross-agent/mailbox/<to>/{inbox,read}/*.json` | signaled (from→to) | 1.0 | v1 |
| Titles (`Audit: <name>`, `worker:<src> - …`) via chat-source + `~/.codex/session_index.jsonl` | audits / spawned | 0.7 unique / 0.5 ambiguous (noted) | v1 |
| ONE incremental transcript scan (Claude+Codex JSONL, mtime+size cursors, line prefilter) | `Spawned-by:`/`Spawned-child:` headers → spawned 1.0/0.95; foreign session-id mentions → references 0.9; ER/GR codes → `session_topics` rows (NO pairwise same_issue edges in v1 — topic groups give the same UI value with zero junk-link risk); `Session Closeout` blocks → open_ends. **Extraction from user+assistant text ONLY — never tool_result/system content** (live data: hook-reminder text inside Bash results would tag ~every session with the same code); per-session topic cap 8 | — | v1 |
| **Resume-fork detection**: sessions sharing the same first-message `uuid` (verified live: fork pairs exist; per-line sessionId is rewritten on fork so THAT detector fails) | continues (later→earlier) 1.0, source `resume-fork`; open_ends deduped across fork pairs | — | v1 (delivers `continues` without waiting for the transcript index) |
| Derivation: shared topic between a global-implementations session and other-repo session ≤14 days apart | governs 0.5 | — | **v2** (weakest heuristic — exactly the wrong-link generator that erodes trust; edge type stays reserved in schema) |
| Transcript-index ATTACH: shared turn-hash prefixes → continues; rare path overlap + semantic neighbors → same_issue | — | — | **v2** (gated on that lane's P1/P2 acceptance; zero new embedding infra — hard rule) |

Hermes/Cursor/Copilot/ChatGPT: nodes-only in v1 (via references + chat-source metadata); their text signals arrive in v2 through the transcript index. T7 absent → skip + `stale_providers` flag, never an error.

**CLI:** `ingest [--collector N] [--full] [--limit-files N]` · `link <idA> <idB> --type … [--note]` · `unlink` · `resolve <id> <open-end-hash>` (manual open-end close, same suppression semantics) · `show <id>` (card + neighbors by type + open ends; prints staleness warning, never auto-ingests) · `export --json` (atomic snapshot `~/.chat-graph/export/graph.json` wearing the SAME `{schema,feed,generated_epoch,…}` envelope as dashboard feeds — nodes+open_ends+`resume_cmd`+`view_cmd`, edges src/dst/type/source/confidence + `unlink_cmd` on sub-0.7 edges, topic groups, repo_annotations; runs incremental ingest first when cursors stale >30 min — the ONLY catch-up-on-query entry point, single race surface) · `stats` (incl. `signal_yield` + `scan_errors_24h`) · `doctor` (dirs+perms 700, chat-source symlink resolves + smoke `resolve`, `PRAGMA quick_check`, journal readable, last-ingest age, free disk >1 GB, scan-error count — one command answers "why is it broken") · `rebuild` (init schema + `ingest --full` + replay manual journal) · `--self-test`. Cut from v1: `clusters` subcommand (connected-components lives in `export`; gates can `jq` it). Bare ids resolved via `chat-source resolve`; chat-source failure = degraded (keep cached titles, set `stale_providers`), never fatal. Nightly tick = one ingest+export line in the nightly-review flow (the optional second launchd template is CUT — the 300s dashboard ticker covers intraday).

**Manual-actions journal (durability keystone):** every `link`/`unlink`/`resolve` appends one JSON line to `~/.chat-graph/journal/manual.jsonl` (fsync) BEFORE the DB write → `graph.db` becomes fully derivable; suppressions survive total DB loss via `rebuild`. Mandatory self-test: link + unlink → delete graph.db → rebuild → suppression still active. (Nightly DB-backup job rejected — the journal covers it with zero scheduled machinery.) Plus `meta` table with `schema_version`: forward-migration list on open; `db_version > code` → abort with plain message.

**Open ends v1 (only direct-attribution sources, nothing fuzzy):** (1) closeout `Handoff:` text with no outgoing continues/spawned edge; (2) session mentions an enforcement-register code whose row isn't verified yet. todo.md fuzzy matching + nightly-review loose ends deliberately deferred (wrong attribution worse than none); repo-level dirt attaches to repos in the export, not chats.

**Top risks:** transcript-index churn (→ separate DB, read-only feature-detected ATTACH); wrong title links (→ low confidence + visible source tag + unlink); scan cost growth (→ cursors, prefilter, per-run cap); topic clique explosion (→ ≤6-member cap, big topics = clusters); reader races (→ WAL + dashboard reads the atomic snapshot, never the DB).

### Part B — dashboard app ("mission control")

**Serving model — static shell + per-feed data files, no server.** One committed page `dashboard/index.html` installed to `~/.mission-control/index.html`, opened as `file://`. Browsers block `fetch()` of sibling JSON on `file://` (CORS/opaque origin), so each feed is written twice atomically: `data/<feed>.json` (canonical contract) + `data/<feed>.js` (`window.MC.feeds.<feed> = {...}`) loaded via `<script src>` — which `file://` allows. No iframes (file:// iframes are mutually opaque — old dashboards get consumed as data, not embedded). Page reloads every 60s (paused when window hidden, active tab kept via URL hash); countdowns tick client-side; per-feed freshness dot (green/amber/red from `generated_epoch` vs expected cadence) keeps liveness honest. Escape hatch: `dashboard open --serve` falls back to `python3 -m http.server` on 127.0.0.1 if a future browser tightens file:// scripts.

**One new launchd job** `com.gillettes.mission-control` (300s tick) runs `dashboard collect --due`; per-feed cadence/cost:

| Feed | Cadence | Source | Cost |
|---|---|---|---|
| automation | 300s | new `scripts/automation-status --json` | <1s |
| git | 900s | `scan-unfinished-work --json` + repo-state-watcher `last-scan.tsv` join | 10–40s, `timeout 120` |
| usage | 1800s | tail `~/.usage-snapshot/history.jsonl` if <40 min old (existing agent already refreshes it); fallback `usage-snapshot --no-ccusage` | ~0s |
| chats | 1800s | `chat-graph export --json` (Part A) | medium, `timeout 60`; absent tolerated → tab shows run command |

Collectors: mkdir-lock + `timeout` + write-to-tmp-then-`mv` (reload mid-write always sees complete old file); every feed fails independently; `schema: 1` envelope `{schema, feed, generated_at, generated_epoch, cadence_s, ok, error, data}` — renderer refuses mismatched schema, keeps last-good with a stale banner.

**Per-tab v1 (thin but real, plain default styling):**
- **Home (default view)**: global status strip + merged "Needs attention" exception list + four summary cards (per design rules in Part C). Reload also fires on window re-focus, not only the 60s timer.
- **Chat map + open work**: flat session rows with lineage **badges** (`worker`/`audit` + one-line parent context) and a copyable **resume command** per row, PLUS clustered cards (connected components) — root chat title big, members indented grouped by edge type (audits / workers / same-issue), provider chip, status glyph+color, flattened "owes" list; filters: repo, has-open-ends, provider. Tree tiering per Part C rule 7. No SVG graph in v1; v2 adds optional per-cluster hand-rolled deterministic SVG (root left, children fanned by edge type, big labels — NOT force-directed physics, no vendored d3; clusters are 2–10 nodes so ~80 lines of vanilla JS).
- **Git health**: summary strip (dirty / unpushed / stale / P1 flags) + per-repo expandable rows (branches, worktree counts from `git worktree list --porcelain`) rendered as TWO sections — scan-unfinished-work table + top watcher-flags list — plus a compact **groom strip** (last auto-cleanup run, actions done/failed, the "you decide" list from `~/.local/state/repo-state-watcher/groom-last.txt`; display-only). The watcher-TSV join is CUT from v1 (join key = repo names containing spaces/apostrophes — fragile matching for cosmetic merging); v2: join + `worktree-sweep.sh --json` classes.
- **Usage/spend**: provider bars with the source's confidence discipline (pct where honest, tokens where not), live reset countdowns, credit rows, waste table, Cursor shown as explicit "no data source" gap row.
- **Automation health**: registry-driven table. `dashboard/jobs.json` (committed) declares expected jobs (label, kind interval/calendar/keepalive, expected freshness, evidence paths, err log). Truth = `launchctl list` (not version-unstable `launchctl print`) + evidence file mtimes/success markers + err-log tail. States: green / yellow / red / `offline-media` (evidence on unmounted T7 — never red) / `unregistered` (launchd label present but not in registry — surfaces drift). Registry must include the `com.gillette.repo-state-watch.*` prefix variants.

**Shell contract (reskin-safe for Part C):** three fenced sections — CSS design TOKENS (`:root` custom properties) / LAYOUT CSS (stable class vocabulary `mc-card`, `mc-badge`, `mc-dot`, `mc-cluster`…) / RENDERERS (pure functions reading `window.MC.feeds.*`, DOM via tiny `h()` helper). All feed text via `textContent`, never `innerHTML` (chat titles/log lines are untrusted; the old usage dashboard already ate one escaping bug). Design phase edits tokens+CSS only. `dashboard demo` opens the shell against committed `dashboard/fixtures/*.json` — design iteration without live feeds; the chats fixture doubles as the shared contract test with Part A.

**CLI** `scripts/dashboard`: `open` (collect --due, open page, print freshness lines) / `refresh [feed]` / `status` (text table, nonzero exit if anything red — scriptable) / `collect [--due|--force]` / `install` (copy shell, sed plist from template, `launchctl bootstrap`, chmod 700) / `demo`.

**Home: global-implementations** (all feeders live here; plist template + `__HOME__`/`__REPO__` convention exists). New files: `scripts/dashboard`, `scripts/automation-status`, `dashboard/index.html`, `dashboard/jobs.json`, `dashboard/fixtures/*.json`, `launchd/com.gillettes.mission-control.plist.template`, `scripts/dashboard.test.sh`, `docs/runbooks/mission-control.md`. Runtime state `~/.mission-control/` chmod 700. Extraction path if it outgrows: collectors talk to feeders only via CLI JSON → `git subtree split` stays clean.

### Hardening addenda (live-data red-team, 2026-07-02 — measured, not guessed)

Ground truth that changed assumptions: corpus = 5,373 Claude + 687 Codex JSONL ≈ 6,060 files / 2.3 GB, largest file 19 MB → **full-history first scan runs in ~2–8 minutes at <100 MB memory** (stdlib line-iterate + substring prefilter). Live specimens found: `audit:` lowercase/no-space in a real mailbox message (title drift is already real); usage history rows carrying `confidence:"stale"` and `resets_in_min:-15`; a currently-dead job (`morning-health-brief` exit 1) as a Phase-3 test specimen; repo names with apostrophes/spaces; `chat-source` is a symlink into another repo; resume-fork duplicate session files (2 pairs in one project dir).

**First-scan design (locked: full history):** foreground with progress, NOT backgrounded (backgrounding a 5-minute pass is gold-plating). Enumerate first (paths+sizes, newest-first so freshest data lands earliest if interrupted); stderr progress every 2s (`[scan] 812/6060 · 34% · ETA 1m52s · errors 3`; `\r` on TTY, plain lines when piped). Per-line `JSONDecodeError` → counter + `~/.chat-graph/logs/scan-errors.log` (path:lineno); per-file `OSError/UnicodeDecodeError` → skip+log; **never abort the pass**; exit 1 only if >20% of files fail. One DB transaction per file (edges+topics+open_ends+cursor together) → Ctrl-C-safe, resumes where it stopped. Files >200 MB skipped+warned. Smoke first: `chat-graph ingest --full --limit-files 25 && chat-graph stats`. Structured collectors run before the scan so `stats` shows real edges within the first minute.

**Guards adopted into v1 (each lands as code guard + test fixture):**
- Title matching case-insensitive/space-tolerant (`^audit:\s*` etc.) — fixture with both observed forms.
- Untitled sessions: title → first user prompt (60 chars) → `(untitled) <id-prefix>`; export guarantees non-empty.
- Ingest concurrency: mkdir-lock `~/.chat-graph/ingest.lock` + `PRAGMA busy_timeout=5000`; locked → skip cleanly (test: two concurrent ingests).
- Feeder-shape drift: live-captured samples committed as `dashboard/fixtures/feeders/` (usage-snapshot.json, scan-unfinished-work.json, last-scan.tsv, delegation-state.json, mailbox-msg.json pinned to `schema:"cross-agent-mailbox/v1"`, session_index sample, claude/codex line samples); both test scripts run collectors against them so upstream drift fails loudly. Collectors wrap extraction in KeyError guards → envelope `ok:false`, renderer keeps last-good + stale banner.
- Scanner blindness made visible: `signal_yield` counter (>100 new files, 0 signals → warning) + `scan_errors_24h` surfaced as a row on the automation tab.
- `.js` transport quoting: `json.dumps(..., ensure_ascii=True)` (escapes emoji + U+2028/9; external script files immune to `</script>`); hostile fixture title (apostrophe + emoji + `</script>`) in the `.js`==`.json` roundtrip test.
- Renderer guards: negative reset countdown → "reset passed — awaiting refresh" + confidence chip per row; negative feed age → "clock skew" amber; CSS `text-overflow: ellipsis` only (never JS string slicing — surrogate pairs); needs-attention stable-sorted by first-seen; open-ends >21 days demote to a collapsed "stale" chip.
- Trust in auto-links: edges with confidence <0.7 render dashed + carry a copyable `chat-graph unlink A B` command — the fix is one paste away.
- jobs.json: `"retired": true` flag (grey, excluded from exceptions — the inverse rot case); `launchctl` parse failure → "degraded" state, never all-jobs-red; **self-monitoring rows** for the mission-control ticker itself + chat-graph ingest (marker file `~/.chat-graph/last-ingest`) — the dashboard reports its own pipeline's health.
- New-chat pulse: `sessions.first_seen_at` column → Home chat card shows "N new chats today"; "Live" badge on sessions active <30 min (honest version of "you are here"; literal foreground-chat marker rejected — file:// page has no reliable signal).
- Doctor absorbs: DB `quick_check`, disk-free, symlink health, journal readability; rebuild command documented in the runbook.
Deferred to v2: cursor-row GC (30 days), flap damping, `dashboard snooze` (v1 lays groundwork: stable `id` on every needs-attention row), Telegram ping on new red (alerting needs dedupe/spam control; nightly review already pushes). Rejected: `export --since` (no consumer), literal you-are-here marker, nightly DB backup job (journal supersedes).

### Part C — research findings (ran during planning) + design phase

**Prior-art sweep (done, 16 tools triaged).** Verdict: cross-provider chat-relationship mapping is **genuinely novel** — the crowded space (agent-sessions 677★, cass 938★, klovi, cc-session, AgentsView) is all flat session lists; best-in-class does within-provider badges only (agent-sessions v4: `workflow`/`side` badges) or Claude-only subagent trees (claude-view, Claude-Code-Agent-Monitor). Nothing reconstructs Claude→Codex→Cursor lineage. Our spawn/mailbox/title provenance makes it possible — no prior art to copy; proven rendering path = **badges → tree → optional graph**.

**Steal list adopted into the design:**
1. Lineage **badges on flat session rows** (`worker` / `audit` / `side` + one-line parent context) ship in v1 chat tab alongside clustered cards — 80% of relationship value, zero graph code (agent-sessions).
2. **One-click resume affordance** per session row: exact command (`claude --resume <id>`, Codex equivalent) — the killer action on any session list (agent-sessions). chat-source already resolves this; add `resume_cmd` to the export nodes.
3. **Master-detail**: list/tree left, selected chat's detail right (LangSmith/Langfuse convention); tree default, DAG behind a "show graph" click (Claude-Code-Agent-Monitor) — matches Part B's v2 SVG decision.
4. Git tab: **gita's color+symbol encoding** (branch colored by remote relationship: synced/ahead/behind/diverged/no-remote; symbols dirty/staged/untracked/stashed) + **mgitstatus action verbs** ("needs push", "needs commit") as each row's right-hand call to action.
5. Usage tab: **burn rate + "limit hits at HH:MM PT" projection** + window progress bars (Claude-Code-Usage-Monitor), every figure labeled official vs estimated (honesty labels); per-live-session context-fill gauge is v2 (claude-view).
6. Automation tab: **homepage's uniform service card** (icon, green/red dot, 2–4 live numbers per job).
7. **Failure-mode panel** (sniffly): errors ranked by category — v2, pairs with delegation-waste digests.
8. Open-work cards bind to **branch/worktree** (vibe-kanban's task↔worktree binding) — v2.

**Source cards to write at implementation (third-party capture rule):** jazzyalex/agent-sessions (MIT — per-provider local-store parsers), Dicklesworthstone/coding_agent_session_search (MIT — 22 provider parsers + normalization schema), tombelieber/claude-view (MIT — file-watcher→live-push architecture, subagent tree), hoangsonww/Claude-Code-Agent-Monitor (MIT — hook→SQLite→WebSocket pipeline), ryoppippi/ccusage (MIT — multi-source local cost engine; already partly used via ccusage). glance's fetch-on-load + per-widget cache TTL refresh model = pattern-mine only (AGPL).

**Design rules (evidence-based, v1-binding):**
1. **First screen = exceptions, not tabs.** Persistent global status strip (`Sessions ✓4 !1 · Git !6 · Usage amber · Autom ✕1`, click jumps to tab) + a top-left "Needs attention" list — the only red/amber items from all four tabs merged, ranked, max ~7 rows, each with plain-words problem + one-line action + jump link. Four fixed-anatomy summary cards below. Everything else one click away. (Grafana 5-second rule; Few single-screen.)
2. **No wall of green:** clean repos collapse to one line ("31 repos clean ✓", expandable); green rows carry no information. Red reserved for act-now (cap about to hit, job failed, auth broken); high-but-ok burn = amber with a suggestion. A color must carry an action.
3. **Never color alone:** Okabe-Ito colorblind-safe palette (green #009E73, amber #E69F00, red #D55E00, blue #0072B2, dark-tuned) + glyphs ✓ / ! / ✕ / ○(never-ran) / ⏸(paused) everywhere.
4. **Honest data age:** every panel shows its own "3m ago" (absolute on hover); stale panel's timestamp turns amber, stale data desaturates to grey + one banner — a frozen green dot is worse than no dashboard. Collector's own health dot in the strip.
5. **Tables beat charts** for heterogeneous status lists (git tab = sortable table, not 40 mini-charts); numbers use `font-variant-numeric: tabular-nums`, low precision ("$14.2", "128k tok"); **pace beats totals** — usage headline = "62% used, 40% of window gone — ×1.55 hot".
6. **Refresh matches data rate:** revalidate on window focus + per-tab cadence (automation/git ~60s, usage ~5min), nothing while hidden; no value jitter.
7. **Chat lineage = tree, never physics.** Evidence: node-link readability collapses past ~20 nodes (Ghoniem/Fekete/Castagliola); force layouts scramble positions every refresh. Tiering: ≤10 sessions → clustered cards with elbow connectors; 10–50 → indented file-explorer tree, finished subtrees collapsed to count chips; >50/history → flat sortable table with expand-on-demand lineage column. Optional node-link ONLY on click: deterministic layered left→right layout, hard cap ~25 visible, permanent middle-truncated labels.
8. **Empty/degraded states are first-class:** never-ran ≠ failed ≠ unreadable ≠ paused-on-purpose ≠ T7-unmounted; "all green" screen says so explicitly + shows what changed since last look.
v2 additions from same research: "since you last looked" diff-on-return highlights; 7-day burn sparklines on a shared scale; per-job last-20-runs success strips. Full rule set with sources goes in the durable research note (Phase 0).

## Build choreography (locked: audit every phase + final review; straight through with gate reports)

**Status 2026-07-03: all nine packets converged + landed on `er087-mission-control` (+ follow-up packet er087-p2c-title-match-schema `2e0fe3b`). Governor live-proof fixes: `723b3ea` (feeder defaults + exit-1 contract), `4494a04` (real feed shapes, size tiering, composite-key lineage). Assurance stack in progress.**

**First build action (before packet 1):** sync `docs/MISSION_CONTROL_PLAN.md` with this file — the repo copy currently predates this session's hardening + choreography sections (a cross-chat audit, commit `3cf0f76`, correctly flagged them missing from its transcript snapshot; they landed here after it). Same commit closes the auditor's todo.md open-end line and keeps its groom-feed row (already mirrored above). Register note: the parallel Hermes record that briefly claimed number 087 was renumbered 088 by that audit — no action.

Phase 0 (capture) is DONE — gl commits `8d5545c`+`adc0acf`, 3rd-party `105a2db`. Phases 1–5 run as **nine bounded worker packets, each through `scripts/delegate-audit-loop.sh`** (a cheaper model builds in an isolated clone; the governor re-runs the tests itself, never trusts the worker's word, loops to convergence, lands exactly one commit per packet on one isolated branch — never main, never pushed by the loop).

**Verified tooling facts this rests on (checked against the actual scripts):**
- The loop clones the worker's sandbox FROM `--work-dir` → one shared worktree chains packets (packet N+1's worker sees packet N's landed commit). ONE branch: `er087-mission-control` at `gi-worktrees/er087-mission-control` via `scripts/worktree-new.sh`.
- `--scope` is ONE case-glob (no `|` alternation — tested in bash 3.2 + 5.3) → multi-directory phases split into separate packets.
- Worker sandbox denies writes outside clone+tmp → **every test suite MUST honor `CHAT_GRAPH_HOME` / `MISSION_CONTROL_HOME` env overrides + mktemp** (a round failing with EPERM on `$HOME` = the worker violated this invariant; feed back as finding, NEVER disable the sandbox).
- **`delegate-sequence.sh` is NOT used**: its spec whitelist can't pass `--governor-id`/`--worker-timeout`/`--triaged-tier` — it would silently drop the parent-chat identity from every delegation record (breaking the final dogfood acceptance) and cap workers at 240s. Direct loop calls in order, stop at first nonzero exit — same stop-at-blocker semantics, lineage + timeouts intact. Follow-up task (after this build): extend the sequencer whitelist + test.
- Quota preflight BOTH providers before packet 1 AND again before packet 9: `bash scripts/usage-burst.sh preflight --provider claude && bash scripts/usage-burst.sh preflight --provider codex` — exit 0 required; 2/3 = stop, report, reschedule. Never fire blind.
- Emergency brake: `touch ~/.cross-agent/HALT` (loop exits 2 before next round). Resume = remove flag, run only remaining packets with fresh `--id`s; converged packets are landed commits, never re-run.

**The nine packets** (task files live at `~/.cross-agent/delegations/er087-specs/`, outside the work-dir; every task file carries the shared invariants block: python3 stdlib only, bash-3.2-safe, tests <90s honoring env overrides, chmod-700 state dirs, redaction via the `search-transcripts` layer, `textContent` only, full diff+verbatim verify output+claims list returned — missing evidence = automatic fail):

| # | SPEC_ID | scope | worker → escalation (2 strikes = up ONE tier, never sideways) | timeout | VERIFY_CMD | assert contains |
|---|---|---|---|---|---|---|
| 1 ✅ a4c7d14 | er087-p1-graph-core | `scripts/chat-graph*` | glm-5.2 (T0) → opus | 900 | `bash scripts/chat-graph.test.sh` | `suppressed` |
| 2 ✅ f1b34a5 | er087-p2a-scan-export | `scripts/chat-graph*` | glm-5.2 → opus | 900 | `bash scripts/chat-graph.test.sh` | `Spawned-by:` |
| 3 ✅ 10b5853 | er087-p2b-chats-fixture | `dashboard/fixtures/*` | spark (T2, down-tier: bounded+mechanically checkable) → gpt-5.3 | 300 | `python3 scripts/chat-graph validate-export dashboard/fixtures/chats.json` | `"schema"` |
| 4 ✅ 0ba3f31 | er087-p3a-automation-status | `scripts/automation-status*` | glm-5.2 → opus | 600 | `bash scripts/automation-status.test.sh` | `offline-media` |
| 5 ✅ 446a3b7 | er087-p3b-jobs-registry | `dashboard/*` | spark → gpt-5.3 | 300 | `automation-status --json --registry dashboard/jobs.json` parses + contains repo-state-watch labels | `com.gillettes.nightly-review` |
| 6 ✅ 9a8e74e+723b3ea | er087-p4a-dashboard-cli | `scripts/dashboard*` | glm-5.2 → opus | 900 | `bash scripts/dashboard.test.sh` | `collect` |
| 7 ✅ fc23378 | er087-p4b-launchd-template | `launchd/*` | spark → gpt-5.3 | 300 | sed-substitute template + `plutil -lint` | `com.gillettes.mission-control` |
| 8 ✅ f90887f | er087-p4c-runbook | `docs/runbooks/*` | spark → gpt-5.3 | 300 | greps for chmod 700 + install + bootout lines | `launchctl bootout` |
| 9 ✅ aa2dcc6+4494a04 | er087-p5-shell | `dashboard/**` | **opus (T0, route-up locked: Trevor-visible UX)** → native takeover + codex spot-audit | 1200 | `bash scripts/dashboard.test.sh --require-shell` (SKIPs shell section cleanly when index.html absent, mandatory under the flag: 3 fenced sections, `window.MC`, zero `innerHTML`, no external http(s) loads, fixtures parse) | `window.MC` |

Canonical invocation (packet 1; others substitute row values; run from the repo):
```bash
bash scripts/delegate-audit-loop.sh \
  --task-file "$SPECS/task-p1-graph-core.md" --work-dir "$WT" \
  --scope 'scripts/chat-graph*' --verify-cmd 'bash scripts/chat-graph.test.sh' \
  --assert-file scripts/chat-graph --assert-contains suppressed \
  --worker-family claude --worker-model glm-5.2 --worker-timeout 900 \
  --max-rounds 3 --triaged-tier T0 \
  --governor-id "$GOV_ID" --governor-provider claude --governor-name "ER-087 mission-control build" \
  --id er087-p1-graph-core
```
Escalation rerun = same command, escalation model, `--id <spec>-esc1` (never reuse a terminal id). GLM outage mid-lane: spawn helper auto-falls back to opus (cost bump, not stall); if flapping, pin `--worker-model claude-opus-4-8` for remaining claude packets + record the routing note. Packet 2b's fixture is SYNTHETIC only (no real session ids/transcript text committed — security).

**Gate reports to Trevor** (each packet boundary, plain words, 3–4 lines): what landed, rounds used, the governor's own verify line + exit code (never the worker's claim), the live-proof output line, what starts next. Escalation report: what's blocked, nothing landed + files untouched, blocker-report path, one plain-words top problem, the standard next step (one tier up; second failure = stop and bring options).

## Verification: evidence rules + live proofs (theater-proof)

**Evidence rule (all packets):** the Work Record pastes verbatim (a) the governor's verify rerun tail from `~/.cross-agent/delegations/<id>/round-log.txt` incl. exit-0 line, (b) landed commit hash + `git show --stat` file list, (c) in-scope changed-paths list, (d) the calibration ledger row, (e) the live-proof command + real output. Worker prose (`round-N-result.md`) is never quoted as evidence.

**Live-data proofs after each landing (run by the governor in the worktree; real `$HOME` state, outside the worker sandbox — things fixtures can't fake):**
- P1: `chat-graph ingest && chat-graph show 541d686b-ac12-40b7-b258-c98ef7e33a60` → must list spawned→`019ecd05-e57e-7c91-87e5-3a68959df3df` (a REAL delegation on disk with `handshake_verified: yes`) at confidence 1.0 source=delegations; `stats` → delegations ≥22, mailbox ≥5 (today's real counts); `stat -f %Lp ~/.chat-graph` → `700`.
- P2: the locked **full-history first scan**: `caffeinate -i scripts/chat-graph ingest --full` from the orchestrator terminal (measured ~2–8 min; NEVER inside a verify-cmd) after the `--limit-files 25` smoke; then `show` on a real `Audit:`-titled Codex session (14 exist in `session_index.jsonl`) → audits edge with source=title; immediate re-run → "0 new/changed files" (cursor no-op); `export --json && validate-export`.
- P3: `automation-status --json` parses; nightly-review row green against last night's real report; label count vs registry (surplus = `unregistered`, never vanished); live dead-job specimen (`morning-health-brief`, currently exit 1) reads red/yellow honestly.
- P4: `dashboard collect --force` → 8 files (4 `.json` + 4 `.js`), `.js` payload byte-equals `.json`; `status` exit codes; real registration `dashboard install && launchctl list | grep mission-control` (reversible).
- P5: `dashboard demo` then BOTH `open -a Safari` and `open -a "Google Chrome"` on `~/.mission-control/index.html` — all four tabs render fixture data with freshness dots in EACH browser (file:// script loading = named risk #1; a block in either browser → `--serve` fallback must work, fixed as P1 inside the phase, not shrugged); then `dashboard open` live: usage tab cross-checked against `usage-snapshot` stdout, git rows against `scan-unfinished-work --json`.
- End-to-end (pre-merge): kill/re-bootstrap a test launchd job → automation tab red within one cadence then green; stop the mission-control ticker → all panels age to amber + desaturate within 2× cadence, restart recovers; suppression round-trip `link A B && unlink A B && ingest && show A` → stays suppressed; delete graph.db → `rebuild` → suppression STILL active (journal proof).

## Final assurance stack (ordered, after packet 9)

1. **Records commit** (native, on the branch): copy the 9 task files into `records/implementation-packets/2026-07-XX-er087-mission-control-packets/`; discoverability pointers (AGENTS.project.md script notes + runbook link); plan-doc phase-table status marks — so the review below covers THEM too.
2. **Full-diff cross-AI review (Codex gpt-5.5, read-only sandbox)**: `git diff origin/main...HEAD > ~/.cross-agent/delegations/er087-review/full-diff.patch`; review packet names the plan doc, diff path, security invariants, suppression semantic, launchd correctness, and test honesty ("do the tests assert or just run?"). Every accepted finding → fix commit + regression test/invariant; rejected → `docs/audits/REJECTED_FINDINGS.md`; deferred → todo.md with owner+trigger.
3. **Fresh-eyes audit chat** (spawned with `--parent-id "$GOV_ID"`, titled `Audit: <this chat's name>` — deliberately also dogfood input): from a clean clone, cold-run both test suites; exercise link→unlink→ingest→show; re-run P1+P2 live proofs; perms = 700 on both state dirs; `grep -c innerHTML dashboard/index.html` = 0; no real secrets/session text in committed fixtures; verdict returned via mailbox.
4. **Push through the gates**: `git push origin er087-mission-control` — global pre-push dispatcher runs verify.sh; no-mistakes pipeline per enrollment. Never `--no-verify`.
5. **Merge-readiness walk** with evidence: committed / pushed / branch ledger refreshed / cross-AI review passed-or-deferred-with-reason / dirty-state snapshots / discoverability.
6. **Dogfood acceptance (the closing proof)**: `chat-graph ingest && chat-graph show "$GOV_ID"` → ≥9 spawned edges (one per converged packet, source=delegations confidence 1.0 — the loop wrote governor id + worker child id + verified handshake into each state.json) + spawned edge to the fresh-eyes audit session + its `audits` edge from the `Audit:` title. **The graph provably contains its own build lineage.** Output pasted into the final Work Record; merge decision goes to Trevor with this as closing evidence.

## Durable records + rollback

Per-packet: todo.md `## Work Record Log` entry (spec id, worker model+tier, rounds, verify line+exit code, commit, live-proof line, honest not-verified list) + `## Test Evidence Log` line per new suite. Per-gate: register ER-087 status note; PROJECT_MEMORY Active Goals update; plan-doc phase mark. At P2 gate: one coordination note in `docs/UNIFIED_TRANSCRIPT_SEARCH_PLAN.md` (read-only ATTACH, v2 collectors gated on its acceptance). Register flips: `in-progress` → `landed` after push → `verified` only after the end-to-end list passes. `~/.cross-agent/delegations/` dirs stay in place (machine-readable audit trail AND P1's ingest corpus). OpenSpec lane: direct build with Work Records (plan/design artifacts already exist); revisit opsx only if Trevor asks.

Rollback: branch never merged + loop never pushes → repo rollback is always free (`git tag archive/er087-mission-control-<date> er087-mission-control && git worktree remove --force <wt> && git branch -D er087-mission-control` + Branch History line). State dirs: `~/.mission-control` always free to remove (`launchctl bootout gui/$UID/com.gillettes.mission-control; rm -rf ~/.mission-control` — all derived). **`~/.chat-graph` is free to remove ONLY while `sqlite3 ~/.chat-graph/graph.db "SELECT count(*) FROM edges WHERE source='manual' OR status='suppressed';"` returns 0. The moment anyone runs `chat-graph link`/`unlink`, never rm — `sqlite3 graph.db ".backup ..."` first (manual links are the one non-re-derivable thing; the journal is the second copy).** Mid-packet blocker: loop guarantees work-dir untouched — nothing to roll back.

## Choreography risks (self-aware)

1. Quota exhaustion mid-lane → preflights (above); mid-run 429s = failed rounds → clean stop at exit 3; resume after window reset with fresh ids. 2. GLM flap → auto-fallback to opus; pin if repeated. 3. Timeout blowups → per-packet timeouts 300–1200s + <90s test-suite invariant + full scan banned from verify-cmds. 4. Sandbox EPERM misread → env-override invariant, feedback not sandbox-off. 5. Two-strike thrash → up exactly one tier with calibration evidence, never sideways. 6. Parallel-chat repo churn → all landing in the isolated worktree; orchestrator never commits to main. 7. file:// block in one browser → per-browser P5 gate + `--serve` escape hatch as in-phase P1 fix.

## Security invariants (restated — not compressed)

`~/.chat-graph/` and `~/.mission-control/` are `chmod 700`, never committed to git, never cloud-synced, never network-served (127.0.0.1 only under explicit `--serve`). Transcript-derived display text runs through the existing display-time redaction layer (`search-transcripts`). All feed text renders via `textContent`, never `innerHTML`. Committed fixtures are synthetic — no real session ids or transcript text. Workers run write-sandboxed; the sandbox is never disabled to make a round pass.
