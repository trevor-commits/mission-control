---
intent: Deliver one trustworthy daily fleet-state brief through Mission Control, with bounded outcomes, high-recall decisions, delivery proof, and conservative dry-run automation.
success_criteria: Existing and new suites pass; privacy and migration invariants hold; installed local UI and one authorized delivery are proven; a real runner dry-run is independently reviewed; implementation audit converges; five-morning verification remains explicitly separate until elapsed evidence exists.
risk_level: high
auto_approve: true
branch: codex/morning-brief
worktree: false
dirty_worktree: allow
---

## Steps

- [x] **Step 1: Resolve source plan and live ground truth**
action: Resolve the Fable transcript, approved plan, upgrade audit, repo contracts, current branch state, and exact runtime/repo claims.
loop: false
max_iterations: 1
verify: test -s /Users/gillettes/.claude/plans/019f4550-2a9a-7fe3-9313-9e7a0be10b35-tha-cuddly-hopcroft.md
gate: auto

- [x] **Step 2: Capture clean Mission Control baseline**
action: Run every existing Mission Control gate before implementation and preserve the output as baseline evidence.
loop: false
max_iterations: 1
verify: bash scripts/chat-graph.test.sh && bash scripts/automation-status.test.sh && REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell && node scripts/dashboard-render-smoke.js . && bash scripts/usage-snapshot.test.sh && bash scripts/scan-unfinished-work --self-test
gate: auto

- [x] **Step 3: Create governed branch and OpenSpec contracts**
action: Create the isolated worktree/branch, branch ledger, strategic design, OpenSpec proposal/design/specs/tasks, and this HOTL binding.
loop: until strict OpenSpec validation passes
max_iterations: 3
verify: DO_NOT_TRACK=1 openspec validate morning-brief --strict
gate: auto

- [x] **Step 4: Lint the HOTL workflow**
action: Run the HOTL document linter and correct formatting, field, gate, or verification-contract errors.
loop: until the workflow lints clean
max_iterations: 3
verify: bash /Users/gillettes/.codex/plugins/cache/gillettes-local-plugins/hotl/2.11.0/scripts/document-lint.sh hotl-workflow-morning-brief.md
gate: auto

- [ ] **Step 5: Capture T7 LaunchAgent failure evidence in the owning repo**
action: Re-verify exit 126, removable-media resolution, affected labels, log failure, and stable local runtime candidate without changing services.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-t7-launchd-before.txt
gate: auto

- [ ] **Step 6: Repair systemic T7-backed LaunchAgent paths**
action: In an isolated third-party runtime branch, add a removable-media-path validator, point affected tracked plists at the stable local runtime, preserve intended loaded/unloaded states, rotate denial logs, and reinstall only intended labels.
loop: until the owning repo tests and proportional live status checks pass
max_iterations: 3
verify: test -s /tmp/morning-brief-t7-launchd-after.txt
gate: human

- [ ] **Step 7: Repair Morning Health and register stable evidence**
action: Add a bounded recent-log check, stable last-run marker, regression test, and Mission Control job registry row; prove the live job no longer exits 126 and its evidence becomes green.
loop: until focused health and automation tests pass
max_iterations: 3
verify: bash scripts/automation-status.test.sh
gate: auto

- [ ] **Step 8: Repair improvement-loop false corrections**
action: Write failing Claude tool-result and Codex wrapper fixtures, filter provider-generated pseudo-user input, group digest identity before cap, quarantine proven false queue/lesson items, regenerate advisory output, and preserve real correction detection.
loop: until focused improvement-loop verification passes
max_iterations: 3
verify: bash '/Users/gillettes/Coding Projects/global-implementations/scripts/verify.sh'
gate: auto

- [x] **Step 9: Land eight branchless source cards**
action: On the third-party repo canonical main, create seven missing cards and update the existing Claude-Code-Agent-Monitor card with Morning Brief patterns; stage only owned hunks and run source-card closeout with export.
loop: until source-card closeout succeeds
max_iterations: 3
verify: bash -lc 'cd "/Users/gillettes/Coding Projects/3rd Party Git Hub Repo'"'"'s" && scripts/source-card-closeout --with-export'
gate: auto

- [x] **Step 10: Write red privacy field-matrix tests**
action: Add synthetic tests covering narrative, actions, model prompts/tails, storage, errors, temporary files, argv, sidecars, and notification chunks; capture the expected pre-implementation failure.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-egress-red.txt
gate: auto

