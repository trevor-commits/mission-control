# Main-only repository consolidation — 2026-08-15

## Goal

Preserve every recoverable branch, checkout, dirty file, and loose commit. Join safe histories to `main`. Remove obsolete state without creating another branch or worktree.

- Owner: Codex `01a00647-2c65-7592-8c65-c76087de3bcf`.
- Execution checkout: `/Users/gillettes/Coding Projects/mission-control` on `main`.
- Baseline: `fa8611bd0e2a3ea4f1c7476adc9807df471d5a56`, equal to `origin/main`.
- Baseline tree: `6c232350159c1b63640352596709811fd0fd73e6`.

## Preservation evidence

- Four dirty checkouts exactly matched immutable snapshot commits: provider cards `a295e142ed3718b6aed90cd8c865b1cb540941d1`, occupied-parent repair `2976396176b75ac0fd1eaf7541e1089789f885f5`, temp cleanup `f2a4213937669f84dee011214f94a62efe3b1efd`, and unified health `d37d8e672e117514397866dafba9a61ea2d20a0c`.
- Fourteen complete checkout archives were created before any checkout mutation. Each exists under the Git common directory and in an independent Downloads directory with mode `0600` and a matching SHA-256.
- Checkout archive SHA-256 prefixes: main `35e0d7fe`, app-managed bd05 `f48ad6d6`, memory health `c6847128`, attention `475bcedf`, and answer dispatch `c0f2c3ad`.
- More prefixes: Opus 5 `451c521d`, ER-277 fixture `806538b6`, usability redesign `67da3b7b`, Phase 0 `e78f33e6`, and provider cards `70a45910`.
- Final prefixes: occupied-parent repair `c659800c`, rollup wiring `0f9a50c9`, temp cleanup `02c337b4`, and unified health `90bde276`.
- Thirty-six annotated tags under `archive/consolidation-20260815/` preserve every named branch, detached checkout, dirty snapshot, safe loose commit, and the pre-consolidation baseline.
- Private refs under `refs/rescue/2026-08-15/` retain the same public sources and the excluded credential-bearing chain.
- Both complete Git bundles have SHA-256 `47be14743e935419cd8a570d0acf2c952c96e5162ea6cab5249118912fab0a17`. `git bundle verify` passed, and the bundle listed 315 retained refs.
- The independent extraction proof is `records/verification/2026-08-15-main-consolidation-bundle-extraction.md`.

## Privacy boundary

The exact global credential pattern passed all 33 intended public source tips. Commit `d9f1a33b4a12b4831264ee3052ce73b0880d6b36` remains private-only because its range identifies credential-shaped content at ancestor `2bfda6afe0ee`, `scripts/loose-end-runner.test.sh:204`.

## History join

Commit `e5cff7760b0791958cb1675472ad370f47243b2c` uses Git's `ours` merge strategy with 20 independent retained heads. All 33 safe source tips are ancestors of that commit.

The merge tree is exactly `6c232350159c1b63640352596709811fd0fd73e6`, identical to the pre-merge `main` tree. The excluded private commit is not an ancestor. Deferred answer-dispatch, visual-refresh, unified-health, and memory-health behavior therefore remains inactive.

## Remaining execution gates

1. Publish `main` and only the explicit archive tags, then read them back.
2. Clean preserved checkout dirt only after archive and snapshot proof.
3. Remove the app-managed checkout through native handoff and leased checkouts through the owner broker.
4. Recover legacy no-lease checkouts through the hash-bound inventory and broker path.
5. Delete residual local and remote topic branches only with expected-object checks.
6. Reconcile this record, `todo.md`, continuity surfaces, branch hygiene, tests, and final remote state.
