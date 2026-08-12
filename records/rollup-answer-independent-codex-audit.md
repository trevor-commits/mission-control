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

## Attempt 5 — rejected receipt identity and regular-file entry boundaries

- Audit task: Codex `/root/lane_d_local_view_reaudit`, fresh `gpt-5.6-sol` / max worker of source task `019f73d8-e5dc-73a0-acc5-8a4916ac6819`.
- Reviewed range: `53e91392dcef3d2deeedf748c14159320a8572e0..8b8fa772336239eab812b38e2b152e69dce65a96`.
- Verdict: `NOT MERGE-READY` despite rollup `23/23` and authoritative `SUITES PASS=23 FAIL=0` receipts.
- P1: a delivered receipt with valid schema/counters and confirmed 64-hex chunk fields could contain digests unrelated to the sidecar-bound delivered Markdown. The public answer returned zero and rewrote local Morning Brief artifacts anyway.
- P1: during exact replay, replacing the batch parent and occupying the current canonical name with a mode-0600 regular file preserved/quarantined the held old-parent batch but left the visible file canonical, wedging every later replay.
- Disposition: both accepted and independently reproduced RED at frozen `8b8fa77`. The repair makes new receipts carry the full Markdown digest and deterministic chunk limit; local refresh recomputes every ordered chunk digest and pins the exact receipt-byte digest across replay. Canonical cleanup now pins regular-file or directory entries without symlink traversal, verifies name/inode identity, quarantines the exact receipt-backed conflict, and never mutates an orphan first-answer entry. Targeted regressions and the 25-test focused suite are green.
- Evidence: `records/evidence/rollup-answer-receipt-entry-red-green.txt`.

## Attempt 6 — rejected missing identity, symlink, race, and global-headline boundaries

- Audit task: Codex `019f77f3-4975-7f51-b296-fbdc2dbd3d47`, fresh `gpt-5.6-sol` / max worker of source task `019f73d8-e5dc-73a0-acc5-8a4916ac6819`.
- Reviewed range: `53e91392dcef3d2deeedf748c14159320a8572e0..0bf1c6905a880bf26233db777d8d35aa3985cf19`.
- Verdict: `NOT REVIEW-CLEAN / NOT MERGE-READY` despite focused rollup `25/25` and authoritative `SUITES PASS=23 FAIL=0`.
- P1: deleting either `markdown_sha256` or `chunk_bytes` from a real delivered receipt still authorized public success and local-view rewriting because both fields were optional and missing chunking fell back to the ambient default.
- P1: a symlink at a receipt-backed deterministic canonical batch name was rejected by `O_NOFOLLOW` recovery, remained canonical, and permanently wedged every replay.
- P2: a deterministic name swap between quarantine validation and `rename()` moved an unbound replacement before post-rename detection.
- P2: Home could say `Answers recorded` while every decision was pending and another feed required attention because the H1 ignored `combinedHomeState()`.
- Disposition: all four accepted and independently RED-reproduced. The repair requires both receipt identity fields before any rewrite; opens and inode-binds the symlink entry itself without following its target; verifies and restores a raced moved replacement; and derives the global Home H1 from combined attention. Targeted 4/4, rollup 29/29, browser 254, and static checks are green. The authoritative repair gate and a new exact-head verdict remain pending.
- Evidence: `records/evidence/rollup-answer-final-boundaries-red-green.txt`.

## Final attempt

