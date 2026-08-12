# Mission Control repository convergence — 2026-08-11

## Goal

Preserve every recoverable Git object and uncommitted change, repair current reliability failures, integrate only work that still matches `PROJECT_INTENT.md`, then close and clean obsolete Git state without losing recovery paths.

Owner: Codex `019ff2ae-33b3-7e50-af39-3a08efef29a8`
Branch: `codex/repo-convergence-019ff2ae`
Base: `origin/main@43bca917871a33f3b4176117df86e15eb80a3472`
Linear: `self-contained:` because `LINEAR.md` records repo-only mode.

## Preservation checkpoint

- Main was clean and equal to `origin/main` at the checkpoint.
- Git had 22 unreachable commits plus 101 remaining unreachable blobs and trees.
- Every unreachable object now has a `refs/rescue/2026-08-11/` ref; a fresh `git fsck --full --unreachable --no-progress` returned no output.
- Four dirty worktrees were captured through temporary indexes without altering their working files:
  - `provider-cards`: `a295e142ed3718b6aed90cd8c865b1cb540941d1`.
  - `rollup-answer-occupied-parent-repair`: `2976396176b75ac0fd1eaf7541e1089789f885f5`.
  - `temp-fixture-cleanup`: `f2a4213937669f84dee011214f94a62efe3b1efd`.
  - `unified-health`: `d37d8e672e117514397866dafba9a61ea2d20a0c`.
- Local branches, remote-tracking branches, and detached worktree heads have matching pre-convergence rescue refs.
- Two complete Git bundles exist:
  - `/Users/gillettes/Downloads/mission-control-recovery-2026-08-11-019ff2ae.bundle`.
  - `/Volumes/T7/mission-control-recovery/mission-control-recovery-2026-08-11-019ff2ae.bundle`.
- Both bundles have SHA-256 `5f62b9b219524e2eb1dea6acf1a37d258b116285478c1614684955cb0270072a`.
- `git bundle verify` passed for both copies.
- A temporary mirror clone from the Downloads bundle passed `git fsck --full --strict` and resolved all four dirty-worktree refs to their expected commits.
- The GitHub repository is public. Recovery-only refs and snapshots stay local until a privacy review proves they contain only publishable data.

## Current inventory and initial dispositions

- PR #11, `codex/rollup-answer-wiring`, is approved but conflicts with `main`. Local head `9185dec694603b1482206b3ce9ab6d8dabc9ef7b` contains an interrupted current-main reconciliation and remains preserved for review.
- PR #10, `codex/phase0-work-record`, is approved but conflicts with `main`. Its current facts will be refreshed into this record before closing the stale PR without merging.
- Reliability work to reconcile on current `main`: the Decisions collector timeout, interrupted-fixture cleanup, process-group reaping, and the panel click race if still reproducible.
- Product work to finish only when current-intent tests pass: rollup-answer and its occupied-parent recovery regression.
- Work to preserve but not ship in this campaign: answer-dispatch autonomy, the old visual refresh, unified-health, and memory-health feature experiments. `PROJECT_INTENT.md` gates autonomy and additional features until the V1 clarity pass is verified.
- Already-contained or superseded refs will receive exact archive tags before deletion. Remote deletion requires an expected-OID check after tag readback.

## Ordered execution plan

1. Reproduce and repair the Decisions collector timeout on a synthetic store large enough to cover the live 136-outcome shape.
2. Add the smallest macOS GitHub Actions workflow that runs the repository verifier without secrets or live-state access.
3. Reconcile rollup-answer against current `main`, including the preserved occupied-parent regression, then obtain fresh exact-head review.
4. Port reliability-only test hygiene and the panel click fix through focused regressions on current `main`.
5. Merge one green outcome at a time, rerunning focused checks and `scripts/verify.sh` after each integration boundary.
6. Install only the final merged source, verify the install stamp, and use actual scheduled-run logs for live proof.
7. Close stale PRs, archive exact source heads, release owner leases, remove worktrees through the cleanup broker, and delete branches with exact-OID checks.
8. Reconcile `todo.md`, OpenSpec state, branch history, recovery commands, and any remaining Trevor-owned decisions.

## No-delete gates

No worktree, local branch, remote branch, PR, rescue ref, or backup is removed until all applicable checks pass:

- exact source SHA appears in the recovery manifest and both verified bundles;
- dirty tracked and untracked files have a restorable snapshot;
- the source is merged, patch-contained, or explicitly closed without merge;
- any remote source has an archive tag whose SHA was read back;
- no live process holds the worktree;
- the recorded owner lease is released by its owner;
- the cleanup broker accepts the exact worktree generation and frozen head;
- remote deletion uses the observed expected OID;
- `todo.md` records the outcome and recovery pointer.

## Current unverified boundaries

- The exact root cause of the Decisions timeout is not yet proven.
- Local rollup head `9185dec` has not received a fresh immutable review or current full verifier in this campaign.
- Existing secondary worktrees predate owner leases and require owner-bound recovery before cleanup.
- Natural scheduled-run proof must come from an observed scheduler firing; quiet time is not proof.
