## Why

Mission Control already collects chat relationships, open work, Git state, job health, and usage, but Trevor still has to reopen transcripts and reconcile several messages to understand what the AI fleet accomplished and what needs him. The Morning Brief turns those existing facts, plus bounded session outcomes, into one trustworthy daily decision surface. It ships useful deterministic value before the LLM enrichment and keeps working when model extraction is unavailable.

## What Changes

**Morning comprehension surface**
- From: raw facts are split across dashboard tabs, transcripts, nightly review, delegation reports, and several notifications.
- To: one NEEDS-YOU-first brief is available in a local file, dashboard, CLI, and short Telegram lead.
- Reason: the product goal is 60-second comprehension, not another data feed.
- Impact: additive Mission Control capability; existing feeds and tabs remain compatible.

**Session outcomes and decisions**
- From: chat graph records relationships and coarse open ends, not trustworthy plain-language outcomes or unanswered decisions.
- To: bounded deterministic parsing plus isolated budgeted LLM rewriting produces provenance-marked outcome cards and an evidence-gated decision queue.
- Reason: chat work is the missing input required to explain what the fleet did.
- Impact: additive SQLite schema and export fields; no LLM work enters the collector lock path.

**Operational reliability and safe automation**
- From: automation status is point-in-time, brief delivery has no independent proof, and no conservative runner acts on mechanically safe stale work.
- To: distinct-run history and streaks, compose-time input freshness, delivery status with a separate deadman, structured Git facts, and a default-dry-run safe runner.
- Reason: a missing or stale brief must fail visibly, and automation must never act from stale prose.
- Impact: additive local state, launchd templates, tests, and operator commands.

## Capabilities

### New Capabilities

- `field-aware-egress`: One fail-closed privacy boundary for model input, stored narrative, decision data, errors, and notification chunks.
- `automation-run-history`: Distinct job-run history, next-run estimates, failure streaks, and honest UI actions.
- `fleet-morning-brief`: Deterministic-first composition, input-freshness assertions, cursor semantics, trust markers, comprehension limits, and dashboard/CLI rendering.
- `session-outcome-cards`: Provider-allowlisted, two-lane, cached, budgeted, evidence-gated outcome extraction and export.
- `operator-decision-queue`: Transactional high-recall unanswered-decision state, deduplicated alerts, dismissals, and Home pinning.
- `structured-git-facts`: Recomputed per-repo facts and explicit push-eligibility reasons for consumers that need mechanical safety.
- `safe-loose-end-runner`: Default-dry-run, disableable, logged safe-tier actions with hard prohibitions and live-proof gating.

### Modified Capabilities

None. Mission Control has no prior OpenSpec living requirements; existing runtime behavior remains backward-compatible and these capabilities are additive.

## Impact

- Code: `scripts/chat-graph`, `scripts/automation-status`, `scripts/scan-unfinished-work`, `scripts/dashboard`, new brief/decision/runner scripts, dashboard renderers, and tests.
- State: additive SQLite tables/columns, `$MISSION_CONTROL_HOME/job-history.json`, brief cursor/delivery files, runner log, and launchd job state.
- Runtime: 5:00 AM brief and 5:20 AM deadman labels; existing Telegram/mobile-connect configuration is reused without copying secrets. This reflects the operator-ordered schedule change in commit `1eeb45d`.
- Operations: installed runtime, job registry, doctor/health evidence, rollback commands, and five-morning proof.
- Governance: ER-107, Mission Control `todo.md`, project memory, OpenSpec verify/retrospective, independent Codex audit loop, and source-card provenance.