- [x] **Step 11: Implement the shared field-aware egress module**
action: Add the standard-library shared module and migrate current redaction callers while preserving narrative/action path semantics and non-content counters.
loop: until the privacy field matrix passes
max_iterations: 3
verify: bash scripts/mission-control-common.test.sh
gate: auto

- [x] **Step 12: Write red graph migration and provider-hygiene tests**
action: Add current-schema fixtures for node kinds, provider allowlist, repo-node preservation, kind-salted item keys, update/resolution evidence, row preservation, idempotence, and future-version refusal.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-graph-migration-red.txt
gate: auto

- [x] **Step 13: Implement additive graph migration and node hygiene**
action: Extend chat-graph schema/migrations, derive node kind, keep repo nodes out of lineage, suppress raw unknown labels, and preserve all current rows/suppressions.
loop: until graph migration tests pass
max_iterations: 3
verify: bash scripts/chat-graph.test.sh
gate: auto

- [x] **Step 14: Write red open-work change-stream tests**
action: Add tests for first/updated/resolved event timestamps, compound stable IDs, bounded new/resolved/aging export, text rewrites, same-text different-kind coexistence, and omission-not-resolution.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-open-work-red.txt
gate: auto

- [x] **Step 15: Implement bounded open-work changes**
action: Add update/resolution evidence persistence and export a bounded `loose_end_changes` stream without changing the unresolved `loose_ends` compatibility contract.
loop: until graph tests pass
max_iterations: 3
verify: bash scripts/chat-graph.test.sh
gate: auto

- [x] **Step 16: Write red distinct-run automation history tests**
action: Add repeated-poll, new-evidence, success-reset, stale/degraded, unknown, restart, concurrency, cap, keepalive episode, schedule, and glob-evidence fixtures.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-job-history-red.txt
gate: auto

- [x] **Step 17: Implement distinct-run history and schedule math**
action: Persist locked atomic unique run events, history confidence, failure streaks, glob evidence, and injectable next-run estimates for both supported schedule forms.
loop: until automation tests pass
max_iterations: 3
verify: bash scripts/automation-status.test.sh
gate: auto

- [x] **Step 18: Render automation history**
action: Extend fixtures, feed, renderer, and smoke assertions for next run, streak, distinct-run strip, confidence, and copyable kickstart command.
loop: until dashboard and render smoke pass
max_iterations: 3
verify: REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell && node scripts/dashboard-render-smoke.js .
gate: auto

- [x] **Step 19: Write red minimal Git-change and open-delta tests**
action: Add deterministic tests for the thin brief's minimal repo changes and open-work new/resolved/aging inputs without pulling in safe-runner eligibility yet.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-thin-inputs-red.txt
gate: auto

- [x] **Step 20: Implement thin-brief input contracts**
action: Extend scan/open-work exports only enough for honest deterministic repo changes and deltas; label missing/noisy data instead of inventing completeness.
loop: until scan and graph tests pass
max_iterations: 3
verify: bash scripts/scan-unfinished-work --self-test && bash scripts/chat-graph.test.sh
gate: auto

- [x] **Step 21: Write red composer and sidecar tests**
action: Add tests for section order, structured sidecar, per-input cadence/freshness, first-run window, equal-timestamp compound cursor, event arrival during compose, preview non-advancement, top-N, and one-screen NEEDS YOU.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-composer-red.txt
gate: auto

- [x] **Step 22: Implement deterministic composer**
action: Add `scripts/morning-brief` producing atomic Markdown and latest.json from deterministic inputs with source-quality/trust labels and snapshot high-water marks.
loop: until composer tests pass
max_iterations: 3
verify: bash scripts/morning-brief.test.sh
gate: auto

- [x] **Step 23: Add local CLI and dashboard brief feed**
action: Implement `dashboard brief --print`, brief feed collection, fixtures, and Home top section from latest.json without parsing Markdown.
loop: until dashboard and render smoke pass
max_iterations: 3
verify: REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell && node scripts/dashboard-render-smoke.js .
gate: auto

- [x] **Step 24: Capture local thin-brief browser proof**
action: Install into an isolated runtime, collect deterministic feeds, render Home/Brief, and capture a nonblank browser artifact before adding model outcomes.
loop: until the local UI proof is readable
max_iterations: 3
verify:
  type: browser
  url: file:///tmp/mission-control-morning-brief/index.html
  check: Home shows a NEEDS-YOU-first Morning Brief summary with source freshness and no raw markdown parsing.
