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

## Final attempt

- Status: pending exact-head re-audit by task `019f7680-90ce-7392-a991-5a76a3bae61b` after the records-complete authoritative gate.
- Did not verify: final review-clean verdict, remote/PR state, merged-main behavior, install/deploy, provider delivery, or live-store behavior.

## Audited Chat

- Audited chat name: Execute Phase 0 hardening backlog.
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/global-implementations`.
- Provider: Codex.
- Full ID: `019f73d8-e5dc-73a0-acc5-8a4916ac6819`.
- Resolved transcript: `/Users/gillettes/.codex/sessions/2026/07/17/rollout-2026-07-17T23-10-22-019f73d8-e5dc-73a0-acc5-8a4916ac6819.jsonl`.

No repository, live store, provider, install, deployment, plist, launchd, merge, or main-branch mutation was authorized or performed by the auditor.
