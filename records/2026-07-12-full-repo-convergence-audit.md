# Full-repo convergence audit

Date: 2026-07-12
Status: immutable candidate `b79d91d` is full-suite green and independently `REVIEW-CLEAN`; merge/install closeout pending
Audit branch: `codex/full-repo-audit-20260712`
Audit worktree: `/Users/gillettes/Coding Projects/mission-control-worktrees/full-repo-audit-20260712`
Merge target/base inspected: `origin/main` at `659b8d218cb57044506f949d0a3fd47de921eb42`
Source thread: Codex `019f59f8-bb9e-70c0-9497-a9686ea24154`

## Audited Chat

### Primary product/orchestration audit

- Audited chat name: `Audit: Mission Control orchestration priorities`
- Audited chat repo/cwd: `global-implementations` / `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Codex
- Full ID: `019f4963-1e75-7600-8a17-1e6f6f8e8ca6`
- Transcript/resolved path: `/Users/gillettes/.codex/sessions/2026/07/09/rollout-2026-07-09T17-17-40-019f4963-1e75-7600-8a17-1e6f6f8e8ca6.jsonl`

### Final-gate orchestration audit

- Audited chat name: `Audit: Review Orchestration tools`
- Audited chat repo/cwd: `global-implementations` / `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Codex
- Full ID: `019f4f6c-e506-7551-876e-d9bb31f56c36`
- Transcript/resolved path: `/Users/gillettes/.codex/sessions/2026/07/10/rollout-2026-07-10T21-26-04-019f4f6c-e506-7551-876e-d9bb31f56c36.jsonl`

### Round-eight Mission Control worker

- Audited chat name: `worker:e85411a1 - morning-brief fix round 8 (installer fail-closed)` (resolved title begins with the spawn-binding packet)
- Audited chat repo/cwd: `mission-control` / `/Users/gillettes/Coding Projects/mission-control`
- Provider: Codex
- Full ID: `019f5056-bc55-7043-88ad-b87b1ac48a6f`
- Transcript/resolved path: `/Users/gillettes/.codex/sessions/2026/07/11/rollout-2026-07-11T01-41-29-019f5056-bc55-7043-88ad-b87b1ac48a6f.jsonl`

### Live portfolio orchestrator with Mission Control work

- Audited chat name: `Build autonomous orchestration`
- Audited chat repo/cwd: `global-implementations` / `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Codex
- Full ID: `019f51c1-5817-7872-a6ce-8b65428277ed`
- Transcript/resolved path: `/Users/gillettes/.codex/sessions/2026/07/11/rollout-2026-07-11T08-17-34-019f51c1-5817-7872-a6ce-8b65428277ed.jsonl`
- Audit boundary: its Mission Control commits and promises were reconciled; the still-running chat had moved to a separate `mac-health` lane, so this audit did not wait for unrelated portfolio work.

### Original product-direction review

- Audited chat name: `*Chat connection tracking tool`
- Audited chat repo/cwd: `global-implementations` / `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Claude Code
- Full ID: `1ef98716-30bb-4530-80e0-6b2f3fa74f79`
- Transcript/resolved path: `/Users/gillettes/.claude/projects/-Users-gillettes-Coding-Projects-global-implementations/1ef98716-30bb-4530-80e0-6b2f3fa74f79.jsonl`

### Round-eight governing chat