gate: auto

- [x] **Step 25: Write red delivery receipt tests**
action: Add stub-send tests for fixed argv, chunk identity/hash, partial confirmation, retry-only-unconfirmed, completed no-op, failed-send cursor retention, and duplicate recognition.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-delivery-red.txt
gate: auto

- [x] **Step 26: Implement resumable delivery status**
action: Add `--send`, fixed-argv mobile-connect use, line-bounded chunks, per-chunk receipts, atomic delivery state, cursor commit on complete success, and safe retry.
loop: until delivery tests pass
max_iterations: 3
verify: bash scripts/morning-brief.test.sh
gate: auto

- [x] **Step 27: Write red deadman tests**
action: Add missing/stale/empty/unsent/partial/throttled/token-leak and independent-path fixtures under a scrubbed launchd-like environment.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-deadman-red.txt
gate: human

- [x] **Step 28: Implement independent deadman and plists**
action: Add the minimal direct failure notifier, fully expanded 7:00/7:20 launchd templates, explicit HOME/PATH, throttling, job registry, and installer wiring.
loop: until deadman, dashboard, and automation tests pass
max_iterations: 3
verify: bash scripts/morning-brief-deadman.test.sh && bash scripts/automation-status.test.sh && REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell
gate: auto

- [x] **Step 29: Review privacy and external side effects before live proof**
action: Run a threat pass over transcript egress, notification payloads, tokens, temp files, logs, permissions, retries, idempotency, and rollback; close every blocking finding.
loop: until no blocking privacy or delivery finding remains
max_iterations: 3
verify:
  type: human-review
  prompt: Review the actual diff and synthetic leakage evidence before first live cross-provider transcript egress or Telegram delivery.
  check: Review the actual diff and synthetic leakage evidence before first live cross-provider transcript egress or Telegram delivery.
gate: human

- [ ] **Step 30: Perform one authorized manual delivery and deadman proof**
action: Use the existing authorized channel to send one manually invoked short brief, record receipt, then safely exercise the suppressed/failed delivery path without exposing tokens or waiting for wall-clock 7:20.
loop: until receipt and failure-path evidence both exist
max_iterations: 2
verify: test -s /tmp/morning-brief-live-delivery-proof.txt && test -s /tmp/morning-brief-deadman-proof.txt
gate: human

- [ ] **Step 31: Write red Tier 1 outcome fixtures**
action: Add synthetic real-shape Claude/Codex/audit/handoff/unstructured/late/unknown-provider fixtures and exact structured command/SHA anchoring assertions.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-tier1-red.txt
gate: auto

- [ ] **Step 32: Implement bounded Tier 1 outcome cards**
action: Parse bounded assistant tails into stable cards, classify handoffs honestly, preserve deterministic anchors, emit late updates, and never resolve on omission.
loop: until graph outcome tests pass
max_iterations: 3
verify: bash scripts/chat-graph.test.sh
gate: auto

- [ ] **Step 33: Implement zero-call coverage planning**
action: Add seven-day provider/grammar/tail/eligibility/token projection with no model calls and modeled-cost labeling rather than claimed charges.
loop: until coverage plan fixtures and no-call assertion pass
max_iterations: 3
verify: bash scripts/outcome-coverage.test.sh
gate: human

- [ ] **Step 34: Write red Tier 2 isolation tests**
action: Add cache, budget-zero, provider kill-switch, OAuth exit-75 defer, raw-tool exclusion, invented-command discard, and slow-model-vs-ingest concurrency tests.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-tier2-red.txt
gate: human

- [ ] **Step 35: Review first live transcript egress**
action: Inspect the exact sanitized prompt, byte/message bounds, provider route, logging metadata, and temporary-file behavior before a bounded sample.
loop: until the privacy reviewer accepts the bounded sample packet
max_iterations: 2
verify:
  type: human-review
  prompt: Confirm the sample contains no raw tool output or prohibited data and that per-provider kill switches work.
  check: Confirm the sample contains no raw tool output or prohibited data and that per-provider kill switches work.
gate: human

- [ ] **Step 36: Run bounded provider sample and set caps**
action: Sample a small number per provider, measure input/output tokens and latency, record quota impact, set caps from observed p95, and do not run broad backfill yet.
loop: until calibration evidence and configured caps exist
max_iterations: 2
verify: test -s /tmp/morning-brief-outcome-calibration.json
gate: human

