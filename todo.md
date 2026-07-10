# TODO

## Active Next Steps
If it's not here, it isn't remembered.
Capture the current goal plus the concrete dependency-ordered steps that are still open.
- Keep this section short, current, and ordered by impact/dependency.
- When this repo has a configured Linear workspace, each actionable item should carry the matching issue ID inline using the repo's real team prefix.
- Keep the matching `Linear Issue Ledger` entry current whenever an item's repo-side home or urgency changes.
- Put audit-created actionable execution items at the top of this section so audit follow-through is the next queue to execute.
- If the current chat creates or discovers more urgent execution-ready work than the existing queue reflects, persist and move that fresher work to the top of this section before handoff so the chat is not the only durable record.
- When a step is verified complete, move or summarize it in `## Completed` instead of deleting the history.
- ER-107 Morning Brief (highest, implemented-pending-proof): deterministic Tier 1 outcomes, high-recall decisions, resumable delivery code, installed dashboard, and default-dry-run loose-end review are review-clean. Next gates are canonical reinstall/rollback proof, explicit Telegram/launchd authorization, bounded Tier 2 calibration, and approximately five natural mornings before verification/archive. | owner: Codex thread `019f4963-1e75-7600-8a17-1e6f6f8e8ca6` | linear: repo-only; no Mission Control Linear team is configured.
- ER-089 usage-aware autonomous routing (high): design and implement provider-usage adapters only where safe credentials/sources exist, then expose the routing signal in Mission Control without inventing missing provider percentages. Blocker: Trevor-held provider auth for z.ai/OpenAI/GitHub if live usage is required. | owner: next Mission Control routing session | linear: self-contained until Linear is configured.
- ER-090 autonomous coding-hygiene loop (high): design the coordinator that consumes Mission Control feeds and raises glaring decisions for dirty work, branches, and fixable problems without unsafe auto-merge/push behavior. Build only after the boundary/aggressiveness decision is recorded. | owner: next Mission Control autonomy session | linear: self-contained until Linear is configured.
- P14 end-of-day loose-ends robot (after ER-090/P12 boundaries): consume the new Open work ledger in dry-run first, auto-fix only mechanically safe items, and escalate decision items loudly without merging, force-pushing, deleting, or editing human docs. | owner: future Mission Control autonomy session | linear: self-contained until Linear is configured.

## Linear Issue Ledger
If it's not here, it isn't remembered.
Mirror every configured Linear issue here with the repo-side home that explains why it exists.
- Each entry should capture:
  - `issue`
  - `status`
  - `todo home`
  - `why this exists`
  - `origin source`
  - `last synced`
- If this repo is intentionally `repo-only` or no configured Linear workspace exists yet, keep an explicit note here instead of leaving the section absent.
- Current mode: repo-only. No Mission Control Linear team/prefix has been verified; Trevor has been asked whether to set one up. Do not invent issue IDs.

## Completed
If it's not here, it isn't remembered.
Preserve a durable completion trail for verified work instead of deleting it from active planning.
- Going forward, prefer one-line entries in this shape: `YYYY-MM-DD | <issue-or-scope>: short title — landed as <SHA>; full record in Work Record Log YYYY-MM-DD`.
- 2026-07-09 | ER-107 Phase 0 reliability repairs — T7 LaunchAgents moved to a stable internal runtime, Morning Health bounded and registered, and improvement-loop wrapper noise removed; owning-repo commits `bbed5e3`, `bd7226e`, `1326217`, and `5f01334`; full record below.
- 2026-07-08 | Audit-loop severity rules — implemented computed red/amber/grey severity for the Open work ledger; full record below.
- 2026-07-08 | Audit-loop wording polish — clarified the Open work hide action and proved source-backed items reappear on refresh; landed in the audit-loop follow-up commit; full record below.
- 2026-07-08 | Map journal action polish — aligned Home/Map/Chats action labels and made Map journal rows open the matching connection web; full record below.
- 2026-07-08 | One loose-ends ledger — implemented the flat Open work export and dashboard reader; full record below.
- 2026-07-04 | Dashboard search-audit V1 UI bundle — implemented and carried into this closeout with local verification; full record below.
- 2026-07-04 | GitHub dashboard/coding-tracker search audit — source-only pattern audit landed; full record below.
- 2026-07-04 | 207d88dd Cursor patch closeout — completed the dirty audit-fix patch with focused regressions and installed-browser proof; landed as 3a612e5; full record below.
- 2026-07-04 | Map recent chat journal — added a five-line recent-chat recap to the Connection map; full record below.
- 2026-07-04 | ER-087 follow-up audit gaps — governance scaffold, product intent, tab wording, stale-ingest honesty, and Map smoke coverage landed in this change; full record below.

## Work Record Log
### 2026-07-09 — Morning Brief orchestration convergence
- Problem: Fable's plan mixed a sound Mission Control product direction with one stale priority and several high-risk capabilities whose trust, privacy, concurrency, and activation boundaries were not yet proven.
- Reasoning: Make Morning Brief the product that composes session recall, response clarity, durable memory, and open-work orchestration; ship a useful deterministic Tier 1 slice first and keep model egress, external delivery, schedules, and automatic action behind explicit gates.
- Diagnosis inputs: audited Fable session `35d96de4-9509-4382-b1a0-10b9a4d1777e`, linked plan-author session `6f306a0b-abbb-4d39-9d64-afa7fb977250`, U1-U7 plan audit, actual Mission Control/T7/global runtime state, installed browser captures, real fleet dry-run, and independent Codex reviews.
- Implementation inputs: commits `fce2a7a`, `255ad3d`, `ab693c6`, `2f3d38a`, `0523925`, and `2da8c9b`; OpenSpec `morning-brief`; the HOTL workflow; live graph/decision feeds; and records under `records/`.
- Fix: implemented provider-native bounded outcome cards, parser-safe exact resolution, transactional high-recall decisions, deterministic brief enrichment, structured Git facts, and a no-execute dry-run runner; repaired browser-found split decisions and false activation failures; installed code without installing LaunchAgents; and corrected the independent reviewer's P2 stale generated-HOTL-state finding through the HOTL runtime.
- Self-audit:
  - method: full cold suites, syntax/static/privacy/negative checks, strict OpenSpec and HOTL validation, live parser migration, installed Home/Brief/Automation captures, real 56-repository dry-run, per-record runner review, and separate holistic implementation audit.
  - outcome: code-review-clean for the deterministic/Tier 1 slice; dashboard `PASS=29 FAIL=0`, runner `PASS=32 FAIL=0`, 23/23 real runner candidates correctly refused, and automatic push remains unavailable.
  - did not verify: authorized Telegram/deadman receipt, Tier 2 provider extraction, natural launchd cadence, or approximately five real mornings; these remain explicit external/elapsed gates.
- by: Codex thread `019f4963-1e75-7600-8a17-1e6f6f8e8ca6` with independent reviewers `/root/outcome_audit`, `/root/git_runner_audit`, and `/root/decision_audit`.
- triggered by: Trevor's request to audit Fable thoroughly, implement agreed findings, and iterate with another Codex reviewer.
- led to: mergeable zero-call/Tier 1 Mission Control slice; ER-107 remains implemented-pending-proof rather than verified.
- linear: repo-only; no Mission Control Linear team is configured.

### 2026-07-09 — Morning Brief Phase 0 cross-repo reliability repairs
- Problem: Fable's Morning Brief plan depended on jobs and correction feeds that were not trustworthy: T7-backed LaunchAgents could fail with exit 126, Morning Health scanned stale whole-log denials and could hang on an unbounded census, and the improvement loop mistook provider wrappers for user corrections.
- Reasoning: Repair the owning systems before allowing Mission Control to summarize them; otherwise a polished brief would amplify false or stale status.
- Diagnosis inputs: live launchd arguments/status/log segments, the T7 runtime repo and installer, Morning Health markers, the global improvement-loop queue/lessons/digest, and independent focused reviews.
- Implementation inputs: third-party runtime commits `bbed5e3`, `bd7226e`, `1326217`; global improvement-loop commit `5f01334`; Mission Control automation registry in `ab693c6`.
- Fix: moved all tracked jobs to `/Users/gillettes/Coding Projects/3rd-party-xscan-checkout`; added static/dynamic removable-media validation and transactional installer rollback; bounded the starred-repo census; made Morning Health use a stable last-run marker and current log segment; filtered Claude/Codex provider wrappers; grouped corrections before capping; and atomically quarantined nine proven false signatures while preserving unrelated real work.
- Self-audit:
  - method: owning-repo suites and validators, live selective reinstall with loaded-state restoration, current-segment log inspection, global verification, quarantine rollback tests, and independent code review in each owning repo.
  - outcome: passed; the stable runtime matches pushed `1326217`, intended jobs are loaded from the internal path, the latest Morning Health segment has no exit 126 or fresh TCC denial, and the global improvement-loop branch/main contain `5f01334` with review-clean fixtures.
  - did not verify: future natural launchd schedules or multiple elapsed Morning Health cycles; the current Morning Health result remains honestly flagged by a real existing starred-drain attention state.
