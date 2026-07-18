# Lane D state — rollup-answer CLI wiring

- Status: AUTHORITATIVE FULL GREEN / FRESH EXACT-HEAD AUDIT PENDING at `bc9014d686c477fe674987072f1ef8a5f4a96718`; occupied-parent repair is 18/18 and the records-complete verifier is `SUITES PASS=23 FAIL=0`; audit, push, and PR remain
- Branch: `codex/rollup-answer-wiring`
- Review base: `53e91392dcef3d2deeedf748c14159320a8572e0`
- Original implementation checkpoint: `754de932301113e81f51bbf4febe2d3fc28c01e0`
- Verifier-hermeticity repair: `ed8ce3591b5fb3070b132b98a062be1125a5f991`
- Independent-audit repair: `34687c9` (`fix(decisions): bind rollup publication to receipts`)
- Second-audit repair: `8613d25` (`fix(decisions): close replay and reader skew gaps`)
- Third-audit repair: `bfaf10b` (`fix(decisions): quarantine visible rollup conflicts`)
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
- `scripts/compose-decision-prompt.py` validates before paths, creates deterministic rollup bytes, retains a pinned batch fd, verifies name-to-fd and member bytes before/after commit and after publication, quarantines the exact receipt-bound held artifact on both first publication and existing-batch replay failure, and separately invalidates an unverified same-name conflict in a replacement path-visible parent.
- `scripts/dashboard` exposes public single/rollup answer commands and runs the strict decisions collector from the same `SCRIPT_DIR` runtime as the transaction writer with `DECISION_ALERT_AUTO=0`; committed-but-refresh-failed is nonzero with structured stdout and explicit degraded stderr.
- Morning Brief omits exactly current pending targets from `NEEDS YOU`; Home and panel show the recorded choice as read-only awaiting owner consumption, with actionable rows stably ordered before pending rows on bounded views.
- `scripts/rollup-answer.test.py` covers 18 temporary-state contracts, including first-write and replay mutation/parent replacement, an already-occupied replacement parent, stale installed-reader skew, tampered destination repair, deterministic digest replay, strict feed failure, Morning Brief coherence, and fake-sender no-egress proof.

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

Receipts:

- `records/evidence/rollup-answer-audit-repair-red-green.txt`
- `records/evidence/rollup-answer-audit-repair-full-green.txt`
- `records/evidence/rollup-answer-final-audit-red-green.txt`
- `records/evidence/rollup-answer-occupied-parent-red-green.txt`
- `records/evidence/rollup-answer-occupied-parent-full-green.txt`
- `records/rollup-answer-independent-codex-audit.md`
- `records/2026-07-18-rollup-answer-work-record.md`

## Claims and limits

- Confirmed: both first-audit P1 findings, all three second-audit findings, and the third-audit occupied-parent P1 were independently reproduced and have behavior-level regressions.
- Confirmed: repair `bfaf10b` passed the targeted occupied-parent contract and 18/18 rollup contracts; exact records-complete `bc9014d` then passed the authoritative `23/0` verifier, and the prior `8613d25` renderer/runtime repairs remain covered.
- Confirmed: no schema migration, dependency, live-store write, provider send, main touch, install, deploy, release, plist, or launchd action occurred.
- Did not verify: final `bfaf10b`-descended independent verdict.
- Did not verify: hosted PR checks or merge state; no Lane D PR exists yet.
- Did not verify: merged-main, installed runtime, provider delivery, or live-store behavior because those actions are prohibited here.
- Do not do: merge, install, deploy, send, write a live store, change plist/launchd, or resolve live decision `decision:a6f185b53cbc1278499b062d` from this lane.
- Merge-sitting note: the still-open/alerting live card `decision:a6f185b53cbc1278499b062d` should be resolved by the integrator at the merge sitting, not by this branch task.

## Exact resume

1. Commit this records-complete full-gate receipt and send the exact successor SHA to a new fresh `gpt-5.6-sol`/max auditor.
2. Repair any accepted new finding under the two-attempt rule and rerun affected/full gates.
3. Append the final audit receipt, push the topic branch, open a review-ready PR whose body carries the approval citation and live-card merge-sitting note, verify hosted checks, and stop before merge/deploy.
