# Mission-Control Dashboard + Chat-Graph — Research Note (2026-07-02)

- Register: ER-087 · Plan: `docs/MISSION_CONTROL_PLAN.md` · Session: Claude `1ef98716-30bb-4530-80e0-6b2f3fa74f79`
- Method: two parallel web-research agents during the planning session (free pass — WebSearch/WebFetch fan-out; no paid scrapers). Agent 1: prior-art sweep, 16 tools triaged across 4 categories. Agent 2: dashboard information-design rules from primary sources.
- Consumers: the approved plan adopted a steal-list + 8 v1-binding design rules from this note. Source cards for the 5 pattern-donor repos live in the 3rd-party repo (`researched-repos/`, commit `105a2db`). Correction from card verification (GitHub API, 2026-07-02): cass's license is `NOASSERTION`, not MIT as first researched — read its license file before any code reuse (pattern-mining unaffected).

## Headline findings

1. **Cross-provider chat-relationship mapping is genuinely novel.** Multi-provider session *viewers/search* are crowded (agent-sessions 677★, cass 938★, klovi, cc-session, claude-code-history-viewer, AgentsView) — every one is a flat list/index. Best relationship features anywhere: agent-sessions v4 within-provider badges (`workflow`, `side`); claude-view / Claude-Code-Agent-Monitor Claude-only subagent trees. Nothing links sessions ACROSS providers (Claude parent → Codex worker → auditing chat), nothing reconstructs spawn/audit lineage from cross-provider evidence. Our `~/.cross-agent/` provenance makes it buildable with no prior art to copy.
2. **Proven rendering path for lineage: badges → tree → optional graph.** Every serious trace tool (Langfuse, LangSmith, Phoenix, AgentOps) defaults to tree for structure + timeline for time; node-link graphs are opt-in and auto-inferred, never the default.
3. **Force-directed graphs rejected on evidence.** Node-link readability collapses past ~20 nodes (Ghoniem/Fekete/Castagliola controlled study); force layouts produce unstable positions across refreshes — spatial memory is destroyed for a many-times-a-day user. Deterministic layered layout, hard cap ~25 visible nodes, permanent labels — only on click.

## Prior-art inventory (16 triaged)

| Tool | Stars/state | What it shows | Pattern stolen |
|---|---|---|---|
| ryoppippi/ccusage (MIT) | 16.8k | 14+ local sources, daily/blocks/live cost | local-JSONL multi-provider cost, 5h-window math, statusline ambient string |
| Maciek-roboblog/Claude-Code-Usage-Monitor (MIT) | 8.3k | burn rate, "runs out at HH:MM", P90 limits | burn + time-to-limit projection; official-vs-estimate trust labels |
| chiphuyen/sniffly (MIT) | 1.2k | usage + error-category breakdown | failure-mode panel (v2) |
| tombelieber/claude-view (MIT) | ~90 | "Mission Control for Claude Code": session cards, kanban, subagent tree, context gauge | file-watcher → live-push (zero polling); context-fill gauge (v2) |
| hoangsonww/Claude-Code-Agent-Monitor (MIT) | 741 | hook→SQLite→WebSocket; tree + DAG/Sankey pages | two-level disclosure: inline tree, DAG on demand |
| Langfuse (core MIT) | ~15k | traces, cost dashboards, agent graphs | tree/timeline/graph triple view of one trace; custom-dashboard-as-saved-query |
| LangSmith (closed) | — | waterfall + tree, per-step cost | master-detail convention (list left, payload right) |
| Arize Phoenix (ELv2) | 10.4k | OTel span trees, sessions | agent-queryable observability (skills) |
| AgentOps (MIT) | ~4-5k | replay, waterfall | — |
| BloopAI/vibe-kanban (Apache-2.0, sunset) | 27.2k | kanban task → agent workspace (worktree+branch) | task↔branch/worktree binding for open work (v2) |
| glanceapp/glance (AGPL) | 35.6k | pages→columns→widgets, one YAML | fetch-on-load + per-widget cache TTL (pattern-mine only — AGPL) |
| gethomepage/homepage (GPL-3) | 31.3k | service cards: icon + status dot + 2-4 stats | uniform card anatomy for automation tab |
| Lissy93/dashy (MIT) / homarr | ~22k / ~8k | YAML dashboards / drag-drop GUI | homarr's GUI config = anti-pattern (not git-trackable) |
| nosarthur/gita (MIT) | 1.9k | one line per repo, color+symbol status | 5-color branch legend + 4-symbol encoding |
| fboender/multi-git-status (MIT) | ~1k | "needs commit/push/pull/upstream" | action-verb phrasing of repo state |
| nickgerace/gfold (Apache-2.0) | 397 | concurrent scan, JSON output | scanner-emits-JSON, dumb renderer |