- by: Codex thread `019f4963-1e75-7600-8a17-1e6f6f8e8ca6` with independent reviewers `/root/phase0_recon` and `/root/spec_challenger`.
- triggered by: Fable plan Phase 0 and the live audit of its assumptions.
- led to: Mission Control can now consume these sources as repaired inputs; elapsed schedule proof remains separate from implementation completion.
- linear: repo-only; no Mission Control Linear team is configured.

### 2026-07-09 — Morning Brief resumable delivery and privacy convergence
- Problem: The first delivery/deadman implementation passed its happy-path suites but independent adversarial review found correctness, freshness, concurrency, and privacy failures that made live delivery unsafe.
- Reasoning: Treat the first green suite as a draft, convert every reviewer counterexample into a regression, and keep Telegram/launchd side effects gated until the implementation itself is review-clean.
- Diagnosis inputs: OpenSpec/HOTL delivery contracts, the actual diff after `255ad3d`, repeated independent adversarial review, and synthetic sender/deadman/dashboard/error fixtures.
- Implementation inputs: `scripts/morning-brief`, `scripts/morning-brief-deadman`, `scripts/dashboard`, their focused suites, two launchd templates, automation registry/fixture, and the shared egress module.
- Fix: implemented fixed-argv resumable delivery, atomic receipts/cursor, exact-once concurrency, same-day deadman proof, shared compose/send locking, immutable compose markers, fail-closed sidecar timestamps, whole-message privacy screening, content-free egress counters, last-good-plus-current-error UI overlays, and shared ERROR sanitization before JSON/JS persistence.
- Self-audit:
  - method: repeated red/green adversarial fixtures, full focused cold suites, strict OpenSpec and HOTL lint, render smoke, and independent review after every material finding.
  - outcome: delivery/privacy slice is review-clean; dashboard is `PASS=26 FAIL=0`, and every accepted finding has a regression.
  - did not verify: live Telegram receipt, installed Mission Control launchd cadence, safe live deadman exercise, canonical installed browser capture, rollback, session outcomes, decisions, safe runner, or five natural mornings.
- by: Codex thread `019f4963-1e75-7600-8a17-1e6f6f8e8ca6` with independent reviewer `/root/mission_mapping`.
- triggered by: Fable plan audit and Trevor's request to implement agreed findings until complete.
- led to: authorized-live-delivery gate next; outcome extraction, decision queue, and runner remain subsequent OpenSpec phases.
- linear: repo-only; no Mission Control Linear team is configured.

If it's not here, it isn't remembered.
Use one entry per bounded task, fix, audit, or review that would otherwise lose reasoning between chats.

```md
### YYYY-MM-DD — short title
- Problem:
- Reasoning:
- Diagnosis inputs:
- Implementation inputs:
- Fix:
- Self-audit:
  - method:
  - outcome:
  - did not verify:
- by:
- triggered by:
- led to:
- linear:
```

### 2026-07-09 — Morning Brief trusted substrate and deterministic thin brief
- Problem: The approved Morning Brief plan depended on trustworthy open-work changes, distinct job runs, field-aware privacy, and a useful brief that did not wait for model-based outcome extraction.
- Reasoning: Ship the deterministic product slice first so Mission Control is useful when models are disabled, deferred, or over budget; keep transcript/model enrichment downstream of privacy and coverage calibration.
- Diagnosis inputs: Fable plan `019f4550-2a9a-7fe3-9313-9e7a0be10b35-tha-cuddly-hopcroft.md`, U1-U7 upgrade audit, OpenSpec `morning-brief`, existing graph/automation/dashboard suites, and synthetic privacy fixtures.
- Implementation inputs: `scripts/mission_control_common.py`, `scripts/chat-graph`, `scripts/automation-status`, `scripts/scan-unfinished-work`, `scripts/morning-brief`, `scripts/dashboard`, dashboard fixtures/renderers, and the governed OpenSpec/HOTL records.
- Fix: added graph schema v5 with provider/node hygiene and explicit resolution evidence; added bounded open-work changes; added distinct-run automation history; added minimal recent Git facts; composed atomic Markdown plus `latest.json`; added preview routing, a dashboard Brief feed, Home summary, and full Brief tab.
- Self-audit:
  - method: red/green synthetic suites, schema migration fixtures, repeated-poll/concurrency tests, equal-timestamp and mid-compose event tests, dashboard shell/render smoke, strict OpenSpec/HOTL validation, and file-browser captures of Home and Brief.
  - outcome: passed for the implemented slice; checkpoint `fce2a7a` is pushed, and the thin-brief follow-up is pending its next commit.
  - did not verify: delivery receipts/deadman, session outcome extraction, decision queue, safe runner, live canonical install, or five real mornings; those remain explicitly later phases.
- by: Codex thread `019f4963-1e75-7600-8a17-1e6f6f8e8ca6` with bounded subagent implementation/review slices.
- triggered by: audit and implementation of Fable session `35d96de4-9509-4382-b1a0-10b9a4d1777e` and its linked plan-authoring session.
- led to: delivery/deadman tests next, followed by outcome coverage and enrichment only after privacy review.
- linear: repo-only; no Mission Control Linear team is configured.

### 2026-07-08 — One loose-ends ledger
- Problem: Mission Control still had several places where open work could hide: chat handoffs, repo todo files, dirty Git state, nightly findings, and request-register rows were not converging into one reader-facing list.
- Reasoning: Trevor's loose-ends/autonomy request should not become another parallel tracker. The safe first step is to make `scripts/chat-graph` the single ledger and keep the dashboard as a reader of that ledger.
- Diagnosis inputs: Claude chat `1ef98716-30bb-4530-80e0-6b2f3fa74f79`, `docs/IMPROVEMENTS.md` P13/P14 specs, `scripts/chat-graph`, `dashboard/index.html`, chat fixtures, and the current V1 UI bundle.
- Implementation inputs: `scripts/chat-graph`, `scripts/chat-graph.test.sh`, `dashboard/index.html`, `dashboard/fixtures/chats.json`, `scripts/dashboard-render-smoke.js`, `PROJECT_INTENT.md`, and `docs/IMPROVEMENTS.md`.
- Fix: added `first_seen_at` to `open_ends`; added `todo_open`, `nightly_finding`, `repo_dirty`, and `register_open` collectors; exported a flat `data.loose_ends` list with action hints, age, severity, and dismiss command; made Home and Chats/Open work read the flat list; kept the Map recent-chat journal in the connected-chat view.
- Self-audit:
  - method: focused unit/regression tests for each collector and auto-resolve path, fixture-backed render smoke, dashboard shell tests, installed dashboard refresh, and browser capture before closeout.
  - outcome: passed; graph, dashboard, automation, usage, scan, syntax/json, whitespace, installed refresh, and browser capture checks all passed.
  - did not verify: P14 end-of-day autonomous execution, because it is intentionally queued behind the decision-boundary work.
- by: Codex thread `019f2b73-9811-7392-b511-201c1f109997`.
- triggered by: Trevor asked to finish the audit gaps from chat `1ef98716-30bb-4530-80e0-6b2f3fa74f79` and added a one-to-five-line connected-chat journal requirement.
- led to: P14 remains queued after ER-090/P12 boundaries; no autonomous fixer was built in this pass.
- linear: self-contained until Linear is configured.

