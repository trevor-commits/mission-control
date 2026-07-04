# Dashboard Coding Tracker Search Audit (2026-07-04)

- Query: <https://github.com/search?q=dashboard+coding+tracker+in%3Aname%2Cdescription%2Creadme+stars%3A%3E10&type=repositories>
- Repo focus: `/Users/gillettes/Coding Projects/mission-control`
- Audit type: source-only external search audit and pattern-mining review.
- Current Mission Control constraint: local/offline dashboard, passive readers where possible, no invented provider percentages, no broad credential/cookie surface in the dashboard itself.
- Method: GitHub search API metadata sweep, README/license/architecture deep-read for high-fit candidates, screenshot spot-check for visual patterns, and comparison to Mission Control's project intent and current queue.

## Scope And Evidence

- GitHub search result count on 2026-07-04: `18475`, `incomplete_results=false`.
- GitHub API rows fetched: top `1000` by GitHub search relevance, then filtered by Mission Control fit.
- Deep-read candidates: `getagentseal/codeburn`, `mm7894215/TokenTracker`, `phuryn/claude-usage`, `steipete/CodexBar`, `onllm-dev/onWatch`, `kenn-io/agentsview`, `graykode/abtop`, `simple10/agents-observe`, `uppinote20/claude-dashboard`, `hoangsonww/Claude-Code-Agent-Monitor`, `siteboon/claudecodeui`, `The-Vibe-Company/companion`, `agent-of-empires/agent-of-empires`, `wangdabaoqq/LinJun`, `nimbalyst/nimbalyst`, `builderz-labs/mission-control`, `BradGroux/veritas-kanban`, `jonwiggins/optio`, `Priivacy-ai/spec-kitty`, `RunMaestro/Maestro`, `spatie/dashboard.spatie.be`, `canonical/dashboard`, `onejgordon/flow-dashboard`, `ActivityWatch/activitywatch`, `netbirdio/dashboard`, `saleor/saleor-dashboard`, `opensearch-project/OpenSearch-Dashboards`, `kubernetes-retired/dashboard`, `gridstack/gridstack.js`, `Egonex-AI/Understand-Anything`, and `Graphify-Labs/graphify`.
- Screenshot spot-checks: CodeBurn dashboard, TokenTracker dashboard, CodexBar menu bar popover, AgentsView session dashboard, abtop terminal monitor, and builderz Mission Control overview.
- Not performed: cloning, installing, running third-party code, credentialed provider checks, paid API checks, or license-level code reuse approval.

## Headline

The strongest path is not a framework rewrite or a generic admin template. Mission Control should keep its static/local architecture and borrow four product patterns: compact quota/provider status, usage attribution drill-down, active-session monitoring, and honest data-source confidence labels.

The search also reinforces a boundary: many attractive tools become risky when they auto-install hooks, read browser cookies, require API keys, expose remote dashboards, or grow into a full multi-agent platform. Pattern-mine them first; integrate only through explicit passive-reader adapters or opt-in import commands.

## Best Candidate Findings

