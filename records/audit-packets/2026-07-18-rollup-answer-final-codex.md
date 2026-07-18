# Goal

Independently audit the repaired Phase 0 Lane D `answered_pending` rollup-answer implementation at its frozen committed head and determine whether it is merge-ready without trusting prior audits, implementation summaries, or receipts.

Runner: Codex
Model: `gpt-5.6-sol`
Reasoning: `max`

## Frozen target

- Worktree: `/Users/gillettes/Coding Projects/mission-control-worktrees/rollup-answer-wiring`.
- Branch: `codex/rollup-answer-wiring`.
- Review base: `53e91392dcef3d2deeedf748c14159320a8572e0`.
- Record the exact full `HEAD`, local/remote status, and `BASE..HEAD` diff before conclusions. Do not review a moving tree.
- Canonical requirements: `openspec/changes/rollup-answer/`, `hotl-workflow-rollup-answer.md`, `STATE.md`, and `records/2026-07-18-rollup-answer-work-record.md`.

## Prior findings to re-prove

The first audit (`019f762c-c815-77b3-97c0-021c66fd3b7e`) rejected `daa8c72` on two P1s. Treat both as adversarial hypotheses and independently test the repair:

1. Post-commit stage/parent mutation must never publish or report bytes/path divergent from the SQLite receipt. The canonical manifest digest and complete replay identity must be persisted; verification must stay bound to held bytes; suspect material must be quarantined; exact replay must deterministically recover without duplicate events.
2. Public `dashboard decide answer[-rollup]` success must include a current `data/decisions.json` feed for Home/Morning Brief. Collection must be strict with `DECISION_ALERT_AUTO=0`; failure after commit must be loud/structured and must not invoke a provider sender.

The fresh audit in task `019f7680-90ce-7392-a991-5a76a3bae61b` then rejected frozen `708031f` on three additional boundaries. The exact repaired-head re-audit must independently re-prove all three:

3. Mutation or parent replacement during replay of an already-published receipt-backed batch must quarantine the exact held artifact, remove invalid canonical visibility, preserve pinned-parent behavior, and recover without duplicate events.
4. A source transaction must not refresh through a stale executable reader under the Mission Control state home; writer and strict collector must share one runtime identity or fail closed.
5. Bounded Home/panel `Needs you` views must stably surface later actionable rows before answered-pending receipts.

## Required review

1. Read repo governance before conclusions. Audit only: no file edits, stage/commit/push/PR mutation, merge, install, deploy, release, live-store write, provider send, plist, or launchd action.
2. Inspect the full source/test/spec/record diff and `git diff --check`. Verify all seven approved semantics plus all five accepted findings across both prior audits against actual code paths.
3. Adversarially examine descriptor/name binding, mutation windows before/after commit/rename, deterministic bytes, persisted digest and metadata completeness, replay against tampered/orphaned/current batches, quarantine safety, parent replacement, SQLite rollback/locking, partial pending sets, strict collector errors, Morning Brief exact-target suppression, and no-send proof.
4. Rerun at minimum:
   - `PYTHONDONTWRITEBYTECODE=1 python3 scripts/rollup-answer.test.py`
   - `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh`
   - `openspec validate rollup-answer --strict`
   - Python and macOS Bash 3.2 syntax, source-artifact predicate, and `git diff --check`.
5. Verify the approval citation: `thread_goal_updated` `2026-07-18T14:47:59.770Z` on source thread `019f73d8`, goal beginning “Yes thoroughly Approve the seven-point answered_pending contract and resume Lane D.”
6. Apply Brooks PR Review discipline. Findings require exact line evidence, symptom/source/consequence/remedy, severity P0-P3, and a runnable counterexample where practical.

## Output contract

- State exact base/head and commands rerun.
- Give a requirement-by-requirement verdict for the seven points and explicit dispositions for all five prior findings.
- Separate Confirmed, Inferred, Needs More Evidence, Do Not Do Yet, residual risk, and an explicit did-not-verify line.
- If no material issue remains, say `REVIEW-CLEAN` and `MERGE-READY`; otherwise say `NOT MERGE-READY` and identify blockers.
- Include an `Audited Chat` block with source chat name, cwd, provider, full ID, and resolved transcript path.
- Do not mutate any repository, GitHub, runtime, provider, or live state.

## Delegation defaults

No delegation for this bounded audit. Two grounded attempts per failing command, then record the unverified boundary without thrashing.