- [ ] **Step 37: Implement isolated Tier 2 extraction**
action: Add separate locked extraction, closed-DB model calls, short WAL writes, content-hash cache, caps, OAuth defer, provider kills, health counters, and narrative-only model output.
loop: until outcome, privacy, and concurrency suites pass
max_iterations: 3
verify: bash scripts/chat-graph.test.sh && bash scripts/mission-control-common.test.sh && bash scripts/outcome-extractor.test.sh
gate: human

- [ ] **Step 38: Write red decision-queue concurrency tests**
action: Add sync/alert/dismiss/restart/explicit-resolution/recurrence/duplicate-ingest tests with structured-vs-inferred trust behavior.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-decision-red.txt
gate: auto

- [ ] **Step 39: Implement transactional decision queue and alerts**
action: Add SQLite WAL decision events, stable identities/fingerprints, explicit resolution, recurrence, fixed-argv alert receipts, dismiss CLI, feed, and pinned Home rows.
loop: until decision and dashboard suites pass
max_iterations: 3
verify: bash scripts/decision-alert.test.sh && REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell && node scripts/dashboard-render-smoke.js .
gate: auto

- [ ] **Step 40: Enrich the working brief with outcomes and decisions**
action: Add Confirmed/Inferred outcome lines, lineage grouping only for valid chat nodes, flat unknown-provider cards, late updates, high-recall decisions, and deterministic anchors while preserving LLM-disabled fallback.
loop: until integrated brief, graph, decision, and dashboard tests pass
max_iterations: 3
verify: bash scripts/morning-brief.test.sh && bash scripts/chat-graph.test.sh && bash scripts/decision-alert.test.sh && node scripts/dashboard-render-smoke.js .
gate: auto

- [ ] **Step 41: Write red branch-level Git fact tests**
action: Add fixtures for local/upstream refs, named remote, ahead/behind, default/protected, worktrees, dirt, last commit/activity freshness, credential-bearing remote, and all refusal reasons.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-git-facts-red.txt
gate: auto

- [ ] **Step 42: Implement structured branch facts**
action: Extend the scanner with sanitized branch-level facts, conservative eligibility, safe remote classification, and explicit refspec argv without leaking URLs.
loop: until scan contract tests pass
max_iterations: 3
verify: bash scripts/scan-unfinished-work --self-test
gate: auto

- [ ] **Step 43: Write red safe-runner refusal tests**
action: Add DISABLE, default dry-run, checked-out, dirty, no upstream, behind/diverged, default/protected, recent/unknown activity, stale activity, credential remote, exact argv, log, and no-mutation tests.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-runner-red.txt
gate: auto

- [ ] **Step 44: Implement default-dry-run safe runner**
action: Recompute facts immediately, implement only eligible explicit push proposals/open-end reconciliation/satisfied-todo detection, enforce hard prohibitions, and write permission-restricted exact before/after JSONL.
loop: until runner tests pass
max_iterations: 3
verify: bash scripts/loose-end-runner.test.sh
gate: human

- [ ] **Step 45: Capture real live-ledger runner dry-run**
action: Run against the actual ledger in default dry-run, snapshot refs/worktrees before and after, and preserve every proposal/refusal for review.
loop: false
max_iterations: 1
verify: test -s /tmp/morning-brief-runner-live-dry-run.jsonl
gate: auto

- [ ] **Step 46: Independently review every runner proposal**
action: Have a separate Codex reviewer compare each dry-run action with live recomputed repo facts and confirm no state moved.
loop: until all unsafe proposals are fixed or explicitly removed
max_iterations: 3
verify:
  type: human-review
  prompt: Review the real dry-run, live facts, and before/after ref snapshots; automatic push remains disabled regardless of result.
  check: Review the real dry-run, live facts, and before/after ref snapshots; automatic push remains disabled regardless of result.
gate: human

- [ ] **Step 47: Prove automatic push remains disabled**
action: Verify no installed plist or default flag can enable live push and the runner requires a later explicit activation decision outside this closeout.
loop: false
max_iterations: 1
verify: bash scripts/loose-end-runner.test.sh
gate: auto