### 2026-07-08 — Map journal action polish
- Problem: The Map recent-chat journal existed and was capped to five rows, but the rows did not offer a direct plain-word way to jump from "what did I touch?" into that chat's connection web. Home's compact session monitor also still used shorter action labels than Map and Chats.
- Reasoning: Trevor asked for a next-day memory aid in the connected-chat view. The smallest useful improvement is to keep the existing feed-driven journal, add a "Show connections" action, and align action labels without adding a new collector or summarizer.
- Diagnosis inputs: Claude Code chat `1ef98716-30bb-4530-80e0-6b2f3fa74f79`, Trevor's current journal request, `PROJECT_INTENT.md`, `notes/DIRECTION-2026-07-04.md`, `dashboard/index.html`, `dashboard/fixtures/chats.json`, and `scripts/dashboard-render-smoke.js`.
- Implementation inputs: `dashboard/index.html`, `dashboard/fixtures/chats.json`, `scripts/dashboard-render-smoke.js`, and independent Codex audit worker `019f4309-f85e-72a3-9e3e-92e6281b2222`.
- Fix: changed Home session-monitor actions to `Reopen this chat` / `Read transcript`; added `Show connections` to each Map journal row; strengthened render smoke so Home and Chats must cover both plain action labels and Map must keep the journal connection action.
- Self-audit:
  - method: full local suite rerun, fixture-backed render smoke, JSON/syntax/whitespace checks, and browser capture of the demo Map with the vendored graph library loaded.
  - outcome: passed; independent follow-up audit returned `review-clean`.
  - did not verify: future Map search/timeline, Home triage scoring, title enrichment, or autonomy/routing packets; those remain queued work.
- by: Codex thread `019f2b73-9811-7392-b511-201c1f109997`.
- triggered by: Trevor asked for a tiny one-to-five-line journal/log in the connected-chat view so the next day he can remember what chat he used and when.
- led to: no new active follow-up; broader Map and routing/autonomy upgrades remain in the existing queue.
- linear: self-contained until Linear is configured.

### 2026-07-08 — Audit-loop wording polish
- Problem: The Open work command label said `Dismiss this item`, which could read like a permanent removal even when the item came from a live source such as `todo.md`.
- Reasoning: Source-backed work should stay honest: hiding it is a short-term local action, and the item must return on the next refresh if the source still says it is open.
- Diagnosis inputs: backup Codex audit loop risk check on commit `838358a`, `dashboard/index.html`, `scripts/chat-graph`, `scripts/chat-graph.test.sh`, and `scripts/dashboard-render-smoke.js`.
- Implementation inputs: `dashboard/index.html`, `scripts/chat-graph.test.sh`, `scripts/dashboard-render-smoke.js`, and this `todo.md`.
- Fix: changed the visible command from `Dismiss this item` to `Hide until refresh`, and added a regression that manually resolving a `todo_open` item hides it once but the collector restores it when the unchecked todo remains.
- Self-audit:
  - method: reran the graph suite, dashboard shell suite, and render smoke after the copy/test change.
  - outcome: passed; `chat-graph.test.sh`, `dashboard.test.sh --require-shell`, and `dashboard-render-smoke.js` all passed.
  - did not verify: a live browser recapture after this copy-only follow-up; previous installed Home/Map/Open work captures remained valid for the broader UI.
- by: Codex thread `019f2b73-9811-7392-b511-201c1f109997`.
- triggered by: independent Codex audit loop risk surfaced during closeout for commit `838358a`.
- led to: no new active follow-up.
- linear: self-contained until Linear is configured.

### 2026-07-08 — Audit-loop severity rules
- Problem: The P13 Open work ledger exported a `severity` field, but the independent audit found that the documented red/amber/grey rules were not actually encoded.
- Reasoning: Home and Chats can only be trusted as a daily command surface if urgent items are ranked by computed evidence, not by a mostly constant amber default.
- Diagnosis inputs: Codex audit worker `019f42ec-0968-7091-a331-9944b5f2ef92`, `docs/IMPROVEMENTS.md`, `scripts/chat-graph`, and `scripts/chat-graph.test.sh`.
- Implementation inputs: `scripts/chat-graph`, `scripts/chat-graph.test.sh`, `docs/IMPROVEMENTS.md`, and this `todo.md`.
- Fix: implemented export-time severity rules for P0/security register rows, detached/divergent Git state, stale handoffs older than 21 days, and unpushed Git work; added a graph export regression for each documented case.
- Self-audit:
  - method: ran the full graph suite, dashboard shell suite, render smoke, syntax check, and whitespace check.
  - outcome: passed; the new severity regression and all dashboard render checks passed.
  - did not verify: live provider usage sources or future launchd cadence; not touched by this fix.
- by: Codex thread `019f2b73-9811-7392-b511-201c1f109997`.
- triggered by: independent Codex audit finding on commit `838358a`.
- led to: no new active follow-up.
- linear: self-contained until Linear is configured.

### 2026-07-04 — 207d88dd Cursor patch closeout
- Problem: Cursor chat `207d88dd-4abf-4328-a66a-aa55a8801d21` implemented a useful audit-fix patch but left it dirty, uncommitted, unpushed, and under-tested for several repaired failure modes.
- Reasoning: the existing patch addressed real dashboard/chat-graph safety and honesty issues; the safest closeout was to keep the direction, tighten the remaining command-execution edge, add focused regression checks, run release evidence, and land the whole patch with repo-visible records.
- Diagnosis inputs: Cursor transcript `207d88dd-4abf-4328-a66a-aa55a8801d21`; prior Codex audit record and commit `31ee124`; dirty diff across dashboard, chat graph, dashboard CLI, scan, and usage snapshot files; Mission Control AGENTS/project docs; release-gate suites.
- Implementation inputs: `dashboard/index.html`, `scripts/chat-graph`, `scripts/dashboard`, `scripts/scan-unfinished-work`, `scripts/usage-snapshot`, `scripts/chat-graph.test.sh`, `scripts/dashboard.test.sh`, `scripts/dashboard-render-smoke.js`, and new `scripts/usage-snapshot.test.sh`.
- Fix: completed the dashboard/chat-graph honesty fixes; removed shell execution from dashboard feeders and credit notifications; made usage notifications reject shell metacharacters and split without glob expansion; preserved tab-containing branch parsing; surfaced stale/skipped chat ingest, normalized usage status, scoped Map edges, and yellow automation jobs; added durable regression tests for the fixed behaviors.
- Self-audit:
  - method: re-read the diff, added regression tests for each high-risk fixed path, ran the local release gates, installed the dashboard runtime, collected live feeds, took a browser capture, scanned the diff for secret-token patterns, and checked final git state before landing.
  - outcome: passed; local suites and installed-browser proof succeeded, and the active `207d88dd Cursor patch closeout` queue item is closed.
  - did not verify: live launchd cadence over future intervals and live provider-side usage percentages beyond the current local feed snapshot.
- by: Codex thread `019f2ddb-4d45-79b2-9ed7-da8303fb3439`.
- triggered by: Trevor request to thoroughly fix and audit after the Cursor chat audit.
- led to: no new active follow-up; ER-089 and ER-090 remain separate product-scope queue items.
- linear: self-contained until Linear is configured.

### 2026-07-04 — Dashboard search-audit V1 UI bundle
- Problem: the search audit surfaced the first concrete Mission Control UI/routing pass still missing from the dashboard: per-panel source honesty, decision-oriented usage cards, clearer Map detail, better needs-you wording, a compact session monitor, and an activity heatmap.
- Reasoning: this was the top unblocked queue item, and it improved Trevor's actual operator questions without adding dependencies or starting the riskier ER-089/ER-090 work first.
- Diagnosis inputs: `PROJECT_INTENT.md`, `notes/DIRECTION-2026-07-04.md`, `records/2026-07-04-dashboard-coding-tracker-search-audit.md`, `dashboard/index.html`, `dashboard/fixtures/*.json`, `scripts/dashboard-render-smoke.js`, and the local dashboard test suite.
- Implementation inputs: `dashboard/index.html`, `dashboard/fixtures/usage.json`, and `scripts/dashboard-render-smoke.js`.
- Fix: added per-panel provenance/source lines across Home/Map/Chats/Git/Usage/Automation; rewrote Usage around decision cards with source/trust/next-action copy; upgraded the Home needs-attention rows to show problem, impact, next action, and source age; added a compact session monitor plus a local chat-activity heatmap; improved the Map side panel with summary cards, grouped connections, confidence/source chips, and honest focus/filter wording; aligned usage fixture source labels with the real feeder outputs; extended render smoke coverage for the new sections.
- Self-audit:
  - method: re-read the changed dashboard shell against the search-audit requirements, ran `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell` and `node scripts/dashboard-render-smoke.js .` after each substantive audit fix, and ran repeated separate code-review passes until no material issues remained.
  - outcome: passed; the dashboard packet is implemented locally, the release gates stayed green, and the follow-up audit no longer found material issues in the changed work.
  - did not verify: installed browser/file:// rendering in a live browser capture during this packet, because this session stayed inside local shell + headless verification only and no new install/runtime capture was produced here.