- Audited chat name: `*Venting my thoughts`
- Audited chat repo/cwd: `global-implementations` / `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Claude Code
- Full ID: `e85411a1-b74b-4556-9939-8eaf5d8f2ea9`
- Transcript/resolved path: `/Users/gillettes/.claude/projects/-Users-gillettes-Coding-Projects-global-implementations/e85411a1-b74b-4556-9939-8eaf5d8f2ea9.jsonl`

The exact source metadata above was resolved with `chat-source describe`; final visible claims were checked with `chat-source latest-exchange`. Titles are navigation labels only. IDs, paths, and current Git state are the source of truth.

## Session and branch reconciliation

| Source | Unique request or claim | Current disposition |
|---|---|---|
| `019f4963` | Deterministic/Tier-1 and bounded Tier-2 Morning Brief, repeated audit, no-provider install, and honest external gates | Implemented and already contained by `main`; this audit retained the explicit natural-morning and provider-calibration gates. |
| `019f4f6c` | Immutable Morning Brief final gate, notification consolidation, Outcome Extractor activation discipline, and a separately scoped automatic executor | Final-gate code is contained by `main`; consolidation decisions were recovered from the dirty ER-103 checkout; the automatic executor remains a separate portfolio/global capability, not missing code in this repo. |
| `019f5056` | Fail-closed installer, full-ingest evidence honesty, branch-history/provenance corrections, and at-least-once wording | Later `main` contains the implementation and records; current tests preserve those invariants. |
| `019f51c1` | Chat truth-layer cache/timeout/process cleanup plus desktop-first follow-through | `origin/main` contains the chat-truth repair and desktop-first PR; later activity is in `mac-health`, not an unfinished Mission Control mutation. |
| `1ef98716` | Plain-language Home/Map/Chats product direction and connected-chat journal | Implemented in the current UI and renderer tests; no unlanded repo branch remains for this feedback. |
| ER-103 Cursor lane | Git lifecycle metadata, proof harvester, notification collision analysis, and Trevor's three morning-surface decisions | Commits `7202ab2` and `0a609f8` are patch-contained in this audit branch. Valid uncommitted decision/model changes from the preserved source checkout were integrated without mutating that checkout. |

Fresh topology proof found only two branches with commits not ancestrally reachable from the candidate: `codex/er103-git-state-and-morning-proof` and `er134-morning-brief-desktop-cta-202607122313`. `git cherry` marked every one of their commits with `-`, proving patch-equivalent containment. There is no known unique uncontained implementation commit in the local or `origin/*` branch set.

## Findings and repairs

| Severity | Reproduced finding | Durable disposition |
|---|---|---|
| P1 | Decision-answer writers could split prompt, answer JSON, and decision history | Per-decision advisory lock spans the whole transaction; state is rechecked under lock; concurrent regression requires exactly one coherent winner. |
| P1 | Caller-controlled `MC_DECISION_ANSWER_LOCK_HELD=1` bypassed the first lock repair | Removed environment trust. The lock is now an inherited, inode-verified file descriptor; the regression deliberately sets the old marker on both writers. |
| P1 | A blocked answer-sidecar path failed after database resolution, leaving a prompt plus unretryable resolved decision but no answer receipt | Both filesystem artifacts are now preflighted and staged before resolution, then atomically published. Exact-choice replay recognizes a matching manual resolution and repairs a crash between database resolution and artifact publication. The regression covers both blocked-first-attempt and post-resolution recovery. |
| P1 | Symlinked `answers/` or `prompts/` parent directories redirected private transaction artifacts outside the Mission Control state root | State home plus both transaction parents are now `lstat`-validated as real directories before chmod, lock, or staging. Regressions cover both linked parents, unchanged external sentinels, no outside artifact, and an open decision after refusal. |
| P1 | An attacker or concurrent process could rename and replace a previously validated `answers/` or `prompts/` directory between validation and publication | The complete answer transaction now runs in one Python process with `O_DIRECTORY|O_NOFOLLOW` directory descriptors and the advisory-lock descriptor held throughout. Stage writes and atomic replacements are relative to pinned descriptors; inode bindings are revalidated immediately before database resolution and again before publication. The deterministic rename/swap regression covers both directories and proves open state, no redirected output, and no surviving stage files. |
| P1 | Proof harvesting replaced Trevor-owned read/understood/notes fields | Machine columns merge into existing rows while the three operator columns remain unchanged. |
| P1 | Proof rows broke on Markdown delimiters and could lose parseability | Escaped-cell parser/writer covers pipes, backslashes, and line breaks. |
| P1 | Proof harvesting copied private `latest.md` prose into a tracked record | Raw brief prose is never read or copied; only bounded receipt state, counts, timestamps, section count, and validated digest are retained. Malicious ID/state/prose fixtures are rejected or excluded. |
| P1 | Lifecycle-only scanner findings returned `findings_total: 0` and exit zero | Human and JSON modes now share the privacy-screened facts packet; lifecycle decision rows affect the final total and exit status. |
| P1 | A clean local-only `main` was falsely unexplained because no remote default existed | No-remote repos infer an existing protected `main`/`master` locally; configured remotes with unknown HEAD remain fail-closed. |
| P1 | App staging followed attacker-preseeded binary/plist/app-directory symlinks | Runtime roots and every app ancestor are link-refusing; binary/plist deployment is atomic; deployed binary hash is checked. Three external-target regressions pass. |
| P1 | Installed/runtime path and asset attestation omitted panel/composer surfaces | Canonical runtime and asset sets include the panel source, composer, panel HTML, launchd template, and vendor asset; tampering fails verification. |
| P1 | Feeder writes and decisions collection could interleave/crash or trust future timestamps | Kernel locks, healthy sidecars, and future-date recollection regressions now cover these paths. |
| P1 | Chat graph and Outcome Extractor locks could trust a reused PID | Process-start identity is recorded and compared before stale lock recovery. |
| P1 | Native Swift decision bridge blocked the main thread | The process bridge is asynchronous and covered by source/compile checks. |
| P1 | Browser/privacy fixtures drifted from shared sanitization policy | Browser fixtures use the shared privacy packet and adversarial cases. |
| P2 | Mobile tables/nav, active-tab visibility, copy feedback, strip target size, and light/dark contrast were incomplete | Source and real-browser assertions cover desktop/mobile overflow, active nav, clipboard failure truth, named controls, target tolerance, and WCAG color ratios. |
| P2 | Decision UI inferred question/options only from prose | Producer carries structured `question`, `options`, and `recommended`; UI prefers those fields and retains bounded fallback parsing. |
| P2 | Authoritative verifier omitted the proof harvester | `verify.sh` runs the self-test and compiles the script in memory. |
| P2 | Audit branch itself lacked lifecycle metadata | Full Active Branch Ledger entry added with owner, purpose, exit conditions, evidence record, and cleanup command. |
| P3 | Strict browser target comparison flaked at `43.999969px` for a CSS `44px` minimum | A `0.01px` rendering tolerance preserves the 44px contract; repeated browser gate passes. |
| P3 | `NSUserNotification` is deprecated | Accepted compatibility debt with an explicit SDK/removal/live-failure/permission-redesign revisit trigger in `todo.md`; migration now would introduce a new notification-permission flow without fixing current behavior. |

## Verification ledger

Focused repaired-candidate evidence before the immutable full run:

- `scripts/harvest-morning-brief-proof --self-test` — PASS, including human-field preservation, escaped operator note, private-prose exclusion, and invalid receipt rejection.
- `scripts/scan-unfinished-work --self-test` — PASS, including clean no-remote default and lifecycle-only nonzero exit.
- `scripts/dashboard.test.sh` — `PASS=65 FAIL=0`, including 12 concurrent answer races with the forged legacy marker, blocked-sidecar no-resolution proof, successful retry, exact-choice post-resolution recovery, linked-parent refusal, and live rename/replacement of both artifact roots after staging.
- `scripts/er134-usability.test.sh` — `50 passed, 0 failed`, including three app-bundle symlink counterexamples.
- `node scripts/dashboard-browser.test.js` — `253 assertions passed` across installed/demo desktop and mobile surfaces.
- `git diff --check` and Bash syntax — PASS.

The superseded `df7ab2c`, `f67e079`, and `051bfe1` candidates each completed the authoritative matrix with `SUITES PASS=21 FAIL=0`, but independent review then found, respectively, the blocked-sidecar, linked-parent, and directory rename/swap P1s above. Those green runs are retained as suite evidence, not accepted as final verdicts.

Final immutable pre-merge evidence at `b79d91d`:

- `/bin/bash scripts/verify.sh` — `SUITES PASS=21 FAIL=0`; full log `/tmp/mission-control-b79d91d-verify.log`.
- Dashboard shell/integration suite — `PASS=65 FAIL=0`.
- ER-134 decision/panel suite — `50 passed, 0 failed`.
- Installed/demo Playwright browser gate — `253 assertions passed`.
- OpenSpec strict validation, Python syntax, shell syntax, scanner self-test, privacy, graph, delivery, deadman, extractor, usage, and all remaining authoritative suites — PASS.
- Independent UX/test challenger `/root/worker_019f59f8_tests_ux` reviewed the exact immutable source after four finding/repair cycles and returned `REVIEW-CLEAN` on `b79d91d`.

Merge/install/push proof and final live state are appended in the closeout commit after those state moves occur.

## Honest residual gates

These are not unimplemented repo defects and must not be papered over with synthetic evidence:

1. The proof log contains three natural delivered mornings (July 10–12), not five, and Trevor's read/understood fields remain blank until he supplies them.
2. Outcome Extractor needs a separately authorized privacy-screened live provider calibration before activation. Offline code/tests are complete. The prematurely registered zero-run label was unloaded and its byte-identical plist moved to `/Users/gillettes/Library/LaunchAgents/com.gillettes.outcome-extractor.plist.pending-calibration-20260713` (SHA-256 `e5e561f72e86bbc2cfcb0c00c10deab60ff5522d31d56e6fbd6a04337eb294d9`); the canonical plist is absent and the label is not loaded. Rollback after an approved calibration: move it back to `com.gillettes.outcome-extractor.plist`, validate with `plutil`, then bootstrap the label.
3. Provider delivery is intentionally at-least-once. Provider acceptance followed by a local crash before receipt persistence remains an explicit ambiguity; the queued reconciliation state machine is not falsely claimed here.
4. The portfolio automatic work executor is a separately scoped global capability with broader authority and safety design. It is not silently pulled into this repo audit.

## Self-audit and Ripple Check

- Method: compared live `origin/main`, every local/origin branch tip, patch containment, the preserved dirty ER-103 checkout, exact resolved session metadata/latest exchanges, durable Work/Audit/Test logs, runtime code, installed-state contracts, and independent counterexample reports.
- Outcome so far: every reproduced code, privacy, UI, test, and repo-governance defect has an implementation or explicit accepted-debt disposition plus a focused regression. The final immutable candidate passed the entire authoritative matrix and the independent challenger returned `REVIEW-CLEAN`; only merge, canonical installation, and live-state proof remain.
- Did not verify yet: five elapsed mornings, Trevor comprehension, or provider calibration, because those require time or explicit external authorization; no live provider send was performed.
- Ripple Check: reviewed `PROJECT_INTENT.md`, `AGENTS.project.md`, `CONTINUITY.md`, `COHERENCE.md`, `LINEAR.md`, root `todo.md`, current OpenSpec state, dashboard feed consumers, install/stamp sets, and the morning-surface collision record. The product remains local/offline, repo-only for Linear, and external-provider gated.
- Better-path challenge: fixed truth and deployment boundaries at their producers and authoritative verifier rather than adding another parallel audit harness or weakening fail-closed gates.

by: Codex thread `019f59f8-bb9e-70c0-9497-a9686ea24154`, with independent architecture/security and UX/test challengers.
linear: self-contained under the repo-only contract in `LINEAR.md`.
