# Lane D state — rollup-answer CLI wiring

- Status: FIFTH-AUDIT REPAIR FOCUSED GREEN / CODE COMMIT + AUTHORITATIVE GATE PENDING; frozen `8b8fa772336239eab812b38e2b152e69dce65a96` was rejected on two reproduced P1s: byte-unbound delivered receipts and a regular file retained at the canonical batch name
- Branch: `codex/rollup-answer-wiring`
- Review base: `53e91392dcef3d2deeedf748c14159320a8572e0`
- Original implementation checkpoint: `754de932301113e81f51bbf4febe2d3fc28c01e0`
- Verifier-hermeticity repair: `ed8ce3591b5fb3070b132b98a062be1125a5f991`
- Independent-audit repair: `34687c9` (`fix(decisions): bind rollup publication to receipts`)
- Second-audit repair: `8613d25` (`fix(decisions): close replay and reader skew gaps`)
- Third-audit repair: `bfaf10b` (`fix(decisions): quarantine visible rollup conflicts`)
- Fourth-audit local-view repair: `0ce6d3d7704a8e305159cdbd78965bd34f1b8a02` (`fix(decisions): reconcile local views after answers`)
- Fifth-audit receipt/entry repair: pending code commit
- Worktree: `/Users/gillettes/Coding Projects/mission-control-worktrees/rollup-answer-wiring`
- Source chat: Codex `019f73d8-e5dc-73a0-acc5-8a4916ac6819`
- Trust Gate: on — durable operator direction and completion semantics
- Canonical change: `openspec/changes/rollup-answer/`
- Executable binding: `hotl-workflow-rollup-answer.md`
- Linear disposition: self-contained / repo-only; no Mission Control Linear team is configured
- Project-memory convention: this repo has no separate `PROJECT_MEMORY.md`; `todo.md` is the declared operational-memory surface
- Live/deploy actions: none

## Approved contract and citation

Trevor approved the following seven points through `thread_goal_updated` at `2026-07-18T14:47:59.770Z` on this source thread (`019f73d8`), with goal text beginning “Yes thoroughly Approve the seven-point answered_pending contract and resume Lane D.”

1. `dashboard decide answer-rollup <card-id> <primary-decision-id> <choice>` plus existing source/resume flags.
2. Target the primary plus only strict action+owner+target equivalents; return independent members untouched and visible.
3. Keep every target `open` with a current-fingerprint `answered_pending` event and private answer/prompt artifacts.
4. Keep pending members locally visible while suppressing ordinary alerts, dismissal, single-answer, and Morning Brief owner-action duplication.
5. Resolve only the exact member for graph-verified answering-turn or downstream-resolution evidence; reject manual resolution while pending.
6. Stage and verify every artifact before one SQLite transaction, then publish one private batch atomically; exact replay recovers a post-commit publication failure.
7. Make exact current scope plus choice idempotent; fail conflicting choice, partial/mismatched pending state, malformed proof, and changed scope closed; changed evidence permits a new answer.

## Current implementation

- `scripts/decision-alert` derives pending from immutable events, replans current scope inside one immediate transaction, verifies private artifact proof, persists the canonical manifest SHA-256 plus exact member/metadata/artifact identity, inserts all target events atomically, and exact-compares every replay field.
- `scripts/compose-decision-prompt.py` validates before paths, creates deterministic rollup bytes, retains pinned descriptors, verifies name-to-fd and member bytes before/after commit and publication, quarantines the exact receipt-bound held artifact on first publication/replay failure, and fd/inode-binds either a directory or regular-file canonical conflict before private quarantine; orphan first-answer conflicts remain untouched.
- `scripts/dashboard` exposes public single/rollup answer commands and treats the strict decisions feed, persisted Morning Brief, and strict public brief feed as one same-`SCRIPT_DIR` success boundary with `DECISION_ALERT_AUTO=0`; committed-but-refresh-failed is nonzero with receipt stdout and explicit degraded stderr.
- Morning Brief omits exactly current pending targets from `NEEDS YOU`; its local-only refresh recomposes not-sent state and accepts delivered state only after a private receipt binds the full delivered Markdown digest, deterministic chunk limit, every ordered chunk digest, and then the exact receipt bytes across replay. It preserves delivered identity/receipt/cursor bytes without resend and refuses to rewrite pending/partial/failed retry content even after local-day rollover. Home and panel show the recorded choice as read-only awaiting owner consumption, with actionable rows stably ordered before pending rows on bounded views.
- `scripts/rollup-answer.test.py` covers 25 temporary-state contracts, including first-write and replay mutation/parent replacement, directory and regular-file occupied canonical names, stale installed decision/brief readers, tampered destination repair, deterministic digest replay, three-surface strict refresh failure, persisted/delivered/in-flight/prior-day Morning Brief behavior, malformed and byte-unbound delivered-receipt rejection, single-answer parity, and fake-sender no-egress proof.