- by: Codex thread `631e0a16-efe8-4377-aa81-0d02783eea59`.
- triggered by: Trevor asked to execute the repo's next required work beginning with the bounded Dashboard V1 bundle and to ensure it was audited and tested.
- led to: ER-089 and ER-090 remain the active follow-up queue; this packet removed the top local/offline UI bundle blocker ahead of them.
- linear: self-contained until Linear is configured.

### 2026-07-04 — GitHub dashboard/coding-tracker search audit
- Problem: Trevor asked for a thorough search audit of GitHub repositories matching `dashboard coding tracker` to find backend, frontend, workflow, wording, and visual patterns that could make Mission Control more useful and easier to digest.
- Reasoning: the GitHub search is very broad and star count is noisy, so the useful work was to sweep the top result set, filter for Mission Control fit, deep-read high-signal candidates, and preserve pattern-level recommendations without installing third-party tools.
- Diagnosis inputs: GitHub search API result count about `18.5k` with `incomplete_results=false` (`18474` latest run; `18475` earlier same-day run); top `1000` API results; README/license/metadata deep reads; README screenshot/asset-reference reviews for CodeBurn, TokenTracker, CodexBar, AgentsView, abtop, and builderz Mission Control; existing Mission Control project intent and queue.
- Implementation inputs: `records/2026-07-04-dashboard-coding-tracker-search-audit.md`, existing third-party source cards for Tabler, Claude-Code-Agent-Monitor, agent-sessions, claude-view, and ccusage, plus the active ER-089/ER-090 queue boundaries.
- Fix: wrote a source-only audit record that recommends compact provider/quota cards, usage attribution drill-downs, active-session monitoring, explicit data-source confidence labels, a later git-yield lens, and mobile-friendly state summaries while rejecting framework rewrites, remote-control surfaces, and generic dashboard kits for v1.
- Self-audit:
  - method: compared external candidates against Mission Control's local/offline product constraints, separated direct patterns from install/adoption risk, and kept the recommendations tied to current tabs and feed boundaries.
  - outcome: passed; the audit produces an implementation queue without changing runtime behavior or adding third-party dependencies.
  - did not verify: cloned/runtime behavior of third-party repositories, credentialed provider usage APIs, paid services, code-level license reuse, or new third-party source-card closeout; the shared third-party index had unrelated dirty top-level source-card/intake work, so this pass preserved findings in the Mission Control record instead of mixing commits.
- by: Codex thread `019f2dec-d36b-7093-8259-8d9df30dede0`.
- triggered by: Trevor request to investigate the GitHub search URL for Mission Control improvement ideas.
- led to: keep ER-089 focused on safe usage/provider status and add the search-audit UI patterns to the next Mission Control polish/routing implementation pass.
- linear: self-contained until Linear is configured.

### 2026-07-04 — ER-087 Mission Control follow-up gaps
- Problem: the standalone repo had the working dashboard code but not enough repo-local governance, product-owner wording, stale full-ingest honesty, or real Map render coverage.
- Reasoning: Trevor's `1ef98716` feedback and `notes/DIRECTION-2026-07-04.md` made Phase 2/4 clarity the blocker before usage-routing/autonomy work.
- Diagnosis inputs: audited chat `*Chat connection tracking tool` (`1ef98716-30bb-4530-80e0-6b2f3fa74f79`), `notes/DIRECTION-2026-07-04.md`, dashboard source, test suites, and browser captures.
- Implementation inputs: `PROJECT_INTENT.md`, dashboard copy, chat-graph export counts, dashboard status freshness check, render smoke, repo governance scaffold, and ER-089/ER-090 queue entries.
- Fix: wrote plain-language `PROJECT_INTENT.md`; added required governance files; changed visible labels across Home/Map/Chats/Git/Usage/Automation; hid raw chat commands behind Reopen/Read labels; surfaced stale full-ingest status; added a real Cytoscape-path smoke test; queued usage-routing/autonomy without implementing them.
- Self-audit:
  - method: source scan for stale labels, full Mission Control test gates, governance validators, and Home/Map/Chats browser captures.
  - outcome: passed; Map overlap found in capture and fixed by showing chat names in the side panel/selected state instead of default canvas labels.
  - did not verify: real provider usage percentages, because ER-089 remains queued pending safe provider credentials/sources.
- by: Codex thread `019f2b73-9811-7392-b511-201c1f109997`.
- triggered by: Trevor follow-up to audited chat `1ef98716-30bb-4530-80e0-6b2f3fa74f79`.
- led to: ER-089 and ER-090 remain active V2 queue items; Linear remains repo-only until configured.
- linear: self-contained until Linear is configured.

### 2026-07-04 — Map recent chat journal
- Problem: Trevor wanted the connected-chat view to show a tiny next-day memory aid: what he touched, when, and which chat it was.
- Reasoning: the existing chats feed already has title, AI, repo, and `last_activity`, so a separate journal collector or summarizer would be extra moving parts.
- Diagnosis inputs: `dashboard/index.html`, `scripts/dashboard-render-smoke.js`, `dashboard/fixtures/chats.json`, and installed Map screenshot.
- Implementation inputs: existing Map renderer, chat fixture feed, and `PROJECT_INTENT.md`.
- Fix: added a `Recent chat journal` section to Map, capped at five newest chats, using existing feed fields only; render smoke now asserts the newest chat title appears on Map.
- Self-audit:
  - method: renderer smoke, dashboard suite, whitespace check, installed-dashboard update, and browser capture.
  - outcome: passed; screenshot shows the five-row journal above the graph.
  - did not verify: whether titles are always the best summary text for every provider; this uses current feed data until a real summarizer is justified.
- by: Codex thread `019f2b73-9811-7392-b511-201c1f109997`.
- triggered by: Trevor requested a one-to-five-line connected-chat journal/reminder.
- led to: no new active follow-up; a title-quality upgrade can wait until titles prove insufficient.
- linear: self-contained until Linear is configured.

## Suggested Recommendation Log
If it's not here, it isn't remembered.
Keep materially new suggestions here so they survive beyond the current chat.
- Forward entry shape should include `date`, `recommendation`, `why`, `by:`, and `linear:`.
- Do not delete old entries; mark them completed, declined, deferred, or superseded with date and chat context.
- Keep audit-created items here only when they are deferred, optional, or not yet execution-ready; otherwise promote them into `## Active Next Steps`.
- When a suggestion comes from an audit or feedback review, link back to the originating audit record or `Feedback Decision Log` entry and later note which chat implemented or declined it.
- 2026-07-04 | recommendation: pattern-mine the dashboard/coding-tracker search audit during the next ER-089/UI polish pass: provider reset/pace cards, usage attribution tables, active-session state list, source-confidence labels, and a later git-yield lens; do not rewrite Mission Control into Next/React, a remote-control platform, or a generic drag/drop dashboard. | why: the highest-fit repos confirm Mission Control's local/static architecture but reveal better visual and workflow affordances for usage, sessions, and attention routing. | by: Codex thread `019f2dec-d36b-7093-8259-8d9df30dede0`; record: `records/2026-07-04-dashboard-coding-tracker-search-audit.md`. | linear: self-contained until Linear is configured.
- 2026-07-04 | recommendation: pattern-mine `tabler/tabler` during the next Mission Control UI polish pass, especially cards, dense tables, badges, tabs, segmented controls, and offline-safe icon affordances; do not install `@tabler/core` wholesale unless a later implementation proves the static file:// bundle stays simpler and safer. | why: Tabler is a mature MIT Bootstrap dashboard kit, but this repo's product intent is still a single-file local/offline dashboard. | by: Codex thread `019f2d4e-54ba-7273-8188-12506a3daf19`; source card: third-party index `researched-repos/tabler-tabler.md` commit `171a122`. | linear: self-contained until Linear is configured.
- 2026-07-05 | recommendation: do not adopt the GitHub Copilot enterprise-observability stack (OpenTelemetry Collector, Prometheus, Grafana, OpenObserve, Superset, Metabase, Airbyte, Meltano, dbt-core, Great Expectations, TensorZero, Helicone, OpenLIT, traceAI, TraceRoot, Pull Request Analytics Action); treat `records/2026-07-04-dashboard-coding-tracker-search-audit.md` as the real same-niche repo map; if a chart is ever justified, prefer vendorable zero-dependency `leeoniya/uPlot` over Chart.js/ECharts/CDN — but not for V1. | why: Copilot recommended from the repo description alone (it said so); every headline pick runs as a background service, framework, or separate warehouse and collides with the explicit non-goals of offline single-file, single-user, no-server. Full evaluation in Feedback Decision Log 2026-07-05. | by: Claude Code (Opus 4.8) session `a9724039-6595-4205-a25b-bf361020250a`. | linear: self-contained until Linear is configured.

