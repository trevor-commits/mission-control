# Morning Brief verification

Date: 2026-07-09
State: deterministic Tier 1 and code-only Tier 2 are implemented; live egress, activation, delivery, and elapsed gates remain open

## Scope verified

- Phase 0 source repairs: the stable internal LaunchAgent runtime, bounded Morning Health evidence, and improvement-loop provider-wrapper filtering.
- Field-aware privacy, additive chat-graph migration, distinct automation run history, and deterministic open-work changes.
- Atomic Markdown and structured Morning Brief output, installed dashboard feeds, and LLM-disabled fallback.
- Resumable fixed-argv delivery and independent deadman implementation without activating Telegram or launchd schedules.
- Bounded zero-call Tier 1 outcome cards for Claude, Codex, Cursor, Copilot, and Hermes.
- Isolated cached Tier 2 outcome classification for high-value sessions, including a closed code taxonomy, strict local schema/cache/config validation, deterministic session/repo/lineage context, inferred-only follow-up lifecycle, global/provider kill switches, Haiku-to-Sonnet ambiguity escalation, OAuth-lock defer, budget fail-open, content-free health, and a 06:40 inactive LaunchAgent template.
- Transactional decision identity, persistence, recurrence, retryable alerts, dashboard dismissal, and graph-backed exact resolution.
- Structured Git facts and the DISABLE-aware default-dry-run loose-end runner.

## Requirement evidence

| Capability | Evidence | Result |
|---|---|---|
| Field-aware egress | `scripts/mission-control-common.test.sh`, delivery/deadman suites, synthetic secret/path/error fixtures | Pass; content is screened at persistence, sidecar, alert, and notification boundaries. |
| Automation run history | `scripts/automation-status.test.sh`, dashboard suite and render smoke | Pass; repeated polls do not invent runs, histories remain bounded, and activation-gated jobs render as awaiting activation rather than failures. |
| Fleet Morning Brief | `scripts/morning-brief.test.sh`, `scripts/morning-brief-delivery.test.sh`, `scripts/morning-brief-deadman.test.sh` | Pass; deterministic compose, atomic sidecar, freshness, resumable receipts, and deadman behavior are covered. |
| Session outcome cards | `scripts/chat-graph.test.sh`, `scripts/outcome-coverage.test.sh`, `scripts/outcome-extractor.test.sh`, `scripts/decision-alert.test.sh`, `scripts/morning-brief.test.sh`, independent counterexample audits | Pass for Tier 1 and synthetic/code-only Tier 2. Exact model schema/config/cache boundaries fail closed; audit lineage and late updates carry deterministic context; inferred rollback/re-enable and human dispositions are covered; model latency never holds ingest; live sampling remains gated. |
| Operator decisions | `scripts/decision-alert.test.sh`, dashboard suite, installed Home capture | Pass; one coherent `NEEDS YOU` block produces one pinned decision and exact evidence controls closure. |
| Structured Git facts | `scripts/scan-unfinished-work --self-test` | Pass; branch/ref/worktree/remote facts fail closed and credential-bearing remotes are rejected. |
| Safe loose-end runner | `scripts/loose-end-runner.test.sh`, real 56-repository dry-run, independent review of all 23 candidate records | Pass; every candidate was correctly refused, every argv was null, and normalized before/after facts were identical. |

## Cold verification

The final worktree pass completed successfully:

- `bash scripts/chat-graph.test.sh`
- `bash scripts/automation-status.test.sh`
- `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell` (`PASS=30 FAIL=0`)
- `node --check scripts/dashboard-render-smoke.js`
- `node scripts/dashboard-render-smoke.js .` (all seven tabs)
- `bash scripts/usage-snapshot.test.sh`
- `bash scripts/scan-unfinished-work --self-test`
- `bash scripts/mission-control-common.test.sh`
- `bash scripts/morning-brief.test.sh`
- `bash scripts/morning-brief-delivery.test.sh`
- `bash scripts/morning-brief-deadman.test.sh`
- `bash scripts/outcome-coverage.test.sh`
- `bash scripts/outcome-extractor.test.sh`
- `bash scripts/decision-alert.test.sh`
- `bash scripts/loose-end-runner.test.sh` (`PASS=32`)
- Python compilation, shell syntax, committed-fixture JSON validation, HOTL document lint, strict OpenSpec validation, and `git diff --check`