- [ ] **Step 48: Run full cold verification**
action: Run every existing/new suite, Python compile, bash syntax, JSON validation, privacy scan, diff check, OpenSpec strict validation, and relevant global/third-party validators.
loop: until all task-caused failures are fixed
max_iterations: 3
verify: bash scripts/chat-graph.test.sh && bash scripts/automation-status.test.sh && REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell && node scripts/dashboard-render-smoke.js . && bash scripts/usage-snapshot.test.sh && bash scripts/scan-unfinished-work --self-test && bash scripts/mission-control-common.test.sh && bash scripts/morning-brief.test.sh && bash scripts/morning-brief-deadman.test.sh && bash scripts/outcome-coverage.test.sh && bash scripts/outcome-extractor.test.sh && bash scripts/decision-alert.test.sh && bash scripts/loose-end-runner.test.sh && DO_NOT_TRACK=1 openspec validate morning-brief --strict && git diff --check
gate: auto

- [ ] **Step 49: Capture installed runtime and browser evidence**
action: Install the reviewed bundle, collect live feeds, run scrubbed-environment entrypoints, capture Home/Automation/Brief views, and document rollback.
loop: until installed and browser evidence are nonblank and current
max_iterations: 3
verify:
  type: browser
  url: file:///Users/gillettes/.mission-control/index.html
  check: Home and Automation show current Morning Brief, trust/freshness labels, and decision/job history surfaces without errors.
gate: human

- [ ] **Step 50: Run self-audit and threat/ripple checks**
action: Compare implementation against every OpenSpec requirement, inspect privacy/security, migrations, side effects, scope, docs, runtime/install drift, manual burden, and rollback; convert findings into tests or durable dispositions.
loop: until no blocking self-audit finding remains
max_iterations: 3
verify: test -s openspec/changes/morning-brief/verify.md
gate: auto

- [ ] **Step 51: Run independent Codex implementation audit**
action: Give a separate Codex session the actual diff, specs, cold outputs, installed proof, and live dry-run; require enumerated findings or review-clean with residual risk.
loop: until the reviewer returns a complete evidence-backed audit
max_iterations: 3
verify: test -s records/morning-brief-independent-codex-audit.md
gate: auto

- [ ] **Step 52: Implement audit findings and repeat**
action: Fix every accepted material finding with regression evidence and rerun independent review while severe novel issues remain plausible.
loop: until review-clean or every residual is explicitly owned and deferred
max_iterations: 5
verify: rg -n 'review-clean|Residual risk' records/morning-brief-independent-codex-audit.md
gate: auto

- [ ] **Step 53: Refresh durable records and implemented state**
action: Update Mission Control Work/Test/Audit records, IMPROVEMENTS statuses, PROJECT_MEMORY, OpenSpec verify/retrospective, ER-107 lifecycle as implemented-pending-proof, branch ledger, and notification consolidation work item.
loop: until project/global validators pass
max_iterations: 3
verify: DO_NOT_TRACK=1 openspec validate morning-brief --strict && bash '/Users/gillettes/Coding Projects/global-implementations/scripts/verify.sh'
gate: auto

- [ ] **Step 54: Commit and push every owning repo outcome**
action: Inspect owned diffs, stage only task files, make conventional per-outcome commits in Mission Control/global/third-party runtime and branchless-card paths, push, and record SHAs without disturbing unrelated dirt.
loop: until every task-edited file is committed and every push succeeds
max_iterations: 3
verify: git status -sb && git log -1 --oneline
gate: human

- [ ] **Step 55: Close implementation with honest pending proof**
action: Report implemented code/runtime/audits, exact commits/pushes, live evidence, rollback, and the elapsed five-morning proof still required; do not mark the overall goal or ER-107 verified yet.
loop: false
max_iterations: 1
verify: DO_NOT_TRACK=1 openspec status --change morning-brief
gate: auto

- [ ] **Step 56: Complete five-morning proof and final archive**
action: Over approximately five real mornings, record read/action/comprehension evidence, tune noise, decide subsume/keep/fold for each notification/report surface, rerun final independent audit, mark ER-107 verified, archive OpenSpec with Ripple/Completed-index updates, and close the overall goal.
loop: until five qualifying mornings and final review-clean evidence exist
max_iterations: 7
verify:
  type: human-review
  prompt: Confirm five real morning records meet the 60-second comprehension and action criteria, consolidation decisions are durable, and final audit is review-clean.
  check: Confirm five real morning records meet the 60-second comprehension and action criteria, consolidation decisions are durable, and final audit is review-clean.
gate: human
