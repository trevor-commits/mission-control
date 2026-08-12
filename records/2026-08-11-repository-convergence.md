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
  - private local recovery copy `mission-control-recovery-2026-08-11-019ff2ae.bundle`.
  - private offline-media recovery copy with the same logical bundle name.
- Both bundles have SHA-256 `5f62b9b219524e2eb1dea6acf1a37d258b116285478c1614684955cb0270072a`.
- `git bundle verify` passed for both copies.
- A temporary mirror clone from the private local copy passed `git fsck --full --strict` and resolved all four dirty-worktree refs to their expected commits.
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

## Selective integration checkpoint

- The reported Decisions timeout is not reproducible on current source or current data. A SQLite backup plus the live 136-outcome chat snapshot completed `sync-snapshot` in 0.532 seconds, the focused decision suite passed, the live feed is healthy, and the scheduled job last exited zero. Historical stderr also records `ENOSPC` and concurrent timeouts across Usage, Git, Chats, and Decisions. That evidence supports a broader host-pressure incident, but it does not prove one exact cause, so no speculative Decisions code change was made.
- CI commit `b370e5afd61c8d84b3558396131233c8ef807f51` adds a dependency-pinned `macos-15` workflow. Follow-up `e27ea08` installs exact `playwright@1.62.0` without bundled browsers so the two required browser suites can load their client while using the runner's installed Google Chrome. GitHub's current `macos-15` image lists Chrome 150, and an isolated install/launch check passed. The local push gate passed all 24 baseline suites and 307 dashboard-browser assertions before publication.
- Rollup source head `9185dec694603b1482206b3ce9ab6d8dabc9ef7b` is merged into the convergence candidate. Its source-head transaction suite passed 29/29 before integration; exact merged-head full verification remains a landing gate.
- Process-group fixes `36386f7` and `5832b16` were ported as `fb7d9e7` and `f736c10`. The current targeted matrix reaped all three interrupted feeder shapes and passed 9/9 without touching live data.
- The menu-bar click race was reproduced as ER-134 `62 passed, 1 failed`, then repaired at `00b82a8`; the focused suite is now `63 passed, 0 failed` while retaining hover preview and pinned headroom.
- Dirty snapshot `f2a4213` supplied the test-fixture containment design. Current commit `5566871` combines its identity-bound temp root with the stronger process-group reaper; verifier self-tests, targeted dashboard cases, chat graph, outcome extractor, and Usage all pass. The formerly noisy absent-file checks now fail silently only when the expected zero-call file is absent.
- A repeated fast-feeder probe reproduced four ownership failures in 120 runs because the child could exit before `os.getpgid()` registered its group. Commit `e6e0d09` records the guaranteed session PGID from `Popen(start_new_session=True)` and consults `os.getpgid()` only while the process still exists. The targeted RED was `PASS=6 FAIL=1`; targeted GREEN is `PASS=7 FAIL=0`; the full dashboard suite is `PASS=90 FAIL=0`.
- Fresh review found that a valid `attention` envelope was absent from `EXPECTED_CADENCE` and `combinedHomeState()`. Manual attention and a stale Brief could therefore leave Home at `Answers recorded`. Source commit `60577b78fa32b48f10580796f94aacdb16a1fb19`, integrated as `bd83a30`, accepts the 300-second cadence, includes the feed in combined Home state, and keeps pending decisions read-only. Both exact RED mutations produced `Answers recorded`; the integrated browser suite passes 315 assertions.
- Source commit `79cff0d98ef97e6c7eeabcf9cd43be19c877cd67`, integrated as `55544cb`, pins both Outcome Extractor attempts to exact `claude-opus-5` and rejects another selector before command lookup. The source owner passed the 37-case extractor suite and two complete `SUITES PASS=24 FAIL=0` runs, including the push hook. The combined branch independently passes all 37 extractor checks and its slow-call transaction test. No live Claude call was made.
- Source commit `fdb838dd6d7520646541c9bf95e2a7901c8c2d58`, integrated as `4453b8e`, validates rollup targets before creating locks, batch paths, or SQLite files. The source exact-head verifier passed `SUITES PASS=26 FAIL=0`; the convergence branch independently retains the invalid-target no-write regression.
- Answer-dispatch autonomy, unified-health, memory-health, and the old visual refresh remain preserved but excluded. They conflict with the current V1 clarity gate or are superseded by newer mainline work.

## Final candidate verification

- Exact candidate `112757172e640450f73fcd1a69f36745f6882a73` passed `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh` with `SUITES PASS=26 FAIL=0`.
- Key totals: dashboard `90/0`; Rollup Answer `29/29`; ER-134 `63/0`; loose-end runner `32/0`; shared policy `2/0`; Usage `24/0`; dashboard browser 315; panel browser `13/0`; native panel suites `16/0` and `15/0`; OpenSpec `2/0`.
- Python syntax, shell syntax, source-artifact checks, `git diff --check`, and immediate commit/status readback passed. The worktree remained clean at the exact candidate.
- The required technical-prose check was run over the five changed record/OpenSpec files. It reported 1,765 errors and 227 warnings across their full historical contents. No prose-clean claim is made, and a wholesale historical rewrite is outside this convergence change.

## PR review and hosted-CI repair

- PR #16 published docs head `8b36b32f0a0bb02b942672500881dbd203a62df8`. GitGuardian passed. The first hosted verifier reached `25/26`; its only failed suite used a 150-millisecond wall-clock threshold and observed 152 milliseconds on the hosted runner. Two passing suites also printed `rg: command not found` because the workflow never installed ripgrep.
- Codex and CodeRabbit found valid gaps in attention refresh, native pending counts, Morning Brief sidecar health, rollup test isolation, failure-injection gating, process-group cleanup, model-policy accounting, SQLite indexing, identifier validation, and checkout credential persistence.
- Repair commit `2bfda6afe0ee839dc498cf27820febfde543dbde` closes those paths. Mutation-backed RED reproduced stale attention, ambient aborts, stale sidecar health, pending native overcount, missing index coverage, and whole-value validation bypass before GREEN.
- Focused GREEN at that commit: dashboard `91/0`; Rollup Answer `32/32`; dashboard browser 315; panel browser `13/0`; native summary `16/0`; Decision Alert, Morning Brief, Outcome Extractor, deadman sender, and loose-end runner all pass. Syntax, strict OpenSpec, and diff checks pass.
- Exact post-review records candidate `9d3f56289619d44486721eee3f3caa691f33618a` passed the authoritative verifier with `SUITES PASS=26 FAIL=0`. Key totals are dashboard `91/0`, Rollup Answer `32/32`, ER-134 `63/0`, loose-end runner `32/0`, Usage `24/0`, dashboard browser 315, panel browser `13/0`, both native core suites `16/0`, and OpenSpec `2/0`. Syntax and source-artifact gates passed; immediate HEAD/status/diff readback stayed exact and clean.

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

- Historical Decisions timeouts cannot be attributed more narrowly than the observed host-wide storage/timeout episode; current behavior is green and no source defect was reproduced.
- Exact records candidate `9d3f56289619d44486721eee3f3caa691f33618a` is authoritative-gate green. The docs-only receipt still needs the ordinary push-hook verifier, hosted CI/review readback, PR merge, and installed-source readback.
- Existing secondary worktrees predate owner leases and require owner-bound recovery before cleanup.
- The Rollup Answer and Opus 5 owner worktrees remain registered until their exact owners release their leases. Their source commits are contained, but physical cleanup must use the broker after each owner turn ends.
- Natural scheduled-run proof must come from an observed scheduler firing; quiet time is not proof.
