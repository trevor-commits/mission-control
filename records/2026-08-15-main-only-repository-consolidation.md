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

## Completed execution

- `main` and 36 explicit archive tags were published atomically. Remote readback matched every local tag object and peeled commit.
- `origin/main` advanced through history join `e5cff7760b0791958cb1675472ad370f47243b2c`, preservation record `16c0449aafcaacc76f03745e73a888732b8443c7`, and recovery gate `563ef06b9a42cd0d2aff47f58569afa8b8571e86`.
- Both ordinary pushes passed the full repository hook with `SUITES PASS=26 FAIL=0` and a clean credential gate.
- Fifteen ignored or untracked paths moved to private quarantine under `.git/codex-quarantine/2026-08-15-main-consolidation-01a00647`. Four tracked dirty states were restored only after exact snapshot comparison.
- Three existing released leases were cleaned through the owner broker: convergence `c3d027bb-4fad-46d0-bc46-9ad206bb1b57`, rollup wiring `c257044e-651d-4052-a698-f659fcb4926d`, and Opus 5 `43904228-a1e6-4739-873d-3e88cca6b8e3`.
- The landed recovery inventory is `records/verification/2026-08-11-lossless-worktree-recovery-inventory.json`. It binds ten legacy checkouts to this transaction and four immutable recovery surfaces.
- Recovery manifest `99752949e836d23c0131b1bf7fb96e8745bd6a0e36531a8c4d34319323c6e2b2` prepared all ten candidates with zero refusals.
- Approval `9c407d5346d5fecf834f8c35df2c312104a763df3106e9b44983e5b8c939f678` authorized those exact candidate, path, and lease tuples.
- Apply completed with zero blocked, drifted, malformed, or unauthorized entries. All ten legacy checkouts then reached broker state `removed`.
- The broker deleted ten worktree-bound local branches. Four residual local branches were deleted atomically with their expected object IDs.
- Local branch inventory now contains only `main`. Every deleted local head remains recoverable through main ancestry, public archive tags, private rescue refs, and both bundles.

## Retained boundaries

- The completed Codex task `019ff47d-1b90-7380-84f4-3117f1426070` was archived through the app lifecycle. Its detached bd05 checkout remains registered because the app did not remove it.
- Native handoff unexpectedly created one transient local branch and switched the primary checkout. Main was immediately restored, and that exact unpushed ref was deleted by expected object ID.
- Seventeen remote topic refs remain. The trusted hook rejected raw deletion, and `BRANCH_LIFECYCLE.md` requires retention until a separately audited provider/CAS cleanup route exists.
- Every retained remote topic head is an ancestor of `main`. They are recovery aliases, not unmerged work.
- The credential-bearing commit remains private-only and is not an ancestor of `main`.
- No additional worktree was created. The handoff's transient branch was never pushed, and no work was lost.