## Audit history and disposition

### Initial ambiguity audit

- Codex `019f7411-b995-76e2-8481-1266b1eebfa8` corroborated that the seven-point contract needed explicit approval before implementation. Disposition: resolved by the cited approval above.

### First implementation audit

- Codex `019f762c-c815-77b3-97c0-021c66fd3b7e`, `gpt-5.6-sol`/max, reviewed `53e91392..daa8c72` and returned `NOT MERGE-READY` with two P1 findings despite a fresh `23/23` verifier run.
- Accepted P1: post-commit stage/parent mutation could diverge from the database receipt because the digest was not persisted and later checks reopened mutable names.
- Accepted P1: the public `sync-snapshot || collect` path could succeed without updating `data/decisions.json`, leaving Home/Morning Brief stale.
- Disposition: both reproduced RED and repaired in `34687c9`; evidence in `records/evidence/rollup-answer-audit-repair-red-green.txt` and `records/evidence/rollup-answer-audit-repair-full-green.txt`.
- Second fresh audit: Codex `019f7680-90ce-7392-a991-5a76a3bae61b`, `gpt-5.6-sol`/max, reviewed frozen `708031f` and returned `NOT MERGE-READY` with two P1s and one P2 despite the same green declared suites.
- Accepted P1: replay-time mutation of an already-published receipt-backed batch failed closed but left the corrupted canonical directory unquarantined because cleanup inferred identity from lifecycle booleans.
- Accepted P1: the source dashboard transaction could write through the branch reader and refresh through a stale executable under the temporary Mission Control home, reporting success with a feed that omitted `answer_pending`.
- Accepted P2: bounded Home/panel prefixes could contain only pending rows while their heading counted a later actionable row as `Needs you`.
- Disposition: all three were independently RED-reproduced and repaired in `8613d25`; exact-head re-audit remains pending after the records-complete full gate.
- Third exact-head audit: the same fresh max-reasoning task reviewed frozen `16a3e516a9566ad5ce929cade29db334e7bfe08f` and returned `NOT MERGE-READY` with one new P1 despite a clean authoritative `23/0` rerun.
- Accepted P1: if the path-visible batch parent was replaced with a new private parent already containing an invalid directory at the deterministic canonical name, failure cleanup preserved the held old-parent artifact but left the unbound current-parent conflict visible until a later replay.
- Disposition: the occupied-parent counterexample was RED-reproduced and repaired in `bfaf10b`; the command now fd-binds and validates the current parent, quarantines only an invalid same-name conflict, preserves the held old-parent object, and leaves valid content untouched. A new frozen-head audit remains pending after the records-complete full gate.
- Fourth fresh audit: `/root/lane_d_final_audit`, `gpt-5.6-sol`/max, reviewed frozen `af083a6` and returned `NOT MERGE-READY` with one P1 and one P2. P1: `answer-rollup` could return zero after updating only decisions while persisted `latest.json` and `data/brief.json` stayed byte-identical/actionable. P2: records still described already-completed evidence steps as pending.
- Disposition: both accepted. The public-command-only counterexample is RED before repair; the same-runtime local reconciliation repair is green across 23 rollup tests, the authoritative 23/0 verifier, Morning Brief, dashboard 67/0, delivered/in-flight/prior-day/missing-receipt/no-send/stale-runtime boundaries, and static checks. Records were reconciled; frozen successor `8b8fa77` then advanced to the fifth audit below.
- Fifth fresh audit: `/root/lane_d_local_view_reaudit`, `gpt-5.6-sol`/max, reviewed frozen `8b8fa77` and returned `NOT MERGE-READY` with two P1s despite the green declared suites. P1: structurally complete 64-hex receipt fields did not bind actual delivered Markdown/chunks. P1: a mode-0600 regular file at the canonical name in a replacement parent survived failure and wedged later replay.
- Disposition: both accepted and independently RED-reproduced. The successor binds full Markdown, chunking, ordered chunks, and exact receipt bytes, and quarantines only exact fd/inode-bound receipt-backed regular-file/directory conflicts. Targeted 3/3, rollup 25/25, and Morning Brief delivery are green; authoritative full gate and fresh successor audit remain pending.

