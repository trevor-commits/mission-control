# 2026-07-18 — Phase 0 rollup-answer CLI work record

- Problem: Mission Control needed one operator answer to reach only strictly equivalent rollup members while leaving each member open until verified owner consumption. The first independently audited implementation then proved two false-success paths: mutable post-commit publication could diverge from its database receipt, and the public command could succeed while Home/Morning Brief still read the pre-answer feed.
- Reasoning: Answering is durable operator direction, not completion. The database receipt and private batch therefore need one reproducible identity, every path-visible success must bind to held verified bytes, and public CLI success must include the local actionable feed while provider egress remains disabled.
- Diagnosis inputs: approved seven-point OpenSpec/HOTL contract; `scripts/queue_admission.py`, `scripts/decision-alert`, `scripts/compose-decision-prompt.py`, `scripts/dashboard`, Morning Brief consumers; independent Codex audit `019f762c-c815-77b3-97c0-021c66fd3b7e`; upstream Claude audit `6b78e170-f063-47e2-92f8-48e6f5ce0600`.
- Approval provenance: `thread_goal_updated` at `2026-07-18T14:47:59.770Z` on Codex thread `019f73d8-e5dc-73a0-acc5-8a4916ac6819`, with goal text beginning “Yes thoroughly Approve the seven-point answered_pending contract and resume Lane D.”
- Implementation inputs: commits `754de93`, `ed8ce35`, `953de86`, `daa8c72`, and audit repair `34687c9`; OpenSpec change `rollup-answer`; temporary Mission Control homes/stores and fake sender/collector fixtures only.
- Fix: added current-fingerprint immutable `answered_pending`, strict targeting, exact per-member consumption, deterministic private batches, persisted canonical manifest digest, fd-bound pre/post-commit verification, quarantine plus exact replay, public `answer-rollup`, strict/no-send decisions-feed refresh, and pending-aware local presentation.
- Self-audit:
  - method: red-before-green behavior probes, focused rollup suite, authoritative `scripts/verify.sh`, strict OpenSpec, Python/macOS Bash 3.2 syntax, browser 253, source-artifact and diff checks, plus independent same-model audit.
  - outcome: audit-repair focused suite `14/14`; authoritative verifier `SUITES PASS=23 FAIL=0`; both P1 findings reproduced and repaired; no schema migration or dependency added.
  - did not verify: final repaired-head independent verdict, hosted PR checks, merged-main behavior, install/deploy, provider delivery, or live-store behavior because those remain pending or explicitly prohibited.
- Ripple Check: reconciled production writer/composer/dashboard behavior with rollup OpenSpec, HOTL, `STATE.md`, todo Work/Test/Feedback/Branch ledgers, evidence, audit record, and PR packet; project intent and repo-only Linear posture remain unchanged. This repository has no separate `PROJECT_MEMORY.md` convention; `todo.md` is its declared operational-memory surface.
- by: Codex `019f73d8-e5dc-73a0-acc5-8a4916ac6819`.
- triggered by: Phase 0 overnight packet plus Trevor's explicit answered-pending approval and independent-audit corrections.
- led to: repaired candidate awaiting one new same-model/max frozen-head audit, then branch-only PR closeout; no main/live action.
- linear: self-contained; Mission Control remains repo-only because no team/prefix is configured.