## Active Branch Ledger
Keep one entry per non-trivial active branch so any chat can see why it exists, which chat opened or resumed it, what work is active, what must happen before merge or closeout, and whether the branch should be deleted or intentionally retained.
Legacy branches opened before this workflow may still need manual backfill; use `TODO: verify` instead of guessing until those entries are added.
Each active branch entry should include:
- `branch`
- `status`
- `created`
- `base`
- `source chat`
- `last refreshed by chat`
- `purpose`
- `linked issue`
- `plugin mirror`
- `merge expectation`
- `merge target`
- `review surface`
- `exit checklist`
- `delete when` or `retain after close`
- `retain reason` when not deleting
- `cleanup command`
- `linked PR/audit/completion record`

### `codex/morning-brief`
- status: active
- created: 2026-07-09
- base: `origin/main` at `ebfbd50`
- worktree: `/Users/gillettes/Coding Projects/mission-control-worktrees/morning-brief`
- source chat: 2026-07-09 `Audit: Mission Control orchestration priorities` (`019f4963-1e75-7600-8a17-1e6f6f8e8ca6`)
- last refreshed by chat: 2026-07-09 same Codex thread
- purpose: Implement ER-107 Morning Brief and the approved Fable plan plus U1-U7 audit corrections as one reviewable product lane.
- linked issue: repo-only disposition; no Mission Control Linear team is configured
- plugin mirror: none; repo-only mode is explicit in the Linear Issue Ledger
- merge expectation: merge to `main`
- merge target: `main`
- review surface: independent Codex evidence audit, then final adversarial review; PR or direct merge after all blocking findings close
- exit checklist:
  - [ ] OpenSpec artifacts, HOTL workflow, and durable plan pointers complete
  - [ ] Thin brief, outcome extraction, decision queue, delivery proof, and safe dry-run runner complete
  - [ ] Full local and installed-runtime verification complete
  - [ ] Independent audit loop reaches review-clean or explicit deferred risk
  - [ ] Work/Test/Audit records and project memory refreshed
  - [ ] Branch committed, pushed, merged or explicitly handed off
- delete when: after merge, remote push, durable closeout, and worktree removal
- retain reason: n/a
- cleanup command: `git -C /Users/gillettes/Coding\ Projects/mission-control worktree remove /Users/gillettes/Coding\ Projects/mission-control-worktrees/morning-brief && git -C /Users/gillettes/Coding\ Projects/mission-control branch -d codex/morning-brief`
- linked PR/audit/completion record: `openspec/changes/morning-brief/`; final record pending

## Branch History
- No closed branch entries recorded yet.

## Audit Record Convention
If it's not here, it isn't remembered.
- Record each audit, ship-check, or substantial verification-driven review in an easy-to-find project audit log entry.
- Each entry should capture:
  - `date`
  - `type` (for example `full audit`, `targeted audit`, `ship-check`, `governance review`)
  - `scope`
  - `repo fingerprint` (branch + commit when available)
  - `prior audit reference`
  - `source/work chat`
  - `audit chat`
  - `implementation chat` or `disposition chat`
  - `separate follow-up audit` (`yes` / `no` plus reason when `no`)
  - `commands / evidence`
  - `tested`
  - `not tested`
  - `findings opened or updated`
  - `fixes closed / verified`
  - `declined / deferred findings`
  - `better-path challenge`
  - `references` (issue, PR, commit, or log path)
  - `by`
  - `linear`
- When a finding is later implemented, deferred, declined, or superseded, update the existing audit trail instead of deleting the history.

