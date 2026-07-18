# Phase 0 queue repair and answer-return path

## 2026-07-17 — Phase 0 queue repair and answer-return path

- Problem: Mission Control's 2026-07-17 Phase 0.3 queue repair and Phase 0.2 answer-return path were represented only by a one-line `todo.md` receipt. The repo's continuity contract requires a dated Work Record, and the central conductor receipt overstated three proof boundaries: the security bypass was described like an automatic notification path, preview output with `sent_count: 0` was presented as send evidence, and an exercised additive install path was presented as a tested full revert.
- Reasoning: preserve the existing receipt as historical evidence, synthesize the missing record only from the named implementation/merge commits and the central `origin/main` receipt, and separate code capability, prior live evidence, and unverified rollback claims.
- Diagnosis inputs:
  - Queue commits: `dcbfb833dea1a76deb0439c4697c3887f79fb187`, `d4759edcb765cdf2bddc17cc8b9b8f59d5b99ff7`, and `10d74514f9d3eae0a462d4405f64921b87b9c25c`.
  - Answer-path commits: `8f2b7ccac2d020188577c66088de9c0e90de92ec` and `c109bd08e368649171a5a797c1a8219c9b1e6989`.
  - Merge commits: `c514a4d5b1432158027e8003bcd9b8ee89156a3f`, `f554f963645428fa0d8c74b84f9c645d5e9b456c`, and `56fa588a706b25b4b06cee3631a8336c085b82df`.
  - Central receipt: `global-implementations` `origin/main` file `records/2026-07-17-phase0-live-fire-execution.md`, including its independent-audit addendum, last changed by `a9f9f90` and read at `origin/main@02802e2b4b00b05275895211beb1ba7618d63787`.
- Implementation inputs:

| Evidence | Supported conclusion |
|---|---|
| `dcbfb83` | Added `queue_admission.py` to every throwaway dashboard-install fixture repository and recorded the five green source suites. |
| `d4759ed` | Added normalized-text group re-ask suppression for seven days, preserved per-decision cadence, and recorded severity-escalation events. |
| `8f2b7cc` | Threaded optional source provenance and resume-chat/provider metadata through dismiss/answer without changing the decision state machine. |
| `c109bd0` | Replaced generic `send` with `decision-send`; documented that Mobile Connect's hand-crafted callback stub could not detect the unwired button-generation caller. |
| `10d7451` | Added idempotent one-shot admission backfill and schema-presence steady-state stamping; its copied-store proof stamped 55 rows then 0 on rerun. |
| `c514a4d` | Merged advisory admission classification, presentation rollup, strict action + owner + target supersession planning, lanes, manual targeted alert bypass, and group suppression. |
| `f554f96` | Merged source provenance, decision-send wiring, and resume-chat return metadata. |
| `56fa588` | Merged admission backfill and steady-state stamping. |
| Central receipt | Recorded the historical live/copy evidence: 113/113 open rows classified, 91 cards, lane counts 12/2/82/17, copied-store backfill idempotency, and cloned-store dismiss provenance. |

- Fix:
  - Added this repo-native dated Work Record and linked it from the project ledger.
  - Preserved the queue authority boundary: admission class, domain, severity, rollup, and authority-envelope fields are advisory data. `queue_admission.py` has no execution authority, and WorkOrder publication remained deferred.
  - Preserved presentation density without silently merging ownership: rollup groups normalized text, while answer fan-out may supersede another member only when action, originating owner/session, and backtick-identified target are all determinable and equal. Unknown or different fields fail closed to independent handling.
  - Described current answer semantics honestly: dismiss/answer records optional source provenance; answer prompts can carry resume chat/provider metadata; the current transaction immediately resolves the decision. A distinct answered-pending-consumption state remains unimplemented and is blocked on the explicit design decision recorded by Lane D.
  - Corrected the integration boundary: `decision-send`, not generic `send`, generates the inline buttons and last-decision fallback state.
  - Audit correction — security bypass: severity classification can mark an active incident as `security`, but the bypass is a **manual per-decision capability** (`decision-alert alert --decision-id ... [--send]`). The named merged source contains no automatic security-to-ping caller.
  - Audit correction — preview receipt: the central receipt's `sent_count: 0` was **preview-mode output**. Without `--send`, the CLI builds would-send text but performs no external send; that output proved eligibility/presentation, not delivery.
  - `revert tested: no — additive schema + install path exercised twice; full revert not performed.`
- Self-audit:
  - method: resolved all eight named commits as commits contained by current `origin/main`; read each commit body and diff summary; read the central receipt and independent-audit addendum from `global-implementations` `origin/main`; inspected the targeted-bypass parser/call sites and preview return path at merge `c514a4d`; checked the record and ledger diff with `git diff --check`; allowed the repo's mandatory pre-push `/bin/bash scripts/verify.sh` to run against hermetic fixtures; ran `PYTHONDONTWRITEBYTECODE=1 python3 scripts/queue_admission.test.py` separately.
  - outcome: the dated record now distinguishes implementation, current terminal-answer behavior, historical test/live evidence, corrections, and deferred work without rewriting the original one-line receipt. The current branch verifier passed all 21 suites, including dashboard 67/0, decision-alert ALL PASS, ER-134 57/0, browser 253 assertions, OpenSpec, and static syntax gates. The standalone queue-admission suite separately passed 24/24.
  - did not verify: historical exact-commit suites were not individually replayed, and no installed runtime, live decision store, alert delivery, schema migration, backfill, install, or revert was exercised in this documentation-only branch. Prior live/copy results are attributed only to the central receipt and named commits. The rollup-answer CLI was still deferred at the source receipt boundary and is not claimed here.
- by: Codex `019f73d8-e5dc-73a0-acc5-8a4916ac6819`
- triggered by: Phase 0 hardening Lane C2 corrective-receipt packet
- led to: a reviewable corrective-record PR and the separately isolated `codex/rollup-answer-wiring` implementation lane
- linear: self-contained; repo-only
