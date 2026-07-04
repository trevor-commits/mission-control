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
- ER-089 usage-aware autonomous routing (high): design and implement provider-usage adapters only where safe credentials/sources exist, then expose the routing signal in Mission Control without inventing missing provider percentages. Blocker: Trevor-held provider auth for z.ai/OpenAI/GitHub if live usage is required. | owner: next Mission Control routing session | linear: self-contained until Linear is configured.
- ER-090 autonomous coding-hygiene loop (high): design the coordinator that consumes Mission Control feeds and raises glaring decisions for dirty work, branches, and fixable problems without unsafe auto-merge/push behavior. Build only after the boundary/aggressiveness decision is recorded. | owner: next Mission Control autonomy session | linear: self-contained until Linear is configured.

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
- 2026-07-04 | 207d88dd Cursor patch closeout — completed the dirty audit-fix patch with focused regressions and installed-browser proof; landed as PENDING-SHA; full record below.
- 2026-07-04 | Map recent chat journal — added a five-line recent-chat recap to the Connection map; full record below.
- 2026-07-04 | ER-087 follow-up audit gaps — governance scaffold, product intent, tab wording, stale-ingest honesty, and Map smoke coverage landed in this change; full record below.

## Work Record Log
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
- 2026-07-04 | recommendation: pattern-mine `tabler/tabler` during the next Mission Control UI polish pass, especially cards, dense tables, badges, tabs, segmented controls, and offline-safe icon affordances; do not install `@tabler/core` wholesale unless a later implementation proves the static file:// bundle stays simpler and safer. | why: Tabler is a mature MIT Bootstrap dashboard kit, but this repo's product intent is still a single-file local/offline dashboard. | by: Codex thread `019f2d4e-54ba-7273-8188-12506a3daf19`; source card: third-party index `researched-repos/tabler-tabler.md` commit `171a122`. | linear: self-contained until Linear is configured.

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
- 2026-07-04 | cross-chat implementation closeout | scope: Cursor chat `207d88dd-4abf-4328-a66a-aa55a8801d21` dirty audit-fix patch, regression coverage, durable records, installed runtime, and browser proof | repo fingerprint: `main` at `31ee124` plus eight task-edited files before closeout commit | prior audit reference: `2026-07-04 | cross-chat implementation audit` / commit `31ee124` | source/work chat: Cursor `207d88dd-4abf-4328-a66a-aa55a8801d21` (`Scan this repo for bugs...`) | audit/implementation chat: Codex `019f2ddb-4d45-79b2-9ed7-da8303fb3439` | separate follow-up audit: no; closeout included self-audit and installed-browser proof | commands/evidence: `bash scripts/chat-graph.test.sh`; `bash scripts/usage-snapshot.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `bash scripts/automation-status.test.sh`; `bash scripts/scan-unfinished-work --self-test`; `bash -n ...`; `python3 -m py_compile scripts/chat-graph`; `git diff --check`; token-pattern diff scan; installed collect; browser capture | tested: stale ingest lock recovery, `ingest_skipped` export/status/Home surfacing, dashboard env override shell rejection, usage notification argv/rejection behavior, normalized usage status strip, yellow automation surfacing, scoped Map edge rendering, scan TSV parsing, installed file:// Home render | not tested: launchd over future intervals, provider-side live usage APIs beyond current local snapshot | findings opened or updated: closed Active Next Steps `207d88dd Cursor patch closeout` | fixes closed/verified: dirty/unpushed patch landed with records; missing regression coverage closed; command-execution hardening verified; installed runtime rendered | declined/deferred findings: provider usage adapters and autonomous hygiene loop stay deferred as ER-089/ER-090 product-scope work | better-path challenge: do not accept cross-chat implementation summaries as complete without commit/push, durable records, regression tests, and installed/runtime evidence when UI changes are release-sensitive | references: screenshot `/tmp/mission-control-207d88dd-closeout-home.png`; transcript `/Users/gillettes/.cursor/projects/Users-gillettes-Coding-Projects-mission-control/agent-transcripts/207d88dd-4abf-4328-a66a-aa55a8801d21/207d88dd-4abf-4328-a66a-aa55a8801d21.jsonl`; closeout commit PENDING-SHA | by: Codex | linear: self-contained until Linear is configured.
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
- 2026-07-04 | commands: `bash scripts/chat-graph.test.sh`; `bash scripts/usage-snapshot.test.sh`; `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell`; `node --check scripts/dashboard-render-smoke.js && node scripts/dashboard-render-smoke.js .`; `bash scripts/automation-status.test.sh`; `bash scripts/scan-unfinished-work --self-test`; `bash -n scripts/dashboard scripts/usage-snapshot scripts/scan-unfinished-work scripts/chat-graph.test.sh scripts/dashboard.test.sh scripts/usage-snapshot.test.sh`; `python3 -m py_compile scripts/chat-graph`; `git diff --check`; token-pattern diff scan; `MISSION_CONTROL_HOME="$HOME/.mission-control" REPO_ROOT="$PWD" bash scripts/dashboard install`; `MISSION_CONTROL_HOME="$HOME/.mission-control" "$HOME/.mission-control/bin/dashboard" collect --force`; browser capture of installed Home | result: pass; chat graph ALL PASS, usage snapshot PASS=2 FAIL=0, dashboard suite PASS=22 FAIL=0, render smoke all 6 tabs, automation ALL PASS, scan self-test PASS, installed Home screenshot nonblank at `/tmp/mission-control-207d88dd-closeout-home.png` | log/PR reference: Work Record Log `2026-07-04 — 207d88dd Cursor patch closeout`; closeout commit PENDING-SHA | by: Codex | linear: self-contained until Linear is configured.
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