The Tier 2 suite uses synthetic transcripts and a fixed local model stub. It makes no network call and proves global/provider/sample/test disables, high-value selection, a separate lock, budget zero, sanitized stdin, fixed argv, canonical code-only cache reuse, exact response validation, deterministic context/lineage, inferred queue separation and reversible lifecycle, ambiguity-only Sonnet escalation, bounded calibration/config parity with export, exit-75 defer, invalid-output fail-open, and slow-model/ingest concurrency.

## Live and installed evidence

- The zero-call live parser migration produced parser-v5 cards without model calls and retained prior observation history.
- The live installed queue contains one coherent pinned decision rather than the fragmented fenced-procedure representation found during browser review.
- The real loose-end dry-run inspected 56 repositories and emitted 23 correctly refused records in `/tmp/morning-brief-runner-live-dry-run.jsonl`; automatic push remains unavailable.
- Code-only installation created a rollback backup at `/private/tmp/mission-control-before-morning-brief-20260709-214023`. The backup was restored byte-for-byte, the implemented runtime was preserved at `/private/tmp/mission-control-implemented-pre-canonical-20260710T053440Z`, and canonical `main` was reinstalled from commit `2432d6e`.
- LaunchAgent manifests were identical across rollback and both canonical installs; the final inventory contained 55 unchanged plist hashes. No Morning Brief job or Telegram schedule was installed.
- The new outcome-extractor LaunchAgent exists only as a source template. It has not been copied, bootstrapped, or run against a live transcript; missing calibrated caps therefore cannot be mistaken for completed live proof.
- Final browser proof under `tmp/playwright/morning-brief-final-{home,brief,automation}.png` rendered Home, Brief, and Automation. Morning Brief and deadman explicitly say `awaiting activation` and have no run command; the existing unrelated Morning Health attention state remains visible rather than being hidden.
- A final installed-browser pass exposed a token-family prefix in source prose and ambiguous activation scheduling. Commit `2432d6e` now consumes the entire optional token suffix at both shared and display boundaries, makes activation state override stale next-run timestamps, and carries adversarial render regressions; independent recheck returned review-clean.

## Self-audit and ripple check

- Privacy: no live transcript or secret-bearing model egress was enabled. Synthetic fixtures cover narrative, action, errors, temporary data, sidecars, notification chunks, model stdin/argv/cache/config/health, prefix-only token documentation, and complete synthetic token suffixes.
- State changes: graph migrations are additive; outcome observations are immutable; decisions use WAL transactions; delivery receipts and cursors use locks and atomic replacement.
- Scope: automatic push, live Tier 2 provider sampling/backfill, live Telegram delivery, and scheduled activation remain outside this implementation closeout.
- Human surface: browser inspection found and drove fixes for split decision text, inline section-boundary leakage, activation-gated jobs falsely appearing failed or scheduled, and token-family prefixes leaking from source prose.
- Rollback: restore the private runtime backup, reinstall the prior code, and preserve graph/decision archives rather than deleting state.
- Coherence: the same outcome/decision feeds drive the dashboard and brief; no parallel tracker was introduced.

## Open proof gates

1. Authorize and record one real Telegram delivery receipt plus a safe deadman failure-path proof.
2. Approve and measure a small privacy-screened provider sample, review content-free token/latency evidence, and apply observed caps before any live Tier 2 backfill.
3. Explicitly decide whether to activate the Outcome Extractor, Morning Brief, and deadman LaunchAgents; no schedule was installed by this work.
4. Record approximately five natural mornings of comprehension/action evidence, decide which older notifications to subsume/keep/fold, rerun the final audit, then mark the OpenSpec change verified and archive it.

These are external, authorization, or elapsed-evidence gates. They do not invalidate the completed deterministic implementation, but they prevent claiming the overall Morning Brief program verified.