| Repo | Fit | What To Borrow | What To Avoid |
|---|---:|---|---|
| [`getagentseal/codeburn`](https://github.com/getagentseal/codeburn) | High | Local-first multi-tool usage breakdowns by project, model, activity, core tools, shell commands, MCP servers, plus "optimize", "compare", and git-yield views. | Do not install as a hard dependency until Node version, source paths, transcript exposure, and adapter contract are reviewed. |
| [`mm7894215/TokenTracker`](https://github.com/mm7894215/TokenTracker) | High | Provider cards, total-token hero, activity heatmap, trend chart, provider/tool integration table, `status --json`-style diagnostics. | Avoid hook auto-install, cloud/leaderboard, and broad provider integration until hook-collision and privacy review. |
| [`phuryn/claude-usage`](https://github.com/phuryn/claude-usage) | High | Stdlib-only incremental JSONL scanner, explicit "not captured" section, local SQLite cache, bookmarkable filters. | Do not depend on CDN Chart.js in the installed local dashboard; vendor or reimplement if used. |
| [`steipete/CodexBar`](https://github.com/steipete/CodexBar) | High | Tiny provider status cards, reset countdowns, pace labels, incident/status badges, manual/1m/2m/5m/15m refresh cadence. | Avoid browser-cookie/keychain/full-disk-access surfaces in Mission Control unless a separate opt-in tool owns that risk. |
| [`onllm-dev/onWatch`](https://github.com/onllm-dev/onWatch) | Medium | Quota cycle overview, burn forecasting, alert thresholds, all-provider tab, Prometheus-style machine endpoint. | GPL and API-key daemon surface make it a pattern source, not a direct dependency. |
| [`kenn-io/agentsview`](https://github.com/kenn-io/agentsview) | High | Master-detail session list, filters, metric cards, heatmaps, top sessions table, direct read fallback when daemon is cold. | Do not expose public dashboards without auth; Mission Control should stay local-only by default. |
| [`graykode/abtop`](https://github.com/graykode/abtop) | High | "What is running right now" table: status, model, context percent, tokens, git state, child ports, orphan ports, `--json` snapshot. | Treat JSON as sensitive because transcript-derived context may leak. |
| [`simple10/agents-observe`](https://github.com/simple10/agents-observe) | Medium | Hook event timeline, replayable status stream, subagent hierarchy, SQLite plus WebSocket model. | Hook-heavy Docker/server design is more moving parts than v1 needs. |
| [`hoangsonww/Claude-Code-Agent-Monitor`](https://github.com/hoangsonww/Claude-Code-Agent-Monitor) | Medium | Existing source card already supports hook-to-SQLite-WebSocket and two-level graph disclosure pattern. | Claude-only and hook-bound; keep as reference, not the cross-provider base. |
| [`builderz-labs/mission-control`](https://github.com/builderz-labs/mission-control) | Medium | Warning banner with action buttons, gateway health, golden-signal panels, incident stream. | Too broad: 32 panels, RBAC, multi-gateway orchestration, evaluations, recurring tasks, and API sprawl are second-system risk here. |
| [`agent-of-empires/agent-of-empires`](https://github.com/agent-of-empires/agent-of-empires) | Medium | Mobile-friendly session states, worktree/session persistence, diff-review workflow, phone access framing. | Remote tunnel/session manager is outside current Mission Control scope. |
| [`nimbalyst/nimbalyst`](https://github.com/nimbalyst/nimbalyst) | Medium | Link sessions to files, tasks, kanban items, git status, and mobile "needs you" states. | Electron app, sync/telemetry, and full workspace manager are heavier than this repo's architecture. |
| [`spatie/dashboard.spatie.be`](https://github.com/spatie/dashboard.spatie.be) | Low | Large glanceable operational tiles and human-readable status copy. | Laravel app architecture is not useful for the local static dashboard. |
| [`ActivityWatch/activitywatch`](https://github.com/ActivityWatch/activitywatch) | Medium | Timeline/event-bucket model and local personal analytics framing. | Broad activity tracking is privacy-heavy; use only if Trevor explicitly wants time tracking. |
| [`gridstack/gridstack.js`](https://github.com/gridstack/gridstack.js) | Low | Optional later drag/drop widget layout pattern. | Drag/drop layout is not a v1 usability fix; it can create messy, non-git-trackable personal layouts. |
| [`tabler/tabler`](https://github.com/tabler/tabler) | Existing card | Mature dashboard anatomy: cards, badges, tabs, icons, dense tables. | Existing source card already says pattern-mine only; do not install wholesale. |

## Patterns Worth Implementing

### 1. Provider And Quota Status Should Become A First-Class Strip

Influenced by CodexBar, TokenTracker, onWatch, and CodeBurn.

Mission Control should add a compact usage strip that answers:

- Which provider/tool is close to a reset or quota limit?
- Is the number live, estimated, stale, skipped, or unavailable?
- What is the next useful action: wait, switch model/tool, refresh, authenticate, or ignore?

Recommended shape:

- One small card per provider/tool.
- Fields: `state`, `used`, `limit`, `resets_at`, `pace`, `source`, `confidence`, `last_checked`.
- No fake percentages. If a provider source is unavailable, show `not captured` with a reason.
- Keep red only for act-now; stale and estimate states should be amber/neutral.

### 2. Usage Needs Attribution, Not Just Totals

Influenced by CodeBurn, TokenTracker, claude-usage, and AgentsView.

The useful drill-down levels are:

- by tool/provider
- by model
- by project/repo
- by session
- by day/window
- by activity type
- by shell command / core tool / MCP server when safely derivable

This is more useful than a large total-token chart because Trevor's real decision is "what should I use next and what burned the window?"

Implementation boundary:

- Add a normalized local feed envelope first.
- Optional future adapters can import JSON from external tools, but Mission Control should not require them.
- Do not read provider credentials or browser cookies inside the dashboard renderer.

### 3. Add A "Current Agent Monitor" View

Influenced by abtop, AgentsView, agent-of-empires, and Nimbalyst.

The dashboard needs one list for active work across local coding agents:

- chat/session name
- provider/tool
- repo/cwd
- state: working, needs you, blocked, idle, stale
- branch/dirty/ahead state when known
- model/effort when known
- context/tokens when known
- last activity
- jump action: reopen, read transcript, inspect diff

This should be table-first. Charts can help later, but a table is the fastest way to answer "what needs my attention?"

### 4. Add A Yield Lens After Usage Works

Influenced most directly by CodeBurn.

A later view should correlate AI sessions with git outcomes:

- shipped commit
- reverted change
- abandoned dirty work
- no-op/help-only session
- review/audit-only session

This is the closest pattern to making Mission Control a decision tool instead of a dashboard. It also supports Trevor's larger goal: preserve subscription value, reduce wasted runs, and spot loops that do not land.

### 5. Make Data-Source Honesty Visible Everywhere

Influenced by claude-usage, AgentsView, CodexBar, onWatch, and current Mission Control stale-ingest rules.

Every panel should expose a small data provenance line:

- `live`
- `local cache`
- `estimated`
- `partial`
- `stale`
- `not captured`
- `skipped`, with reason

The "not captured" state matters. Several tools make this explicit; Mission Control should make it a product principle. A blank or frozen green status is worse than a visible limitation.

### 6. Improve Navigation Around User Questions, Not Data Sources

Search-result dashboards tend to organize by implementation area. Mission Control should organize by Trevor's questions:

- Home: what needs attention now?
- Usage: what can I safely spend?
- Sessions: what is running or stalled?
- Map: how did chats/work connect?
- Git: what changed and what needs landing?
- Automation: what is scheduled or unhealthy?
- Records: what did we decide and where is the proof?

This is already close to the current design direction. The search mainly confirms that adding more panels is less valuable than making the existing tabs answer these questions cleanly.

## Backend And Data Model Implications

Mission Control should keep a small local collector model:

```mermaid
flowchart LR
  A["Passive local readers"] --> B["Normalized feed envelopes"]
  C["Optional external JSON imports"] --> B
  D["Manual or scheduled refresh"] --> A
  B --> E["Static dashboard renderer"]
  B --> F["CLI status/doctor output"]
  E --> G["Home, Usage, Sessions, Map, Git, Automation"]
```

Recommended feed fields:

| Field | Reason |
|---|---|
| `source_id` | Lets panels say where the number came from. |
| `source_kind` | Separates passive reader, cache, imported JSON, and manual note. |
| `collected_at` | Supports stale detection. |
| `confidence` | Prevents estimates from looking official. |
| `scope` | Provider, repo, session, branch, automation, or global. |
| `decision_state` | ok, attention, blocked, stale, partial, not captured. |
| `next_action` | Turns data into a user-facing dashboard. |
| `raw_ref` | Path or command that produced it, not secrets or transcript payload. |

Adapters should be optional and boring. Start with local files and existing scripts; add `--json` import support only after the feed contract is stable.

## Frontend And UX Implications

Strong patterns to steal:

- Compact provider cards with reset countdown and confidence label.
- Top-level "needs attention" banner only when there is a real action.
- Left-to-right priority: problem, impact, action, source age.
- Heatmaps for activity density, not for critical status.
- Master-detail session browser: list on the left, selected session details on the right.
- Dense tables with stable columns for repeat decisions.
- Simple status badges with plain wording.
- Mobile first state list: `Needs you`, `Working`, `Blocked`, `Idle`, `Stale`.

Patterns to reject:

- Generic drag/drop dashboards before the information hierarchy is stable.
- Force-directed graph as the default view.
- Decorative card sprawl or 20+ panel home screens.
- Full remote control surface inside Mission Control.
- Login/RBAC/API architecture unless Mission Control becomes multi-user, which is not the current product.
- Provider scoreboards that imply precision from local estimates.

## Suggested Mission Control Queue

1. **Usage V1 clarity:** Add provider/tool status cards with reset/pace/source/confidence fields. Keep unavailable sources explicit.
2. **Usage attribution:** Add by-provider, by-model, by-project, and by-session breakdowns from current local feeds before adding external adapters.
3. **Session monitor:** Add an active-session table with state, repo, branch/dirty/ahead, last activity, and reopen/read actions.
4. **Source diagnostics:** Add a `dashboard status --json` or equivalent feed status output so UI and automation consume the same honesty layer.
5. **Yield lens:** After usage and session IDs are stable, correlate sessions to commits/reverts/abandoned diffs.
6. **Mobile summary:** Add a compact "needs you / working / blocked / idle" section optimized for quick phone checks.

## Source-Capture Status

Existing relevant source cards in the third-party research repo already cover:

- `researched-repos/tabler-tabler.md`
- `researched-repos/hoangsonww-claude-code-agent-monitor.md`
- `researched-repos/jazzyalex-agent-sessions.md`
- `researched-repos/tombelieber-claude-view.md`
- `researched-repos/ccusage-ccusage.md`

New top candidates that should receive source cards in the third-party index when that shared checkout is clean:

- `getagentseal/codeburn`
- `mm7894215/TokenTracker`
- `kenn-io/agentsview`
- `graykode/abtop`
- `steipete/CodexBar`

At audit closeout, the third-party research checkout already had unrelated modified top-level source cards and a dirty external-source intake file. I did not add new cards there because a scoped closeout would have mixed this audit with another actor's source-card work. The current audit keeps the actionable findings in this Mission Control record so the next implementation pass is not blocked on third-party index maintenance.

## Final Recommendation

Do not adopt a competing dashboard project wholesale. Build the next Mission Control improvements as a small set of local feed and UI upgrades:

- usage/quota cards with reset and confidence labels
- usage attribution tables
- active-agent/session monitor
- data-source honesty line per panel
- later yield lens tied to git outcomes

This keeps the repo aligned with its current purpose: a local operator dashboard that explains what needs attention and why, without becoming a second agent platform.
