# Morning Brief verification

Date: 2026-07-09
State: implemented for the deterministic Tier 1 slice; external and elapsed gates remain open

## Scope verified

- Phase 0 source repairs: the stable internal LaunchAgent runtime, bounded Morning Health evidence, and improvement-loop provider-wrapper filtering.
- Field-aware privacy, additive chat-graph migration, distinct automation run history, and deterministic open-work changes.
- Atomic Markdown and structured Morning Brief output, installed dashboard feeds, and LLM-disabled fallback.
- Resumable fixed-argv delivery and independent deadman implementation without activating Telegram or launchd schedules.
- Bounded zero-call Tier 1 outcome cards for Claude, Codex, Cursor, Copilot, and Hermes.
- Transactional decision identity, persistence, recurrence, retryable alerts, dashboard dismissal, and graph-backed exact resolution.
- Structured Git facts and the DISABLE-aware default-dry-run loose-end runner.

## Requirement evidence

| Capability | Evidence | Result |
|---|---|---|
| Field-aware egress | `scripts/mission-control-common.test.sh`, delivery/deadman suites, synthetic secret/path/error fixtures | Pass; content is screened at persistence, sidecar, alert, and notification boundaries. |
| Automation run history | `scripts/automation-status.test.sh`, dashboard suite and render smoke | Pass; repeated polls do not invent runs, histories remain bounded, and activation-gated jobs render as awaiting activation rather than failures. |
| Fleet Morning Brief | `scripts/morning-brief.test.sh`, `scripts/morning-brief-delivery.test.sh`, `scripts/morning-brief-deadman.test.sh` | Pass; deterministic compose, atomic sidecar, freshness, resumable receipts, and deadman behavior are covered. |
| Session outcome cards | `scripts/chat-graph.test.sh`, `scripts/outcome-coverage.test.sh`, independent parser-v5 counterexample audit | Pass for Tier 1; parser supersession requires the same selected message and sanitized content hash. Tier 2 remains gated. |
| Operator decisions | `scripts/decision-alert.test.sh`, dashboard suite, installed Home capture | Pass; one coherent `NEEDS YOU` block produces one pinned decision and exact evidence controls closure. |
| Structured Git facts | `scripts/scan-unfinished-work --self-test` | Pass; branch/ref/worktree/remote facts fail closed and credential-bearing remotes are rejected. |
| Safe loose-end runner | `scripts/loose-end-runner.test.sh`, real 56-repository dry-run, independent review of all 23 candidate records | Pass; every candidate was correctly refused, every argv was null, and normalized before/after facts were identical. |

## Cold verification

The final worktree pass completed successfully:

- `bash scripts/chat-graph.test.sh`
- `bash scripts/automation-status.test.sh`
- `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell` (`PASS=29 FAIL=0`)
- `node --check scripts/dashboard-render-smoke.js`
- `node scripts/dashboard-render-smoke.js .` (all seven tabs)
- `bash scripts/usage-snapshot.test.sh`
- `bash scripts/scan-unfinished-work --self-test`
- `bash scripts/mission-control-common.test.sh`
- `bash scripts/morning-brief.test.sh`
- `bash scripts/morning-brief-delivery.test.sh`
- `bash scripts/morning-brief-deadman.test.sh`
- `bash scripts/outcome-coverage.test.sh`
- `bash scripts/decision-alert.test.sh`
- `bash scripts/loose-end-runner.test.sh` (`PASS=32`)
- Python compilation, shell syntax, committed-fixture JSON validation, HOTL document lint, strict OpenSpec validation, and `git diff --check`

There is intentionally no `outcome-extractor.test.sh`: the model-backed Tier 2 extractor is not implemented until the bounded provider/privacy calibration gate is approved and measured.

## Live and installed evidence

- The zero-call live parser migration produced parser-v5 cards without model calls and retained prior observation history.
- The live installed queue contains one coherent pinned decision rather than the fragmented fenced-procedure representation found during browser review.
- The real loose-end dry-run inspected 56 repositories and emitted 23 correctly refused records in `/tmp/morning-brief-runner-live-dry-run.jsonl`; automatic push remains unavailable.
- Code-only installation preserved LaunchAgent hashes and created a rollback backup at `/private/tmp/mission-control-before-morning-brief-20260709-214023`.
- Browser proof under `tmp/playwright/` rendered Home, Brief, and Automation. Morning Brief and deadman appear as awaiting activation; the existing unrelated Morning Health attention state remains visible rather than being hidden.

## Self-audit and ripple check

- Privacy: no raw transcript or secret-bearing model egress was enabled. Synthetic fixtures cover narrative, action, errors, temporary data, sidecars, and notification chunks.
- State changes: graph migrations are additive; outcome observations are immutable; decisions use WAL transactions; delivery receipts and cursors use locks and atomic replacement.
- Scope: automatic push, model-backed Tier 2 extraction, live Telegram delivery, and scheduled activation remain outside this implementation closeout.
- Human surface: browser inspection found and drove fixes for split decision text, inline section-boundary leakage, and activation-gated jobs falsely appearing failed.
- Rollback: restore the private runtime backup, reinstall the prior code, and preserve graph/decision archives rather than deleting state.
- Coherence: the same outcome/decision feeds drive the dashboard and brief; no parallel tracker was introduced.

## Open proof gates

1. Authorize and record one real Telegram delivery receipt plus a safe deadman failure-path proof.
2. Approve and measure a small privacy-screened provider sample before implementing Tier 2 extraction.
3. Explicitly decide whether to activate the Morning Brief/deadman LaunchAgents; no schedule was installed by this work.
4. Record approximately five natural mornings of comprehension/action evidence, decide which older notifications to subsume/keep/fold, rerun the final audit, then mark the OpenSpec change verified and archive it.

These are external, authorization, or elapsed-evidence gates. They do not invalidate the completed deterministic implementation, but they prevent claiming the overall Morning Brief program verified.
