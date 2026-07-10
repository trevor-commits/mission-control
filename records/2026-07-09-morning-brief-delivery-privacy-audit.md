# Morning Brief delivery and privacy audit

Date: 2026-07-09
Verdict: review-clean for the delivery/deadman/privacy slice

## Audited Chat

- Audited chat name: Mission Control orchestration priorities
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Claude/Fable
- Full ID: `35d96de4-9509-4382-b1a0-10b9a4d1777e`
- Transcript: `/Users/gillettes/.claude/projects/-Users-gillettes-Coding-Projects-global-implementations/35d96de4-9509-4382-b1a0-10b9a4d1777e.jsonl`
- Linked Fable plan session: `6f306a0b-abbb-4d39-9d64-afa7fb977250`

## Scope

Independent read-only review covered Morning Brief composition, delivery,
receipts, retries, delivery/deadman locking, launchd wiring, dashboard freshness,
automation run identity, and every error/sidecar/notification egress boundary.
No live Telegram message or live Mission Control LaunchAgent mutation occurred.

## Findings closed

The first pass found seven blocking defects: substring label matching skipped the
main job, yesterday's brief could satisfy today's deadman, concurrent sends could
duplicate a chunk, raw cursor IDs could enter the sidecar, secrets could straddle
chunk boundaries, old briefs could be relabeled fresh, and mutable `latest.json`
was incorrectly used as a distinct-run marker.

Follow-up passes found and closed additional defects: malformed Brief timestamps
did not fail closed; compose could race delivery and split marker/receipt identity;
egress counters were test-only; a preserved last-good feed hid a current refresh
error; and raw feeder stderr could persist secrets/PII into error JSON and JS.

Each accepted finding became a regression. The final implementation uses exact
launchd label checks, same-local-day delivery proof, shared stale-recoverable state
locks, whole-message screening before chunking, sanitized cursor high-water marks,
a once-per-compose marker, strict Brief timestamp validation, content-free compose
and delivery egress counters, current error overlays over preserved last-good data,
and the shared ERROR policy before any error artifact is written.

## Verification

- Morning Brief compose, delivery, deadman, shared egress, dashboard, automation
  history, render-smoke, syntax, plist, strict OpenSpec, HOTL lint, and whitespace
  checks pass.
- Dashboard suite: `PASS=26 FAIL=0`.
- Independent adversarial replays passed for concurrent send/compose, previous-day
  delivery, malformed timestamps, stale feed truth, chunk-boundary secrets, error
  JSON/JS persistence, and content-free counters.

## Residual risk

Operational proof remains separate: canonical Mission Control installation, one
explicitly authorized Telegram delivery, a safe deadman failure-path exercise,
installed browser evidence, rollback evidence, and approximately five natural
mornings. Review-clean here does not claim those elapsed or external side effects.