- Status: seventh frozen-head audit **REVIEW-CLEAN / MERGE-READY** at code head `78672c46d94041f974ca97b0d2cfe5596c6b020a` only. Codex Sol was usage-limited; Cursor independent auditor `9db69b00-966c-43d3-b1eb-72181b949178` substituted. PR #11 exists; main merge conflicts resolved in the finish session (attention-lane + answered-pending preserved). This historical verdict does not certify later source, convergence, or PR heads.
- Historical full-gate evidence: `records/evidence/rollup-answer-receipt-entry-full-green.txt` (`SUITES PASS=23 FAIL=0`, rollup 25/25).
- Current focused evidence: `records/evidence/rollup-answer-final-boundaries-red-green.txt` (targeted 4/4, rollup 29/29, browser 254; records the live macOS `O_SYMLINK` RED and its repair).
- Current authoritative evidence: `records/evidence/rollup-answer-final-boundaries-full-green.txt` (`SUITES PASS=23 FAIL=0` at exact repair head `78672c46d94041f974ca97b0d2cfe5596c6b020a`; rollup 29/29; browser 254; OpenSpec 2/0).
- Seventh audit packet: `records/audit-packets/2026-07-24-rollup-answer-seventh-frozen-head.md`.
- Post-merge focused re-gates (2026-07-24 finish): rollup 29/29, ER-134 62/0, browser 254, attention-lane 5/0.
- Did not verify: merged-main install/deploy, provider delivery, or live-store behavior; live card `decision:a6f185b53cbc1278499b062d` remains for the merge sitting.

## Attempt 7 — Cursor frozen-head successor (Codex unavailable)

- Audit task: Cursor code-reviewer `f84e6b96-c741-495e-8163-d193af78bed3` / session `9db69b00-966c-43d3-b1eb-72181b949178`.
- Reviewed range: frozen code `78672c46d94041f974ca97b0d2cfe5596c6b020a` (tip `c3af26b` docs-only).
- Verdict: `REVIEW-CLEAN / MERGE-READY`.
- Seven-point contract: all PASS. Prior P1/P2 classes 1–6: all REPAIRED. New merge blockers: none.
- Evidence: parent rollup 29/29 OK; OpenSpec strict valid; packet above.

## Audited Chat

- Audited chat name: Execute Phase 0 hardening backlog.
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/global-implementations`.
- Provider: Codex (finished by Cursor).
- Full ID: `019f73d8-e5dc-73a0-acc5-8a4916ac6819`.
- Resolved transcript: `/Users/gillettes/.codex/sessions/2026/07/17/rollout-2026-07-17T23-10-22-019f73d8-e5dc-73a0-acc5-8a4916ac6819.jsonl`.

No live store, provider send, install, deployment, plist, launchd, or main-branch merge was performed by the auditor or finish session. Branch-only PR updates and conflict resolution only.

## Post-audit convergence handoff

- Later source repairs: attention/feed repair
  `60577b78fa32b48f10580796f94aacdb16a1fb19` and validation-before-write repair
  `fdb838dd6d7520646541c9bf95e2a7901c8c2d58`.
- Convergence containment: `bd83a30` and `4453b8e` on
  `codex/repo-convergence-019ff2ae`. PR review and hosted-CI repair is
  `2bfda6afe0ee839dc498cf27820febfde543dbde`.
- Separate verification: exact source head `fdb838d` passed `SUITES PASS=26 FAIL=0`.
  Convergence repair passed rollup `32/32`, dashboard `91/0`, browser
  315, panel `13/0`, native summary `16/0`, and every affected owner suite.
  Final records-head authoritative and hosted verification remain landing gates.
- Work Record: `todo.md`, “2026-08-12 — PR review and hosted-CI repair.”
- Completed index: `todo.md`, “Lane D source implementation and review repair.”
- Issue and branch ledger: `self-contained:` repository convergence in Active
  Next Steps and `codex/repo-convergence-019ff2ae` in Active Branch Ledger.
- Self-audit: behavioral findings were mutation-reproduced before repair.
  Historical evidence commands were corrected without rewriting their outcomes.
  No install, provider send, live-store mutation, merge, ref deletion, or
  worktree cleanup occurred during reconciliation.
- Ripple Check: `STATE.md`, the Rollup Answer OpenSpec tasks, verification and
  retrospective, the convergence record, audit packet, Active Next Steps,
  Completed, Branch/Audit/Test/Feedback ledgers, and evidence records were
  reconciled together. Product intent, V2 gates, and runtime activation remain
  unchanged.
