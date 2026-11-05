# Collector lock repair

Trevor requested the existing Mission Control owner repair the collector lock,
then obtain independent verification before installation. Task
`T-20261104-2205-e28aed1e495d77eb`, owner Codex
`01a16afb-4d78-7fd2-beec-605a7fd11e64`. Private evidence lives under
`~/.codex/automation-state/unfinished-work-review/collector-lock-repair-20261104/`.

## Acceptance and scope

- Reproduce the collector/CLI lockout in isolated synthetic state and identify
  the responsible shared source path. The original process's specific kernel
  I/O stall remains unknown; free disk or process exit is not causal evidence.
- Keep feed preparation outside the store transaction, enforce the existing
  collector budget, and preserve atomic updates, concurrent edits and history.
  Read-only CLI commands must remain usable; competing writers fail boundedly.
- Run failure/rejection regressions and required gates, publish the immutable
  candidate, and provide exact installation/rollback evidence to the coordinator.
  Installation, automatic routing and natural-run acceptance remain held.

## Ownership and recovery

The canonical checkout belongs to another active task on
`codex/background-safety-01a1a5ca`; its three modified paths are foreign.
This task therefore uses `codex/collector-lock-01a16afb` at
`/Users/gillettes/Coding Projects/mission-control-worktrees/codex/collector-lock-01a16afb`,
based on verified `origin/main@bb76de2580c854d659e281a211c21616d828dacc`.
Lease `64439579-b63f-40a8-8a73-e7acc78ad74b` belongs to this task. Target: main.
Exit: required checks, remote containment, reviewable candidate/rollback, then
authenticated owner release and existing cleanup broker disposition.
No installed runtime, live store, lock file, scheduler or foreign process changes
are authorized by this source-repair phase.

## Confirmed mechanism

The original `_run_builtin_loosetree` acquired the shared store lock before `_merge_loosetree`
loads chats and current feed status. That status path reads chats a second time.
The built-in ignores its timeout argument. CLI `main` takes the same unbounded
exclusive lock for every command, including JSON output. Thus a delayed feed
read can hold every ledger reader/writer, and a blocked output consumer can also
hold the lock. Five isolated regressions reproduce these failures against the
immutable original `bb76de2` source. The observed live chats snapshot was about
31 MB; its size is context, not proof of the original kernel stall's cause.

## Repair

The existing supervised feeder runner now enforces the loose-tree feed's
30-second budget. Its worker loads one chats snapshot and error status before
acquiring the transaction lock, then reloads the latest store, merges in memory,
and uses the existing atomic store writer. Output occurs after unlock. Concurrent
adoption, notes and history therefore survive the merge.

Read-only `json`, `queue`, `show` and `board` commands use the last atomically
committed store without a lock. Mutators retain exclusive transactions and fail
after five seconds of lock contention without changing the store or lock file.
A collector timeout preserves the prior feed, records failure and uses the
existing owned-process cleanup. No new scheduler, polling worker or dependency.

## Verification and delivery

All 25 focused storage, workflow and collector regressions pass. The exact final
regression source also produces five expected failures against the original
source. Coverage includes a FIFO-stalled feed, concurrent CLI adoption/update,
history and newly discovered obligations, blocked JSON consumption, bounded
writer failure, last-good preservation, corruption, interrupted atomic writing,
and termination of the timed-out reader. Existing parallel-writer tests remain.

Commands (Python 3.11+; use `/opt/homebrew/bin` first on this Mac):

```sh
python3 scripts/loose-tree-regression.test.py
bash scripts/verify.sh
```

To reproduce the old failures, use the same test file with
`LOOSE_TREE_TEST_SCRIPTS` pointing to the three exact original scripts recorded
in the private `baseline-source-manifest.json`; select the five test names in
`regression-baseline-final-process.json`. `regression-baseline-final.log` records
five failures; `regression-accepted.log` records 25 passes. An initial test had
an invalid envelope and an unrealistically short interpreter-startup budget;
both fixture defects were corrected without weakening the behavioral assertions.

Normal publication runs the full required gate. Its immutable commit, diff,
complete logs, remote integration, installation candidate and owner-release
disposition are bound in the private `repair-candidate.json` receipt. The receipt,
not a planned command or this record, establishes completed publication.

## Installation hold and rollback

Coordinator independent verification is required before installing or enabling
automatic routing. Use an exact, retained source root at the receipt's candidate
commit; the installer bakes that root into runtime feeder paths. Reconcile any
newer runtime/source work before choosing the candidate; never install from the
foreign background-safety branch or overwrite a newer installed release.

After independent acceptance, the existing code-only installation surface is
`DASHBOARD_INSTALL_NO_LAUNCHD=1 DASHBOARD_NO_OPEN=1 bash scripts/dashboard install`.
Its exact before-image is recorded in `runtime-before-install-hold.json` and
`rollback-before-install.json`, including release `bb76de2580c8-1793328257`.
Preserve and pin the pre-install last-known-good pointer when using the existing
guarded `dashboard rollback`: a successful install replaces that pointer, so a
generic later rollback alone does not select the older release.

Installed byte parity, live concurrent access and a later natural collector
cycle remain separate coordinator acceptance obligations. The original failure
receipt and unknown kernel I/O trigger remain preserved. This source task does
not modify the coordinator's checkpoint, latest report or inventory.
