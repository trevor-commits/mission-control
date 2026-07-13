## 1. Governance and baseline

- [x] 1.1 Resolve the audited Fable plan, U1-U7 upgrades, repo contracts, branch state, and current baseline verification.
- [x] 1.2 Create the ER-107 OpenSpec design/specs and Mission Control branch/todo pointers.
- [x] 1.3 Create and lint the root HOTL micro-workflow; keep it authoritative for step-level execution.

## 2. Phase 0 reliability repairs

- [x] 2.1 Repair the systemic T7-backed LaunchAgent path failure in the owning third-party repo/runtime, add a removable-media path validator, and prove loaded jobs no longer fail with exit 126 (`bbed5e3`, `bd7226e`, `1326217`, pushed and installed).
- [x] 2.2 Fix Morning Health's stale whole-log denial detection, add a stable last-run marker, and register the job in Mission Control (`bd7226e`, `ab693c6`; current run segment has no exit 126 or fresh TCC denial).
- [x] 2.3 Fix improvement-loop provider-wrapper false positives, group digest findings before capping, quarantine proven false lessons/queue entries, and verify real corrections still work (`5f01334`, pushed to global `main`; nine false signatures quarantined and real correction fixtures retained).
- [x] 2.4 Create/update the eight Morning Brief prior-art source cards on the third-party repo's required branchless main path (`b0075a6`, pushed).

## 3. Shared privacy and graph substrate

- [x] 3.1 Add failing field-matrix tests for every model/storage/error/sidecar/notification egress boundary.
- [x] 3.2 Implement the shared field-aware egress module and migrate current chat-graph redaction callers.
- [x] 3.3 Add idempotent graph migration for node kind, outcome cards, kind-salted item keys, update/resolution evidence, and bounded open-end change export.
- [x] 3.4 Prove repo-node preservation, provider allowlisting, unknown-source safety, explicit-only resolution, row preservation, and future-version refusal.

## 4. Distinct automation history

- [x] 4.1 Add failing tests for trusted run identity, repeated-poll dedupe, streak resets, unknown history, concurrency, restart, cap, schedule math, and glob evidence.
- [x] 4.2 Implement atomic distinct-run history, next-run estimates, evidence globs, and honest history confidence.
- [x] 4.3 Extend Automation rendering/fixtures with next run, distinct-run strip, streak, and copyable run command.

## 5. Deterministic thin Morning Brief

- [x] 5.1 Add failing tests for minimal Git change facts, open-end new/resolved/aging change events, compound high-water cursors, input cadence/freshness, section order, caps, and source-quality labels.
- [x] 5.2 Implement deterministic composition to atomic Markdown and structured `latest.json`, with preview never advancing delivery state.
- [x] 5.3 Add `dashboard brief --print`, dashboard feed collection, Home rendering, fixtures, and render/browser proof.

## 6. Delivery and deadman

- [x] 6.1 Add failing tests for fixed-argv send, field-aware chunks, brief/chunk identity, partial-send retry, completed-send no-op, failed-send cursor retention, and scrubbed launchd environment.
- [x] 6.2 Implement `--send`, per-chunk receipts, delivery status, dedupe, and the operator-ordered 5:00 AM fully-expanded launchd template.
- [x] 6.3 Implement and test the independent 5:20 delivery deadman, throttling, direct redacted failure path, and registry/installer wiring.
- [x] 6.4 Complete the high-risk privacy/side-effect review gate before the first authorized live transcript egress or Telegram proof.

## 7. Session outcomes and coverage calibration

- [x] 7.1 Add synthetic real-shape Tier 1 fixtures for reply-v5, Codex closeout, audit report, handoff packet, unstructured tail, late closeout, and unknown provider.
- [x] 7.2 Implement bounded Tier 1 outcome parsing, stable cards, explicit-resolution evidence, late-update events, and additive export.
- [x] 7.3 Implement zero-call seven-day coverage planning with grammar/provider counts and projected calls/tokens/quota impact.
- [ ] 7.4 After privacy proof and explicit provider authorization, run a small bounded provider sample; record actual tokens/latency; configure observed caps before any bounded backfill. Outcome Extractor activation remains a separate explicit decision; deterministic scheduled brief delivery does not imply it.
- [x] 7.5 Implement isolated cached Tier 2 extraction with provider kill switches, OAuth-lock defer, budget fail-open, closed taxonomy output, deterministic session/repo/lineage context, inferred-only queue lifecycle, bounded sample/calibration tooling, scheduled-job template, and slow-model concurrency proof. Live provider sampling and Outcome Extractor activation remain gated rather than being implied by code completion.