## Audit Record Log
If it's not here, it isn't remembered.
- 2026-07-09 | independent Morning Brief implementation audit | scope: final deterministic/Tier 1 commits, OpenSpec/HOTL contracts, cold suites, installed/browser proof, live graph state, and 56-repository runner dry-run | repo fingerprint: `codex/morning-brief` at `2da8c9b` plus closeout records | prior audit reference: outcome parser and per-record runner audits in this Codex thread | source/work chat: Codex `019f4963-1e75-7600-8a17-1e6f6f8e8ca6` auditing Fable `35d96de4-9509-4382-b1a0-10b9a4d1777e` | audit chat: separate Codex agent `/root/decision_audit` | implementation chat: source/work chat | separate follow-up audit: yes; one P2 stale generated HOTL sidecar/report finding was accepted and corrected through the supported HOTL runtime | commands/evidence: all focused suites, strict OpenSpec, HOTL lint, installed code-only hash manifests, three browser captures, `/tmp/morning-brief-runner-live-*.json*`, and `records/morning-brief-independent-codex-audit.md` | tested: outcomes, decisions, delivery/deadman code, dashboard, structured Git facts, default-dry-run runner, privacy, installed rendering, and rollback artifacts | not tested: live Telegram, Tier 2, launchd activation, automatic push, natural cadence, or five mornings | findings opened or updated: P2 durable-state contradiction | fixes closed / verified: generated HOTL run marked blocked/superseded without invented execution evidence | declined / deferred findings: external and elapsed gates explicitly deferred | better-path challenge: merge the useful deterministic product slice without pretending the overall program is verified | references: `records/morning-brief-independent-codex-audit.md`; `openspec/changes/morning-brief/verify.md` | by: Codex | linear: repo-only.
- 2026-07-08 | independent Map journal polish audit | scope: Home session-monitor action labels, Map recent-chat journal action, Chats action-label smoke coverage, and fixture fallback coverage | repo fingerprint: `main` at `1175101` with local journal polish diff | prior audit reference: Claude Code chat `1ef98716-30bb-4530-80e0-6b2f3fa74f79` plus Mission Control `Map recent chat journal` work record | source/work chat: Codex `019f2b73-9811-7392-b511-201c1f109997` | audit chat: Codex worker `019f4309-f85e-72a3-9e3e-92e6281b2222` | implementation chat: Codex `019f2b73-9811-7392-b511-201c1f109997` | separate follow-up audit: yes; worker found a P3 smoke gap and rechecked the fix | commands/evidence: `bash scripts/chat-graph.test.sh`; `bash scripts/automation-status.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js`; `node scripts/dashboard-render-smoke.js .`; `bash scripts/usage-snapshot.test.sh`; `bash scripts/scan-unfinished-work --self-test`; `python3 -m json.tool dashboard/fixtures/chats.json`; `git diff --check`; browser capture `/tmp/mission-control-map-journal-polish-with-graph.png` | tested: Map journal five-row render, `Show connections` action, Home and Chats `Reopen this chat` / `Read transcript` labels, view-only fixture fallback, and Cytoscape graph render alongside the journal | not tested: queued Map search/timeline, Home triage scoring, title enrichment, usage routing, or autonomy | findings opened or updated: P3 smoke fallback gap fixed in-session | fixes closed/verified: render smoke now requires both plain action labels and a journal connection action; independent follow-up audit returned `review-clean` | declined/deferred findings: residual queued packets remain intentionally deferred | better-path challenge: keep this as a small clarity polish using existing feed data instead of adding a new journal data source | references: Work Record `2026-07-08 — Map journal action polish` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-08 | independent audit-loop severity fix | scope: P13 Open work severity computation in `scripts/chat-graph` and graph tests | repo fingerprint: `main` after wording fix `74a5af5` with local severity diff | prior audit reference: Codex audit worker `019f42ec-0968-7091-a331-9944b5f2ef92` finding on commit `838358a` | source/work chat: Codex `019f2b73-9811-7392-b511-201c1f109997` | audit chat: Codex worker `019f42ec-0968-7091-a331-9944b5f2ef92` | implementation chat: Codex `019f2b73-9811-7392-b511-201c1f109997` | separate follow-up audit: yes; worker found severity drift from the P13 contract | commands/evidence: `bash scripts/chat-graph.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `python3 -m py_compile scripts/chat-graph`; `git diff --check` | tested: register P0/security red, stale handoff grey, unpushed Git amber, detached Git red, dashboard render compatibility | not tested: live browser recapture after this logic-only follow-up | findings opened or updated: P2 severity-rule drift fixed in-session | fixes closed/verified: `_loose_severity()` now encodes documented cases and graph export regression covers them | declined/deferred findings: none | better-path challenge: compute severity from source facts rather than adding a manually managed priority field | references: Work Record `2026-07-08 — Audit-loop severity rules` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-08 | independent audit-loop follow-up | scope: Open work temporary-hide label and source-backed reappearance behavior after commit `838358a` | repo fingerprint: `main` at `838358a` plus focused follow-up diff | prior audit reference: Claude Code chat `1ef98716-30bb-4530-80e0-6b2f3fa74f79` and commit `838358a` | source/work chat: Codex `019f2b73-9811-7392-b511-201c1f109997` | audit chat: Codex worker `019f42ec-0968-7091-a331-9944b5f2ef92` plus backup worker `019f42f1-85bd-7603-8a29-cc3eced39054` | implementation chat: Codex `019f2b73-9811-7392-b511-201c1f109997` | separate follow-up audit: yes; worker surfaced the dismiss-label risk and the fix added a regression for source-backed reappearance | commands/evidence: `bash scripts/chat-graph.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .` | tested: temporary-hide wording, `todo_open` manual resolve, `todo_open` reappearance when the source remains open, and Chats render smoke | not tested: live browser recapture after this copy-only follow-up | findings opened or updated: P3 wording risk fixed in-session | fixes closed/verified: `Dismiss this item` replaced by `Hide until refresh`; source-backed hide-once semantics covered by regression | declined/deferred findings: none | better-path challenge: use precise temporary wording instead of making the manual command sound like durable source cleanup | references: Work Record `2026-07-08 — Audit-loop wording polish` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | targeted implementation audit | scope: Dashboard search-audit V1 UI bundle in `dashboard/index.html`, `dashboard/fixtures/usage.json`, and `scripts/dashboard-render-smoke.js` | repo fingerprint: `main` with local uncommitted dashboard bundle changes in the working tree | prior audit reference: `2026-07-04 | external source search audit` and record `records/2026-07-04-dashboard-coding-tracker-search-audit.md` | source/work chat: Codex `631e0a16-efe8-4377-aa81-0d02783eea59` | audit chat: same Codex thread with separate `code-review` subagent passes | implementation chat: same Codex thread | separate follow-up audit: yes; multiple separate review passes were run after implementation and after each fix cycle | commands/evidence: `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node scripts/dashboard-render-smoke.js .`; repeated `code-review` agent passes focused on the changed dashboard files; `git diff --stat -- dashboard/index.html scripts/dashboard-render-smoke.js dashboard/fixtures/usage.json` | tested: panel provenance lines, decision-card rendering, credit-window handling, map side-panel grouping/copy, session-monitor priority/join logic, heatmap alignment/DST bucketing, and fixture-backed render coverage | not tested: installed browser/file:// runtime capture in this packet's own working-tree state | findings opened or updated: all material audit findings were fixed in-session; no new queue item opened from the closeout audit | fixes closed/verified: false 0% usage readings, credit-card duplication, repo-join drift, focus/filter wording, heatmap weekday/DST issues, map grouping honesty, source-label mismatches, and session-rank ordering | declined/deferred findings: none | better-path challenge: keep the packet dependency-light and fix the misleading edge cases instead of shipping a broad visual rewrite | references: Work Record `2026-07-04 — Dashboard search-audit V1 UI bundle`; `records/2026-07-04-dashboard-coding-tracker-search-audit.md` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | external source search audit | scope: GitHub search URL `dashboard coding tracker in:name,description,readme stars:>10`, Mission Control improvement patterns, source-only backend/frontend/workflow/UI review | repo fingerprint: `main` at pre-audit clean state | prior audit reference: `records/2026-07-02-mission-control-research.md` | source/work chat: Codex `019f2dec-d36b-7093-8259-8d9df30dede0` | audit chat: same | implementation chat: not applicable; source-only audit | separate follow-up audit: no; no runtime/code adoption performed | commands/evidence: GitHub API metadata sweep of top 1000 rows from about 18.5k results (`18474` latest run; `18475` earlier same-day run), README/license/metadata deep-read for high-fit candidates, README screenshot/asset-reference reviews for six visual candidates, comparison to Mission Control project intent and active queue | tested: source relevance, architecture fit, visual pattern fit, integration risk classification | not tested: cloned third-party runtime behavior, credentialed provider APIs, paid services, or license-level code reuse | findings opened or updated: Suggested Recommendation Log entry for ER-089/UI polish pattern mining | fixes closed/verified: durable search audit record written | declined/deferred findings: direct adoption/install of third-party tools deferred until opt-in adapter review | better-path challenge: preserve local/offline Mission Control and borrow narrow feed/UI patterns instead of importing a generic dashboard platform | references: `records/2026-07-04-dashboard-coding-tracker-search-audit.md` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | cross-chat implementation closeout | scope: Cursor chat `207d88dd-4abf-4328-a66a-aa55a8801d21` dirty audit-fix patch, regression coverage, durable records, installed runtime, and browser proof | repo fingerprint: `main` at `31ee124` plus eight task-edited files before closeout commit | prior audit reference: `2026-07-04 | cross-chat implementation audit` / commit `31ee124` | source/work chat: Cursor `207d88dd-4abf-4328-a66a-aa55a8801d21` (`Scan this repo for bugs...`) | audit/implementation chat: Codex `019f2ddb-4d45-79b2-9ed7-da8303fb3439` | separate follow-up audit: no; closeout included self-audit and installed-browser proof | commands/evidence: `bash scripts/chat-graph.test.sh`; `bash scripts/usage-snapshot.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `bash scripts/automation-status.test.sh`; `bash scripts/scan-unfinished-work --self-test`; `bash -n ...`; `python3 -m py_compile scripts/chat-graph`; `git diff --check`; token-pattern diff scan; installed collect; browser capture | tested: stale ingest lock recovery, `ingest_skipped` export/status/Home surfacing, dashboard env override shell rejection, usage notification argv/rejection behavior, normalized usage status strip, yellow automation surfacing, scoped Map edge rendering, scan TSV parsing, installed file:// Home render | not tested: launchd over future intervals, provider-side live usage APIs beyond current local snapshot | findings opened or updated: closed Active Next Steps `207d88dd Cursor patch closeout` | fixes closed/verified: dirty/unpushed patch landed with records; missing regression coverage closed; command-execution hardening verified; installed runtime rendered | declined/deferred findings: provider usage adapters and autonomous hygiene loop stay deferred as ER-089/ER-090 product-scope work | better-path challenge: do not accept cross-chat implementation summaries as complete without commit/push, durable records, regression tests, and installed/runtime evidence when UI changes are release-sensitive | references: screenshot `/tmp/mission-control-207d88dd-closeout-home.png`; transcript `/Users/gillettes/.cursor/projects/Users-gillettes-Coding-Projects-mission-control/agent-transcripts/207d88dd-4abf-4328-a66a-aa55a8801d21/207d88dd-4abf-4328-a66a-aa55a8801d21.jsonl`; closeout commit 3a612e5 | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | cross-chat implementation audit | scope: Cursor chat `207d88dd-4abf-4328-a66a-aa55a8801d21` audit findings, implementation claim, dirty diff, and verification claims | repo fingerprint: `main` at `ebb07e2` with six dirty Cursor-touched files | prior audit reference: none for this exact chat | source/work chat: Cursor `207d88dd-4abf-4328-a66a-aa55a8801d21` (`Scan this repo for bugs...`) | audit chat: Codex `019f2ddb-4d45-79b2-9ed7-da8303fb3439` | implementation chat: same Cursor chat; no commit made | separate follow-up audit: yes; this entry records the follow-up audit | commands/evidence: `chat-source describe/full/latest`, raw Cursor JSONL, `git status -sb`, `git diff --stat`, all local release-gate suites, focused stale-lock/export/override probes, `git diff --check`, syntax checks, secret-pattern diff scan | tested: current dirty patch test suites and targeted probes for stale ingest lock, `ingest_skipped`, argv override rejection, SQLite index inspection, scan self-test, render smoke | not tested: installed `~/.mission-control` runtime/browser capture for the dirty patch, live launchd cadence, provider usage live sources | findings opened or updated: Active Next Steps `207d88dd Cursor patch closeout`; P1 dirty uncommitted/unpushed implementation; P2 missing durable Work/Test record; P2 weak regression coverage for several fixed behaviors | fixes closed/verified: current code patch passes local suites and focused probes; no secrets matched in dirty diff | declined/deferred findings: no code fixes performed in this audit-only pass | better-path challenge: do not accept the Cursor chat as complete until the patch is either committed with durable records and targeted tests or intentionally discarded | references: transcript `/Users/gillettes/.cursor/projects/Users-gillettes-Coding-Projects-mission-control/agent-transcripts/207d88dd-4abf-4328-a66a-aa55a8801d21/207d88dd-4abf-4328-a66a-aa55a8801d21.jsonl`; files `dashboard/index.html`, `scripts/chat-graph`, `scripts/dashboard`, `scripts/dashboard.test.sh`, `scripts/scan-unfinished-work`, `scripts/usage-snapshot` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | targeted audit follow-up | scope: Mission Control Phase 2/4 clarity + ER-087 audit gaps | repo fingerprint: `main`, pre-commit follow-up state | prior audit reference: Claude Code chat `1ef98716-30bb-4530-80e0-6b2f3fa74f79` (`*Chat connection tracking tool`) | source/work chat: same | audit/implementation chat: Codex `019f2b73-9811-7392-b511-201c1f109997` | separate follow-up audit: no; this pass included test and browser verification | commands/evidence: see Test Evidence Log | tested: source label scan, all local suites, governance validators, Home/Map/Chats browser captures | not tested: live provider usage adapters | findings opened or updated: ER-089 usage-routing queue, ER-090 autonomous hygiene queue | fixes closed/verified: governance scaffold, PROJECT_INTENT, plain labels, stale full-ingest status, Cytoscape smoke | declined/deferred findings: usage-routing/autonomy implementation deferred until V1 clarity complete | better-path challenge: stopped feature growth until owner-facing clarity and trust signals passed | references: `PROJECT_INTENT.md`, `dashboard/index.html`, `scripts/dashboard-render-smoke.js`, `scripts/chat-graph`, `scripts/dashboard` | by: Codex | linear: self-contained until Linear is configured.