## Evidence

### Historical red/green

- Initial behavior/render RED: `records/evidence/rollup-answer-red.txt`, `records/evidence/rollup-answer-render-red.txt`.
- First focused green: `records/evidence/rollup-answer-focused-green.txt`.
- Rejected verifier false green plus hermeticity repair: `records/evidence/rollup-answer-verifier-artifact-red-green.txt` and `records/2026-07-18-verifier-source-artifact-repair.md`.
- First authoritative committed green: `records/evidence/rollup-answer-full-green.txt` (`ed8ce35`, 23/0).

### Independent-audit repair

| Gate | Result |
|---|---|
| New/strengthened rollup contracts before repair | RED — 5 failures, 2 errors |
| Rollup answer after repair | 14 tests, OK |
| Authoritative verifier | `SUITES PASS=23 FAIL=0` |
| Dashboard browser | 253 assertions |
| Strict OpenSpec | 2 passed, 0 failed |
| Python / macOS Bash 3.2 / source artifacts | pass |
| Provider sender trap | not invoked |

### Second-audit repair focused evidence

| Gate | Result |
|---|---|
| Existing-batch replay mutation and parent replacement before repair | RED — 2 failures |
| Stale installed decision reader before repair | RED — 1 failure |
| Home actionable ordering before repair | RED — 1 render failure |
| Panel actionable ordering before repair | RED — `58 passed, 1 failed` |
| Rollup answer after repair | 17 tests, OK |
| Dashboard render after repair | all 7 tabs pass |
| ER-134 usability after repair | `59 passed, 0 failed` |
| Python / macOS Bash 3.2 / diff checks | pass |

### Third-audit occupied-parent repair focused evidence

| Gate | Result |
|---|---|
| Auditor occupied replacement-parent counterexample | RED — invalid canonical conflict remained visible after nonzero return |
| Added occupied-parent regression before repair | RED — canonical conflict still existed |
| Added occupied-parent regression after repair | 1 test, OK |
| Rollup answer after repair | 18 tests, OK |
| Pending-event cardinality and later exact rebuild | one per target; exact digest rebuilt |

### Records-complete authoritative gate

| Gate | Result |
|---|---|
| Exact committed head | `bc9014d686c477fe674987072f1ef8a5f4a96718` |
| Rollup answer | 18 tests in 29.520s, OK |
| Dashboard / ER-134 / usage | `67/0`; `59/0`; `24/0` |
| Dashboard browser | 253 assertions |
| Strict OpenSpec | 2 passed, 0 failed |
| Python / shell / source artifacts | pass |
| Authoritative verifier | `SUITES PASS=23 FAIL=0` |

### Fourth-audit persisted Morning Brief repair

