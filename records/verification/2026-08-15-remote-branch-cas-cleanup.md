# Remote branch exact-lease cleanup — 2026-08-15

## Goal

Remove every non-main remote branch after lossless consolidation. Work only from the primary `main` checkout. Do not create another branch or worktree.

- Owner: Codex `01a00647-2c65-7592-8c65-c76087de3bcf`.
- Execution checkout: `/Users/gillettes/Coding Projects/mission-control` on `main`.
- Starting `main`: `6e9776fa97bc946a422457dab700de0cc1db719e`, equal to `origin/main`.
- Approved helper: `/Users/gillettes/Coding Projects/global-implementations/scripts/branch-hygiene.sh cleanup-merged --yes`.

## Safety route

The helper deletes each remote branch with:

```text
git push --force-with-lease=refs/heads/<branch>:<expected_oid> origin :refs/heads/<branch>
```

Before cleanup, the helper self-test passed. Targeted source review confirmed one exact-OID lease per deletion, moved-ref refusal, ancestor-or-squash proof, and nonzero handling for authentication failures.

No approved and tested atomic multi-ref deletion route existed. A direct raw batch attempt remained blocked by the trusted Git hook, so the approved helper stayed in use.

## Recovery checks

- Every target tip matched its live remote OID.
- Every target tip was an ancestor of `origin/main`.
- Every target had a published annotated archive tag whose peeled commit matched the exact tip.
- Both complete Git bundles verified before and after cleanup.
- Both bundles have SHA-256 `47be14743e935419cd8a570d0acf2c952c96e5162ea6cab5249118912fab0a17` and mode `0600`.
- The independent bundle remains under `/Users/gillettes/Downloads/mission-control-recovery-2026-08-15-01a00647/`.

## Deleted remote heads

- `claude/dashboard-visual-refresh` at `fd96ca5d98f09ee91613e1033ff82c7ef2a285d3`.
- `codex/answer-dispatch-slice1` at `3fa22f233a6e0aba05537cb616f8417b772e93b7`.
- `codex/er103-git-state-and-morning-proof` at `0a609f8f47de06ec55fdc0240d041fbe4c26486d`.
- `codex/er156-telegram-flow-routing` at `d8be1358dbe71f633557c40055e0a3e87a35bebd`.
- `codex/er277-collector-019fb8ef` at `b29726e6551759a04789e4dcdd4987db7be798c0`.
- `codex/er277-fixture-pgid-reaper` at `7a85d248cdd415295276fc1432d00cc2c9dbf265`.
- `codex/er930-opus5-only` at `79cff0d98ef97e6c7eeabcf9cd43be19c877cd67`.
- `codex/phase0-work-record` at `9296e2c70ee73affe792abff032257c320101106`.
- `codex/repo-convergence-019ff2ae` at `fc52c57465a20eef048eaa73612771a07e6ba3e7`.
- `codex/rollup-answer-wiring` at `5153e2db74fbc8ac1ed62793567365ec29fbc161`.
- `cursor/019ff2ae-terminal-audit` at `a75ea18d1662fb2328a28b0d97834bad24976303`.
- `cursor/attention-lane` at `ca934e268fe3080227e70ec90e6e2c375c9f89d9`.
- `feat/memory-health-line` at `c5b78d8bccc25e8321bd192e2e5f91b4caff22cd`.
- `phase0/admission-backfill` at `10d74514f9d3eae0a462d4405f64921b87b9c25c`.
- `phase0/answer-return-path` at `c109bd08e368649171a5a797c1a8219c9b1e6989`.
- `phase0/queue-repair` at `d4759edcb765cdf2bddc17cc8b9b8f59d5b99ff7`.
- `preserve/primary-dirt-20260717` at `cd26fd78605501b951a38be5c842c40a201abdef`.

## Execution note

The first guarded attempt stopped before deletion because the repository verifier found ignored `scripts/__pycache__` bytecode. The four generated `.pyc` files moved intact to:

```text
/Users/gillettes/Coding Projects/mission-control/.git/codex-quarantine/2026-08-15-main-consolidation-01a00647/verification-pyc-before-remote-cas-cleanup
```

Cleanup then ran with `PYTHONDONTWRITEBYTECODE=1`. Every reported remote deletion completed through the exact-OID helper route.

Three oversized combined review outputs were truncated and discarded. The exact edited sections, helper contract, remaining-ref checks, and final state were rerun through bounded commands before commit.

## Final readback

- `git ls-remote --heads origin` returned only `refs/heads/main` at `6e9776fa97bc946a422457dab700de0cc1db719e` before this records-only commit.
- Local branches contained only `main` at the same commit.
- The helper's non-mutating cleanup preview reported `Nothing to delete`.
- The primary checkout was clean and matched `origin/main` before records were edited.
- Twenty-one branch archive tags remained under `archive/consolidation-20260815/branch/`.
- `git bundle verify` passed for both complete bundles after deletion.
- The only additional registered checkout was detached bd05 at `43bca917871a33f3b4176117df86e15eb80a3472`.
- `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh` passed `SUITES PASS=26 FAIL=0` on the records candidate.

## Remaining boundary

The detached checkout at `/Users/gillettes/.codex/worktrees/bd05/mission-control` is Codex-managed. Repository policy requires its app lifecycle to remove it. No manual removal was attempted.