## Test Evidence Convention
If it's not here, it isn't remembered.
- Testing is required delivery evidence. If a check is skipped, blocked, or only partially run, record the reason and the remaining risk.
- Record each verification run as:
  - `date` (YYYY-MM-DD)
  - `command(s)` executed
  - `result` (pass/fail + short note)
  - `log/PR reference` (commit SHA, CI URL, or local log path)
  - `by`
  - `linear`
- When a verification run closes or updates an audit finding, cross-reference the matching audit record entry and the chat or commit that performed the work.

## Test Evidence Log
If it's not here, it isn't remembered.
- 2026-07-09 | commands: full Morning Brief cold matrix (`chat-graph`, `automation-status`, dashboard shell/render, usage, scanner self-test, shared egress, brief/delivery/deadman, coverage, decisions, runner), Python/shell/JSON/static checks, strict OpenSpec, HOTL lint, `git diff --check`, live parser-v5 migration, code-only install, LaunchAgent hash comparison, installed browser capture, and independent per-record/holistic audits | result: PASS for deterministic/Tier 1 implementation; dashboard `PASS=29 FAIL=0`, runner `PASS=32 FAIL=0`, all seven tabs rendered, 23/23 real candidates correctly refused, normalized action-relevant Git facts unchanged, and no LaunchAgent installed | log/PR reference: `openspec/changes/morning-brief/verify.md`; `records/2026-07-09-morning-brief-orchestration-convergence.md`; `records/morning-brief-independent-codex-audit.md`; `/tmp/morning-brief-runner-live-dry-run.jsonl`; `tmp/playwright/morning-brief-installed-*.png` | by: Codex thread `019f4963` and independent reviewers | linear: repo-only.
- 2026-07-09 | commands: Morning Brief delivery/privacy convergence — repeated `bash scripts/morning-brief.test.sh`; `bash scripts/morning-brief-delivery.test.sh`; `bash scripts/morning-brief-deadman.test.sh`; `bash scripts/mission-control-common.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `bash scripts/automation-status.test.sh`; `node scripts/dashboard-render-smoke.js .`; Python/Bash syntax; strict OpenSpec; HOTL document lint; `git diff --check`; independent adversarial replay after each fix | result: PASS; exact-once concurrent delivery, compose/send coherence, same-day deadman, malformed timestamp matrix, stale/error overlay honesty, whole-message secret screening, cursor fail-close, content-free counters, and sensitive stderr rejection all pass; dashboard `PASS=26 FAIL=0`; independent final verdict review-clean | log/PR reference: `records/2026-07-09-morning-brief-delivery-privacy-audit.md`; Work Record `2026-07-09 — Morning Brief resumable delivery and privacy convergence` | by: Codex thread `019f4963` plus reviewer `/root/mission_mapping` | linear: repo-only.
- 2026-07-09 | commands: `bash scripts/mission-control-common.test.sh`; `bash scripts/chat-graph.test.sh`; `bash scripts/automation-status.test.sh`; `bash scripts/morning-brief.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js`; `node scripts/dashboard-render-smoke.js .`; `bash scripts/scan-unfinished-work --self-test`; strict OpenSpec and HOTL validation; `git diff --check`; browser captures of `file:///tmp/mission-control-morning-brief/index.html` Home and `#brief` | result: pass; privacy matrix, graph v5 migration/open-delta suite, distinct automation history, deterministic composer, dashboard PASS=22 FAIL=0, all 7 render tabs, scanner self-test, schema/workflow validation, whitespace, and nonblank Home/Brief screenshots passed | log/PR reference: checkpoint `fce2a7a`; `/tmp/morning-brief-home.png`; `/tmp/morning-brief-tab.png`; Work Record `2026-07-09 — Morning Brief trusted substrate and deterministic thin brief` | by: Codex thread `019f4963-1e75-7600-8a17-1e6f6f8e8ca6` | linear: repo-only; no Mission Control Linear team is configured.
- 2026-07-08 | commands: `bash scripts/chat-graph.test.sh`; `bash scripts/automation-status.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js`; `node scripts/dashboard-render-smoke.js .`; `bash scripts/usage-snapshot.test.sh`; `bash scripts/scan-unfinished-work --self-test`; `python3 -m json.tool dashboard/fixtures/chats.json`; `git diff --check`; `DASHBOARD_NO_OPEN=1 bash scripts/dashboard demo`; browser capture of demo Map with local vendor copied into the demo state | result: pass; graph suite ALL PASS, automation ALL PASS, dashboard suite PASS=22 FAIL=0, render smoke all 6 tabs, usage PASS=2 FAIL=0, scan self-test PASS, JSON/syntax/whitespace checks pass, browser screenshot nonblank at `/tmp/mission-control-map-journal-polish-with-graph.png` | log/PR reference: Work Record Log `2026-07-08 — Map journal action polish` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-08 | commands: `bash scripts/chat-graph.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `python3 -m py_compile scripts/chat-graph`; `git diff --check` | result: pass; graph suite ALL PASS with severity-rule regression, dashboard suite PASS=22 FAIL=0, render smoke all 6 tabs, syntax/whitespace checks pass | log/PR reference: Work Record Log `2026-07-08 — Audit-loop severity rules` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-08 | commands: `bash scripts/chat-graph.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .` | result: pass; graph suite ALL PASS, dashboard suite PASS=22 FAIL=0, render smoke all 6 tabs after the temporary-hide wording and source-backed reappearance regression | log/PR reference: Work Record Log `2026-07-08 — Audit-loop wording polish` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-08 | commands: `bash scripts/chat-graph.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `bash scripts/automation-status.test.sh`; `bash scripts/usage-snapshot.test.sh`; `bash scripts/scan-unfinished-work --self-test`; `bash -n scripts/dashboard scripts/usage-snapshot scripts/scan-unfinished-work scripts/chat-graph.test.sh scripts/dashboard.test.sh scripts/usage-snapshot.test.sh scripts/automation-status.test.sh`; `python3 -m py_compile scripts/chat-graph`; `python3 -m json.tool dashboard/fixtures/chats.json`; `git diff --check`; `/Users/gillettes/.codex/scripts/ai-browser-runtime.sh ensure`; `MISSION_CONTROL_HOME="$HOME/.mission-control" REPO_ROOT="$PWD" bash scripts/dashboard install`; `MISSION_CONTROL_HOME="$HOME/.mission-control" "$HOME/.mission-control/bin/dashboard" collect --force`; browser captures for installed Home/Map/Open work | result: pass; graph suite ALL PASS, dashboard suite PASS=22 FAIL=0, render smoke all 6 tabs, automation ALL PASS, usage snapshot PASS=2 FAIL=0, scan self-test PASS, syntax/json/whitespace checks pass, browser screenshots nonblank at `/tmp/mission-control-p13-home.png`, `/tmp/mission-control-p13-map.png`, `/tmp/mission-control-p13-open-work.png` | log/PR reference: Work Record Log `2026-07-08 — One loose-ends ledger` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | commands: repeated `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; repeated `node scripts/dashboard-render-smoke.js .`; repeated focused `code-review` subagent audits of `dashboard/index.html`, `dashboard/fixtures/usage.json`, and `scripts/dashboard-render-smoke.js` while fixing the audit findings | result: pass; dashboard suite stayed PASS=22 FAIL=0, render smoke stayed green across all 6 tabs, and the separate review passes ended with no material findings left in the changed dashboard bundle | log/PR reference: Work Record Log `2026-07-04 — Dashboard search-audit V1 UI bundle`; Audit Record `2026-07-04 | targeted implementation audit` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | commands: GitHub search API sweep of top 1000 rows for `dashboard coding tracker in:name,description,readme stars:>10`; README/license/metadata deep-read for high-fit candidates; README screenshot/asset-reference reviews for CodeBurn, TokenTracker, CodexBar, AgentsView, abtop, and builderz Mission Control; `git diff --check -- records/2026-07-04-dashboard-coding-tracker-search-audit.md todo.md` | result: pass for source-only audit and docs whitespace check; no runtime code changed | log/PR reference: Work Record Log `2026-07-04 — GitHub dashboard/coding-tracker search audit`; record `records/2026-07-04-dashboard-coding-tracker-search-audit.md` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | commands: `bash scripts/chat-graph.test.sh`; `bash scripts/usage-snapshot.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `bash scripts/automation-status.test.sh`; `bash scripts/scan-unfinished-work --self-test`; `bash -n scripts/dashboard scripts/usage-snapshot scripts/scan-unfinished-work scripts/chat-graph.test.sh scripts/dashboard.test.sh scripts/usage-snapshot.test.sh`; `python3 -m py_compile scripts/chat-graph`; `git diff --check`; token-pattern diff scan; `MISSION_CONTROL_HOME="$HOME/.mission-control" REPO_ROOT="$PWD" bash scripts/dashboard install`; `MISSION_CONTROL_HOME="$HOME/.mission-control" "$HOME/.mission-control/bin/dashboard" collect --force`; browser capture of installed Home | result: pass; chat graph ALL PASS, usage snapshot PASS=2 FAIL=0, dashboard suite PASS=22 FAIL=0, render smoke all 6 tabs, automation ALL PASS, scan self-test PASS, installed Home screenshot nonblank at `/tmp/mission-control-207d88dd-closeout-home.png` | log/PR reference: Work Record Log `2026-07-04 — 207d88dd Cursor patch closeout`; closeout commit 3a612e5 | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | commands: `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `git diff --check`; `MISSION_CONTROL_HOME="$HOME/.mission-control" REPO_ROOT="$PWD" bash scripts/dashboard install`; browser capture of installed Map | result: pass; render smoke proves Map includes newest chat title, dashboard suite PASS=21 FAIL=0, screenshot written to `/tmp/mission-control-map-journal.png` | log/PR reference: Work Record Log `2026-07-04 — Map recent chat journal` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-04 | commands: `bash scripts/chat-graph.test.sh`; `bash scripts/automation-status.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; repo governance validators; browser captures for Home/Map/Chats | result: pass; dashboard suite PASS=21 FAIL=0, render smoke all 6 tabs, governance validators pass after thin-root note fix | log/PR reference: local images `/tmp/mission-control-home-audit.png`, `/tmp/mission-control-map-audit.png`, `/tmp/mission-control-chats-audit.png` | by: Codex | linear: self-contained until Linear is configured.

