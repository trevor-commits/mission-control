# Morning Brief orchestration convergence

Date: 2026-07-09
Status: implemented and review-clean for the zero-call/Tier 1 slice; external and elapsed proof remains open

## Audited Chat

- Audited chat name: Mission Control orchestration priorities
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Claude/Fable
- Full ID: `35d96de4-9509-4382-b1a0-10b9a4d1777e`
- Transcript: `/Users/gillettes/.claude/projects/-Users-gillettes-Coding-Projects-global-implementations/35d96de4-9509-4382-b1a0-10b9a4d1777e.jsonl`
- Linked Fable plan-author session: `6f306a0b-abbb-4d39-9d64-afa7fb977250`
- Plan: `/Users/gillettes/.claude/plans/019f4550-2a9a-7fe3-9313-9e7a0be10b35-tha-cuddly-hopcroft.md`

## Decision

Fable's broad diagnosis was directionally correct but its first priority was stale: the global improvement loop had already shipped. The highest-leverage current lane was the Mission Control Morning Brief because it composes the three underlying capabilities Trevor was weighing—session/transcript recall, clear operator-facing responses, and durable memory/open-work state—into one daily quality gate. Session lookup, response clarity, and memory remain maintenance rails rather than competing top-level projects.

## Implemented scope

- Repaired Phase 0 source reliability in the owning repositories: stable internal LaunchAgent runtime, bounded Morning Health evidence, and provider-wrapper filtering in the improvement loop.
- Added bounded zero-call Tier 1 outcome cards for Claude, Codex, Cursor, Copilot, and Hermes, including provider-native Hermes `state.db`, immutable observations, explicit resolution evidence, parser-version invalidation, safe command anchors, and coverage planning.
- Added a transactional decision queue with exact closed origin trust, graph-backed resolution, recurrence, retryable alert receipts, stale-reservation recovery, dashboard dismiss round trips, and one coherent decision per `NEEDS YOU` block.
- Added structured Git/worktree facts and a privacy-screened, DISABLE-aware runner that can only propose dry-run explicit pushes; live execution remains unavailable.
- Enriched the deterministic Morning Brief and static dashboard with outcomes, one pinned decision, provenance, late updates, job history, and source freshness.
- Added a code-only dashboard install route so installed/browser verification cannot silently install LaunchAgents or authorize Telegram delivery.

## Audit convergence

Independent Codex reviewers repeatedly challenged the actual diff and synthetic counterexamples. Accepted findings became regressions for:

- Hermes cursor races, database reset/reuse, and parser-version reprocessing.
- ACTION-only version identity, bounded sanitized output, canonical Claude parent selection, A-B-A ordering, stale markers, same-message markers, answering-turn evidence, and omission safety.
- Closed structured-origin trust, caller-asserted resolution rejection, alert retry/reservation behavior, dashboard lock/error refresh honesty, and installed-runtime decision wiring.
- Empty/malformed/wrong-path worktree output, per-remote default branches, credential/query refs, human-output privacy, short writes, DISABLE races, and no-mutation dry-run behavior.
- Browser-found response-clarity failures: split fenced procedures and inline `Answer: ...` content entering the decision. Parser v5 keeps one coherent action, extracts explicit shell fences only into ACTION anchors, and requires both selected message identity and sanitized content hash before parser supersession can resolve an old representation.

Focused final verdicts were review-clean for outcomes/coverage, decisions/dashboard/brief, and the Git runner.

The final holistic reviewer found one P2 durable-state contradiction: a generated HOTL run had been initialized but never used, so its tracked sidecar/report still represented every step as pending while the canonical workflow recorded manual progress. The finding was accepted. The HOTL runtime now marks that generated run blocked and superseded, without inventing per-step execution evidence; the workflow, OpenSpec tasks, `verify.md`, and `records/morning-brief-independent-codex-audit.md` are the implementation record.

The post-merge installed-browser pass found two more scoped issues: substring redaction could leave a complete Anthropic token suffix after removing only its prefix, and a stale next-run timestamp could override awaiting-activation state. Commit `2432d6e` fixed both with adversarial render fixtures that retain the dangerous suffix and contradictory year-2099 timestamp. The same independent Codex reviewer returned review-clean after both fixes.

## Live evidence

- Zero-call coverage found current provider-native sessions without invoking a model.
- Real runner dry-run covered 56 repositories. All 23 candidate branch records were correctly refused, every `argv` was null, automatic push remained disabled, normalized before/after Git facts were identical, and a separate reviewer inspected every record.
- Evidence artifacts:
  - `/tmp/morning-brief-runner-live-before.json`
  - `/tmp/morning-brief-runner-live-output.json`
  - `/tmp/morning-brief-runner-live-dry-run.jsonl`
  - `/tmp/morning-brief-runner-live-after.json`
- Code-only installed runtime backup: `/private/tmp/mission-control-before-morning-brief-20260709-214023`; the pre-canonical implemented runtime is preserved at `/private/tmp/mission-control-implemented-pre-canonical-20260710T053440Z`.
- The original backup was restored without a diff and canonical Mission Control `main` at `2432d6e` was reinstalled. LaunchAgent hashes were identical before and after; no new job or Telegram schedule was installed.
- Final installed browser artifacts are `tmp/playwright/morning-brief-final-{home,brief,automation}.png`. Home, Brief, and Automation rendered nonblank; one coherent pinned decision remains, token-family source prose is absent, and both gated jobs explicitly say `awaiting activation`.

## Deliberately not done

- No live Telegram brief or deadman message was sent.
- No Tier 2/model transcript sample or extraction was run; this still requires the explicit privacy/provider calibration gate.
- No automatic push path was enabled.
- Natural LaunchAgent cadence and approximately five real mornings of comprehension/action evidence have not elapsed.
- OpenSpec remains active and ER-107 remains implemented-pending-proof rather than verified/archived.

## Rollback

- Installed runtime: restore the private backup above to `~/.mission-control`, then recollect only after validating the restored state.
- Parser migration is additive and preserves old outcome versions/observations; use the prior executable against the same graph schema if code rollback is required.
- Branch code: revert the scoped Morning Brief commits; do not delete the live graph or decision archives as a rollback shortcut.
