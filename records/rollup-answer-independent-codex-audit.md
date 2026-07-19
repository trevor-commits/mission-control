# Rollup-answer independent Codex audit

## Attempt 1 — rejected candidate and accepted repairs

- Audit task: Codex `019f762c-c815-77b3-97c0-021c66fd3b7e`.
- Model/reasoning: `gpt-5.6-sol` / max.
- Reviewed range: `53e91392dcef3d2deeedf748c14159320a8572e0..daa8c72708b36472e5b370cb9e2374a17d23b41d`.
- Verdict: `NOT MERGE-READY` despite `SUITES PASS=23 FAIL=0`.
- P0: none.
- P1: two accepted findings.

### P1 disposition

1. **Post-commit publication divergence — accepted and repaired in `34687c9`.** The old path committed `answered_pending` before binding later stage/final validation to the same held directory and before persisting the manifest digest. The repair removes wall-clock bytes from rollup artifacts, persists the canonical manifest SHA-256 and exact replay metadata, verifies a held batch fd before/after commit and after rename, quarantines suspect material, and makes parent replacement/mutation exact-replayable.
2. **Public answer feed could remain stale — accepted and repaired in `34687c9`.** The old `sync-snapshot || collect` path treated a non-writing sync as success. The dashboard now runs the strict decisions collector with `DECISION_ALERT_AUTO=0`, reports committed-but-refresh-failed nonzero with structured stdout, and proves Home/Morning Brief coherence without invoking a provider sender.

Evidence: `records/evidence/rollup-answer-audit-repair-red-green.txt` and `records/evidence/rollup-answer-audit-repair-full-green.txt`.

## Attempt 2 — rejected replay/runtime/presentation boundaries

- Audit task: Codex `019f7680-90ce-7392-a991-5a76a3bae61b`.
- Model/reasoning: `gpt-5.6-sol` / max.
- Reviewed range: `53e91392dcef3d2deeedf748c14159320a8572e0..708031f603e2c53ba9a8a8375e9f23a42ed123f4`.
- Verdict: `NOT MERGE-READY` despite rollup 14/14 and `SUITES PASS=23 FAIL=0`.
- Findings: two P1 and one P2, all accepted.

### Finding disposition

1. **Existing-batch replay corruption remained canonical — accepted and repaired in `8613d25`.** Cleanup now quarantines `artifact_name`, the authoritative name bound to the held artifact fd, independent of whether this invocation created or published the batch. Hermetic replay-time mutation and parent-replacement regressions prove canonical removal, pinned-parent quarantine, exact recovery, and one immutable event per target.
2. **Strict refresh could read through a stale installed runtime — accepted and repaired in `8613d25`.** The embedded decisions collector now uses `MISSION_CONTROL_RUNTIME_DIR/decision-alert`, the same `SCRIPT_DIR` runtime used by the public transaction. A temporary executable stale reader is planted and proved uninvoked while the refreshed feed exposes pending state.
3. **Pending prefixes could hide actionable work — accepted and repaired in `8613d25`.** Home and panel now stably partition actionable rows before pending rows, with browser/panel regressions where three pending rows precede a later actionable row.

Evidence: `records/evidence/rollup-answer-final-audit-red-green.txt`.

## Attempt 3 — rejected occupied replacement-parent boundary

- Audit task: Codex `019f7680-90ce-7392-a991-5a76a3bae61b`.
- Model/reasoning: `gpt-5.6-sol` / max.
- Reviewed range: `53e91392dcef3d2deeedf748c14159320a8572e0..16a3e516a9566ad5ce929cade29db334e7bfe08f`.
- Verdict: `NOT MERGE-READY` with one P1 despite a clean authoritative `SUITES PASS=23 FAIL=0` rerun.
- Accepted P1: replacing the path-visible `answer-batches` parent during exact replay with a private parent already containing an invalid directory at the deterministic canonical name left that unbound conflict visible after the command failed. The held old-parent artifact was correctly quarantined and later replay recovered, but the public canonical path was receipt-divergent during the failure window.
- Repair: `bfaf10b` separately opens and revalidates the current parent through the pinned home descriptor, distinguishes it from the held old parent by inode, binds any same-name directory to an fd, and quarantines it only when it is not the persisted receipt-backed artifact. The regression proves old-object preservation, immediate removal of invalid canonical visibility, exact later rebuild, and one pending event per target.
- Audit transparency: the auditor's first full verifier run was `22/1` only because its own direct test invocation created ignored bytecode; it removed only that audit-created cache, reran with bytecode disabled, and obtained a clean `23/0` at the unchanged frozen head. This was test-environment contamination, not a product finding.

Evidence: `records/evidence/rollup-answer-occupied-parent-red-green.txt`.

## Attempt 4 — rejected persisted Morning Brief coherence boundary

- Audit task: Codex `/root/lane_d_final_audit` (fresh same-model/max worker of source task `019f73d8-e5dc-73a0-acc5-8a4916ac6819`).
- Model/reasoning: `gpt-5.6-sol` / max.
- Reviewed range: `53e91392dcef3d2deeedf748c14159320a8572e0..af083a64e8dd7a264d1cdfc4ed7d344b8a895b20`.
- Verdict: `NOT MERGE-READY` despite the source task's committed `SUITES PASS=23 FAIL=0` receipt.
- P1: the public answer transaction refreshed only `data/decisions.json`; an already-persisted `morning-brief/latest.json` and public `data/brief.json` remained byte-identical, retained the answered decision, and still allowed exit zero.
- P2: `verify.md`, `STATE.md`, and `todo.md` still described already-committed/full-green steps as pending.
- Disposition: accepted. The P1 was reproduced with a public-command-only RED test at frozen `af083a6`. The repair adds exact-runtime `morning-brief --refresh-local`, strict brief-feed publication, authoritative delivered-receipt validation, receipt/cursor preservation, in-flight delivery fail-closed behavior across a day rollover, single-answer parity, and planted stale runtime/no-send traps. Focused gates are rollup `23/23`, Morning Brief all pass, dashboard `67/0`, ER-134 `59/0`, syntax/diff clean. The P2 records are reconciled in the same repair change.
- Evidence: `records/evidence/rollup-answer-morning-brief-coherence-red-green.txt`.
- Auditor limitation: its focused `18/18` rerun passed, but its own full verifier was interrupted after several green suites. The source task's exact `af083a6` full-gate receipt remains the authoritative pre-repair gate; a new post-repair authoritative gate is still required.

## Final attempt

- Status: fourth-audit repair `0ce6d3d` is focused and authoritative-gate green; a new frozen-head same-model/max verdict remains pending.
- Full-gate evidence: `records/evidence/rollup-answer-morning-brief-coherence-full-green.txt` (`SUITES PASS=23 FAIL=0`); historical pre-repair receipt is `records/evidence/rollup-answer-occupied-parent-full-green.txt`.
- Did not verify: final review-clean verdict, remote/PR state, merged-main behavior, install/deploy, provider delivery, or live-store behavior.

## Audited Chat

- Audited chat name: Execute Phase 0 hardening backlog.
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/global-implementations`.
- Provider: Codex.
- Full ID: `019f73d8-e5dc-73a0-acc5-8a4916ac6819`.
- Resolved transcript: `/Users/gillettes/.codex/sessions/2026/07/17/rollout-2026-07-17T23-10-22-019f73d8-e5dc-73a0-acc5-8a4916ac6819.jsonl`.

No repository, live store, provider, install, deployment, plist, launchd, merge, or main-branch mutation was authorized or performed by the auditor.