Cross-provider viewers checked for novelty: jazzyalex/agent-sessions (677★, MIT — Codex/Claude/OpenCode/Cursor/Copilot/Hermes in one list, quota meter, resume-in-terminal; badges only), Dicklesworthstone/coding_agent_session_search "cass" (938★, license NOASSERTION per GitHub API — 22+ provider parsers → SQLite, BM25+semantic, explicitly no lineage), klovi, cc-session, claude-code-history-viewer, AgentsView (closed).

## Design rules adopted (v1-binding; full reasoning in plan Part C)

1. First screen = exceptions: global status strip + merged "Needs attention" list (≤7 rows, plain-words problem + one-line action + jump link) + four fixed-anatomy summary cards. (Grafana 5-second rule; Few single-screen.)
2. No wall of green — clean repos collapse to one expandable line; a color must carry an action; red = act-now only.
3. Never color alone — Okabe-Ito palette (green #009E73, amber #E69F00, red #D55E00, blue #0072B2) + glyphs ✓/!/✕/○/⏸.
4. Honest data age per panel; stale desaturates + banner; frozen green is worse than no dashboard.
5. Tables beat charts for status lists; `tabular-nums`; low precision; pace beats totals ("62% used, 40% of window gone — ×1.55 hot").
6. Refresh matches data rate; revalidate on window focus; nothing while hidden.
7. Lineage = tree, never physics: ≤10 sessions → clustered cards; 10–50 → indented tree with collapsed finished subtrees; >50 → flat table with expand-on-demand lineage.
8. Empty/degraded states first-class: never-ran ≠ failed ≠ unreadable ≠ paused ≠ T7-unmounted.
v2: diff-on-return ("since you last looked"), 7-day burn sparklines (shared scale), per-job last-20-runs strips.

## Anti-patterns (rejected)

Wall of green; force-directed hairball; false liveness (pulsing "live" over dead fetches); gauges/3D/decoration; alert-color inflation; over-refresh value jitter; 7-digit precision; panel sprawl.

## Sources

Design: Few *Common Pitfalls in Dashboard Design* (perceptualedge.com whitepaper); Grafana dashboard best practices; Datadog executive-dashboards + dashboards-at-scale; Smashing Magazine *UX Strategies for Real-Time Dashboards* (2025-09); Pencil & Paper dashboard UX patterns; dbkay "Save Red, Yellow, and Green for Traffic Lights"; Stacey Barr KPI traffic-light problems; ClearPoint RAG playbook; Ghoniem/Fekete/Castagliola node-link vs matrix (Palgrave IVS 9500092); Hairball Buster (Connections 2019-009); Cambridge Intelligence large-networks + dynamic-networks; Carbon status-indicator pattern; Okabe-Ito palette references; MDN font-variant-numeric; Tufte sparkline theory; TanStack Query window-focus refetching; UptimeRobot status-page guide; UX Tigers think-time; dark-mode dashboard patterns (aydesign, Toptal).
Prior art: github.com/{ryoppippi/ccusage, Maciek-roboblog/Claude-Code-Usage-Monitor, chiphuyen/sniffly, tombelieber/claude-view, hoangsonww/Claude-Code-Agent-Monitor, ColeMurray/claude-code-otel, langfuse/langfuse, Arize-ai/phoenix, AgentOps-AI/agentops, BloopAI/vibe-kanban, glanceapp/glance, gethomepage/homepage, Lissy93/dashy, nosarthur/gita, fboender/multi-git-status, nickgerace/gfold, jazzyalex/agent-sessions, Dicklesworthstone/coding_agent_session_search, cookielab/klovi, tyql688/cc-session, jhlee0409/claude-code-history-viewer}; langfuse.com agent-graphs + custom-dashboards docs; langchain.com/langsmith; agentsview.io; laminar.sh top-6 observability ranking.