| Gate | Result |
|---|---|
| Public command against pre-existing persisted brief before repair | RED — `latest.json` and `data/brief.json` remained unchanged after exit zero |
| Not-sent, delivered, in-flight/prior-day, missing-receipt, single-answer, and stale-runtime/no-send boundaries | pass |
| Rollup answer after repair | 23 tests in 30.549s, OK (final pre-commit rerun) |
| Morning Brief | all pass |
| Dashboard | `67/0` |
| ER-134 usability | `59/0` after aligning its partial install fixture with the required Morning Brief runtime |
| Python / macOS Bash 3.2 / diff checks | pass |
| Exact committed repair head | `0ce6d3d7704a8e305159cdbd78965bd34f1b8a02` |
| Post-repair authoritative verifier | `SUITES PASS=23 FAIL=0` |
| Full-gate rollup / dashboard / ER-134 / usage | `23/23`; `67/0`; `59/0`; `24/0` |
| Browser / strict OpenSpec / artifact predicate | `253`; `2/0`; pass |

### Fifth-audit receipt/entry repair focused evidence

| Gate | Result |
|---|---|
| Structurally valid but byte-unbound delivered receipt before repair | RED — public answer unexpectedly succeeded and rewrote local brief |
| Replacement-parent regular-file canonical conflict before repair | RED — mode-0600 canonical file remained after nonzero return |
| Exact counterexamples after repair | 3 targeted tests, OK |
| Rollup answer after repair | 25 tests in 35.034s, OK |
| Morning Brief delivery | all pass, including retry/concurrency/content binding |
| Authoritative verifier / fresh successor audit | pending after code commit |

Receipts:

- `records/evidence/rollup-answer-audit-repair-red-green.txt`
- `records/evidence/rollup-answer-audit-repair-full-green.txt`
- `records/evidence/rollup-answer-final-audit-red-green.txt`
- `records/evidence/rollup-answer-occupied-parent-red-green.txt`
- `records/evidence/rollup-answer-occupied-parent-full-green.txt`
- `records/evidence/rollup-answer-morning-brief-coherence-red-green.txt`
- `records/evidence/rollup-answer-morning-brief-coherence-full-green.txt`
- `records/evidence/rollup-answer-receipt-entry-red-green.txt`
- `records/rollup-answer-independent-codex-audit.md`
- `records/2026-07-18-rollup-answer-work-record.md`

## Claims and limits

- Confirmed: both first-audit P1 findings, all three second-audit findings, the third-audit occupied-parent P1, the fourth-audit persisted-view P1, and both fifth-audit P1s were independently reproduced and have behavior-level regressions.
- Confirmed: repair `bfaf10b` passed the targeted occupied-parent contract and 18/18 rollup contracts; exact records-complete `bc9014d` passed the historical authoritative `23/0` verifier. Fourth repair `0ce6d3d` passes the replacement authoritative `23/0` verifier, including rollup 23/23, dashboard 67/0, ER-134 59/0, usage 24/0, browser 253, OpenSpec 2/0, and the final source-artifact predicate.
- Confirmed: no schema migration, dependency, live-store write, provider send, main touch, install, deploy, release, plist, or launchd action occurred.
- Did not verify: the fifth repair's authoritative full gate or final independent verdict.
- Did not verify: hosted PR checks or merge state; no Lane D PR exists yet.
- Did not verify: merged-main, installed runtime, provider delivery, or live-store behavior because those actions are prohibited here.
- Do not do: merge, install, deploy, send, write a live store, change plist/launchd, or resolve live decision `decision:a6f185b53cbc1278499b062d` from this lane.
- Merge-sitting note: the still-open/alerting live card `decision:a6f185b53cbc1278499b062d` should be resolved by the integrator at the merge sitting, not by this branch task.

## Exact resume

1. Commit the fifth-audit code/spec/test repair, run the authoritative verifier at that exact commit, commit its receipt, and freeze the successor.
2. Send the exact frozen successor to a new fresh `gpt-5.6-sol`/max auditor; on review-clean, append the verdict, push, open the review-ready PR with the approval citation and live-card merge-sitting note, verify hosted checks, and stop before merge/deploy.
