# Lane D state — rollup-answer CLI wiring

- Status: ACTIVE; independent-audit repairs are focused/full-green; final fresh audit and PR remain
- Branch: `codex/rollup-answer-wiring`
- Review base: `53e91392dcef3d2deeedf748c14159320a8572e0`
- Original implementation checkpoint: `754de932301113e81f51bbf4febe2d3fc28c01e0`
- Verifier-hermeticity repair: `ed8ce3591b5fb3070b132b98a062be1125a5f991`
- Independent-audit repair: `34687c9` (`fix(decisions): bind rollup publication to receipts`)
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
- `scripts/compose-decision-prompt.py` validates before paths, creates deterministic rollup bytes, retains a pinned batch fd, verifies name-to-fd and member bytes before/after commit and after publication, quarantines invalid post-commit material, and reconstructs the persisted digest on exact replay.
- `scripts/dashboard` exposes public single/rollup answer commands and runs the strict decisions collector with `DECISION_ALERT_AUTO=0`; committed-but-refresh-failed is nonzero with structured stdout and explicit degraded stderr.
- Morning Brief omits exactly current pending targets from `NEEDS YOU`; Home and panel show the recorded choice as read-only awaiting owner consumption.
- `scripts/rollup-answer.test.py` covers the contract in temporary state, including post-commit mutation/parent replacement, tampered destination repair, deterministic digest replay, strict feed failure, Morning Brief coherence, and fake-sender no-egress proof.

## Audit history and disposition

### Initial ambiguity audit

- Codex `019f7411-b995-76e2-8481-1266b1eebfa8` corroborated that the seven-point contract needed explicit approval before implementation. Disposition: resolved by the cited approval above.

### First implementation audit

- Codex `019f762c-c815-77b3-97c0-021c66fd3b7e`, `gpt-5.6-sol`/max, reviewed `53e91392..daa8c72` and returned `NOT MERGE-READY` with two P1 findings despite a fresh `23/23` verifier run.
- Accepted P1: post-commit stage/parent mutation could diverge from the database receipt because the digest was not persisted and later checks reopened mutable names.
- Accepted P1: the public `sync-snapshot || collect` path could succeed without updating `data/decisions.json`, leaving Home/Morning Brief stale.
- Disposition: both reproduced RED and repaired in `34687c9`; evidence in `records/evidence/rollup-answer-audit-repair-red-green.txt` and `records/evidence/rollup-answer-audit-repair-full-green.txt`.
- Final repaired-head audit: pending in a new same-model/max task.

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

Receipts:

- `records/evidence/rollup-answer-audit-repair-red-green.txt`
- `records/evidence/rollup-answer-audit-repair-full-green.txt`
- `records/rollup-answer-independent-codex-audit.md`
- `records/2026-07-18-rollup-answer-work-record.md`

## Claims and limits

- Confirmed: both first-audit P1 findings were independently reproduced and have behavior-level regressions.
- Confirmed: the repair candidate passed the authoritative 23-suite matrix and left no source bytecode.
- Confirmed: no schema migration, dependency, live-store write, provider send, main touch, install, deploy, release, plist, or launchd action occurred.
- Did not verify: final repaired-head independent verdict.
- Did not verify: hosted PR checks or merge state; no Lane D PR exists yet.
- Did not verify: merged-main, installed runtime, provider delivery, or live-store behavior because those actions are prohibited here.
- Do not do: merge, install, deploy, send, write a live store, change plist/launchd, or resolve live decision `decision:a6f185b53cbc1278499b062d` from this lane.
- Merge-sitting note: the still-open/alerting live card `decision:a6f185b53cbc1278499b062d` should be resolved by the integrator at the merge sitting, not by this branch task.

## Exact resume

1. Commit the records/spec/state update and rerun strict OpenSpec plus the authoritative verifier on the exact committed head.
2. Create a new `gpt-5.6-sol`/max audit task against that frozen SHA; repair any accepted finding under the two-attempt rule and rerun affected/full gates.
3. Append the final audit receipt, push the topic branch, open a review-ready PR whose body carries the approval citation and live-card merge-sitting note, verify hosted checks, and stop before merge/deploy.