## Testing Cadence Matrix
| Trigger | Command(s) | Cadence | Gate Criteria |
|---|---|---|---|
| Chat graph logic change | `bash scripts/chat-graph.test.sh` | Per change | Tests pass and export/doctor behavior is covered |
| Automation status or job registry change | `bash scripts/automation-status.test.sh` | Per change | Tests pass and registry states remain honest |
| Dashboard collector/install/status change | `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell` | Per change | Shell, fixtures, status, install, and render smoke pass |
| Dashboard renderer or fixture change | `node scripts/dashboard-render-smoke.js .` | Per change | Every tab renders fixture content; Map builds graph elements |
| Usage snapshot logic change | `bash scripts/usage-snapshot.test.sh` | Per change | Credit notification command handling remains argv-only and advice is delivered as one message |
| Release-sensitive visual/file:// change | browser capture of `~/.mission-control/index.html` or demo output | Per change | Rendered page is nonblank and expected controls are visible |

## Feedback Decision Log
If it's not here, it isn't remembered.
Record outside feedback and the resulting reasoning once, then update the same entry as the decision evolves.
- Each entry should capture:
  - `date`
  - `feedback source`
  - `feedback summary`
  - `evaluation chat`
  - `reasoning response`
  - `decision status` (`accepted`, `partial`, `deferred`, `rejected`, or `superseded`)
  - `implementation/disposition chat`
  - `linked branch / audit / suggestion / test evidence`
  - `by`
  - `linear`
- Reuse or update an existing entry when the same feedback thread comes back instead of opening duplicate records.
- 2026-07-04 | feedback source: Trevor in Codex thread `019f2b73-9811-7392-b511-201c1f109997` | feedback summary: connected-chat view should include a tiny journal/log of what was done and which chat it happened in | evaluation chat: same Codex thread | reasoning response: accepted; implemented from existing chat-feed timestamps/titles instead of adding a new collector | decision status: accepted | implementation/disposition chat: same Codex thread | linked branch / audit / suggestion / test evidence: Work Record `2026-07-04 — Map recent chat journal`; Test Evidence `2026-07-04` | by: Codex | linear: self-contained until Linear is configured.
- 2026-07-05 | feedback source: Trevor pasted a GitHub Copilot third-party-repo recommendation for this repo and asked which suggestions to agree with and which could actually be implemented | feedback summary: Copilot — working only from the repo description, not its contents, which it openly admitted — recommended an enterprise observability + data-warehouse + business-intelligence stack (OpenTelemetry Collector, Prometheus, Grafana, OpenObserve, Superset, Metabase, Airbyte, Meltano, dbt-core, Great Expectations, TensorZero, Helicone, OpenLIT, traceAI, TraceRoot, a Pull Request Analytics GitHub Action, onWatch, ECharts/Chart.js) plus a 4-phase "adopt Collector+Prometheus+Grafana+OpenLIT+dbt" plan | evaluation chat: this session (full adversarial review of pasted AI output) | reasoning response: category error against PROJECT_INTENT. One test disposes of the headline list — does it run as a background service/framework/separate warehouse, or is it a vendorable file the page loads offline? OTel Collector, Prometheus, Grafana, OpenObserve, Superset, Metabase, Airbyte, Meltano, dbt-core, Great Expectations, and TensorZero all fail it and collide with the explicit non-goals (no server, no framework rebuild, single-user, offline/file://). Copilot's Phase-1 (Collector+Prometheus+Grafana) would replace the double-clickable offline file with a multi-service ops stack — a different product, not a heavier version of this one. LLM-observability picks (Helicone/OpenLIT/traceAI/TraceRoot) require SDK/proxy instrumentation that cannot attach to first-party Claude Code/Codex/Cursor and reintroduce the rejected proxy/cookie surface. TensorZero is an LLM gateway/router, violating the passive read-only design. Great Expectations duplicates existing feed-boundary validation + `dashboard-render-smoke` at far heavier scale. What actually transfers is only: (a) the category instinct that token/session/cost observability is the right neighborhood — already better mapped by the 2026-07-04 dashboard-coding-tracker audit; (b) vendor-neutral normalized ingestion — already implemented as feed envelopes; (c) "cost per merged PR"-style metrics — already queued as the V2 yield lens; none require new infrastructure. onWatch was already triaged in the prior audit (GPL, pattern-only); no other Copilot pick improves on that audit's peer set. `leeoniya/uPlot` (tiny zero-dependency MIT canvas charting) is noted only as the right-sized counter-example to Copilot's Chart.js/ECharts/CDN pick if a chart ever earns its place; it still fails this repo's "no new dependency unless it reduces local-operability risk" bar for V1 | decision status: rejected (adopt none of the recommended tools) with partial value captured — category instinct and two ideas already reflected in the ER-089 usage-routing and V2 yield-lens queue | implementation/disposition chat: this session; nothing adopted, installed, or wired | linked branch / audit / suggestion / test evidence: `records/2026-07-04-dashboard-coding-tracker-search-audit.md` (the correct same-niche map); Suggested Recommendation Log 2026-07-05 | by: Claude Code (Opus 4.8) session `a9724039-6595-4205-a25b-bf361020250a` | linear: self-contained until Linear is configured.