## 8. Transactional decision queue

- [x] 8.1 Add concurrency/idempotence tests for sync, alert, dismiss, explicit resolution, recurrence, restart, and duplicate ingest.
- [x] 8.2 Implement the SQLite WAL decision store, structured/inferred trust split, cross-session high-recall persistence, and exact resolution evidence.
- [x] 8.3 Implement deduplicated fixed-argv alerts, `dashboard decide dismiss`, queue feed, and pinned Home rows.

## 9. Outcome-enriched brief

- [x] 9.1 Add Tier 1 and code-only Tier 2 outcome/decision enrichment to the already-working brief; model-only follow-ups remain outside NEEDS YOU and all live Tier 2 use remains gated by calibration.
- [x] 9.2 Prove visible Confirmed/Inferred provenance, deterministic commands/SHAs/IDs, provider-scope honesty, top-N ranking, late updates, and LLM-disabled fallback.

## 10. Structured Git facts and safe runner

- [x] 10.1 Implement and test branch-level Git facts, sanitized remotes, all refusal reasons, activity freshness, and explicit refspec proposals.
- [x] 10.2 Implement the DISABLE-aware default-dry-run runner with only the named safe tier and exact before/after JSONL logs.
- [x] 10.3 Run one real live-ledger dry-run and have a separate reviewer inspect every proposed action; do not enable automatic push (56 repositories, 23/23 correctly refused, Git facts unchanged, review-clean).

## 11. Integrated verification and audit

- [x] 11.1 Run every existing and new suite, syntax/static/privacy checks, OpenSpec validation, and mutation/negative controls.
- [x] 11.2 Install into an isolated then canonical local runtime, collect feeds, capture Home/Automation/Brief browser proof, and verify rollback (final installed code from `main` at `2432d6e`; LaunchAgent manifests unchanged).
- [x] 11.3 Complete one authorized manual delivery receipt and a safe deadman failure-path proof without exposing secrets (2026-07-10 brief `20260710-e0b7a9ca4b16`, 2/2 receipt; isolated scratch deadman proof).
- [x] 11.4 Run independent post-implementation Codex audits against the actual diff/evidence, implement findings, and iterate until review-clean or explicit deferred risk (`records/morning-brief-independent-codex-audit.md`; Tier 2 iteration ledger `records/morning-brief-tier2-codex-audit.md`).
- [x] 11.5 Commit and push every owning repo change for the original 2026-07-09 implementation closeout with final dirty-state and multi-repo landing evidence (original Mission Control convergence through `cf6b536`; bounded Tier 2 implementation `df991b4`; Tier 2 audit records `ef281a5`; global ER-107 `4a3e425`; all pushed on `origin/main`, with the prior topic branch/worktree removed after merge).
- [x] 11.6 Complete the 2026-07-11 final-gate immutable audit, land the exact reviewed candidate on canonical `main`, reinstall and verify the exact current-main SHA/stamp without provider delivery, and clean superseded branches/worktrees (`1261c48` independently code/runtime `READY` and records/provenance `review-clean`; exact closeout commit installed before push).

## 12. Elapsed live proof and convergence

- [ ] 12.1 Record approximately five real mornings of read/action/comprehension evidence; tune noise without weakening trust invariants.
- [ ] 12.2 Produce the subsume/keep/fold decision for each existing notification/report surface, distinguishing Telegram, macOS notifications, local reports, and discarded output.
- [ ] 12.3 Mark ER-107 verified, archive OpenSpec with Ripple/Completed-index updates, and complete final independent audit only after elapsed proof exists.
