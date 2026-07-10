# Independent Codex audit: Morning Brief implementation

Date: 2026-07-09
Audit scope: commits `2f3d38a`, `0523925`, `2da8c9b`; OpenSpec/HOTL contracts; cold verification; installed/browser proof; and the live 56-repository runner dry-run
Reviewer: separate Codex agent `/root/decision_audit`
Final state: implementation review-clean after the durable-state finding and two final installed-UI/privacy findings were corrected; external and elapsed gates remain open

## Audited Chat

- Audited chat name: Mission Control orchestration priorities
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Claude/Fable
- Full ID: `35d96de4-9509-4382-b1a0-10b9a4d1777e`
- Transcript: `/Users/gillettes/.claude/projects/-Users-gillettes-Coding-Projects-global-implementations/35d96de4-9509-4382-b1a0-10b9a4d1777e.jsonl`

## Finding and disposition

### P2 — generated HOTL run state contradicted the canonical workflow

The tracked `.hotl` sidecar/report said the run was active at step 1 with every step pending, while `hotl-workflow-morning-brief.md` recorded the manual implementation progress. A future resumer could have trusted the stale sidecar and concluded that no work had begun.

Disposition: accepted and fixed. The generated run had only been initialized; its runtime transitions were never used while execution proceeded through the canonical workflow/OpenSpec records. The HOTL runtime's supported `step 1 block` transition now marks that generated run as superseded and explicitly points readers to the workflow checkboxes, OpenSpec tasks, `verify.md`, and this audit. No pending sidecar row is represented as execution evidence.

### P1 — short-prefix redaction left a full token suffix visible

The first display regex matched the documented Anthropic prefix before the generic full-token alternative, so substring replacement could leave a complete synthetic credential body visible. The fix consumes the whole optional suffix. The render smoke now injects both prefix-only documentation and a complete token with a unique suffix and proves neither survives.

### P2 — awaiting activation could lose precedence to stale schedule data

The first clarity patch checked `next_run_epoch` before activation state, allowing an uninstalled job with stale precomputed data to claim a concrete next run. The fix checks activation first. The smoke retains a contradictory year-2099 timestamp and proves only `Next run: available after activation` renders.

Both fixes landed in `2432d6e`; the independent scoped recheck returned review-clean.

## Code verdict

Review-clean for the implemented deterministic/Tier 1 slice:

- Outcome cards: bounded provider-native collection, immutable versions/observations, exact resolution evidence, parser-version invalidation, and safe content/command separation.
- Decision queue: WAL transactions, closed provenance trust, exact graph-backed resolution, recurrence, retryable alerts, and dashboard round trips.
- Loose-end runner: fail-closed Git facts, DISABLE behavior, no live execution path, private audit logs, and default dry-run only.
- Installed UI: one coherent pinned decision, explicit trust/freshness labels, and awaiting-activation jobs rather than false failures.

## Evidence re-run by the reviewer

- Graph, automation, dashboard, usage, scanner, shared-egress, brief, delivery, deadman, coverage, decision, and runner suites passed.
- Dashboard shell suite: `PASS=29 FAIL=0`.
- Runner suite: `PASS=32 FAIL=0`.
- Strict OpenSpec validation and HOTL document lint passed.
- All 23 real fleet candidates were correctly refused; every action argv was null and automatic push stayed disabled.
- Code-only rollback/reinstall preserved the complete LaunchAgent hash manifest; the final live inventory contained 55 unchanged entries and recorded both the original and implemented-runtime backups.
- Home, Brief, and Automation browser captures were nonblank and consistent with the activation gates.

## Residual gates, not defects

- No authorized Telegram delivery/deadman receipt yet.
- No Tier 2 provider sample or extractor; privacy/provider calibration comes first.
- No launchd activation or automatic push.
- No five-morning comprehension/noise evidence or notification-consolidation decision.
- The first screens still contain long/historical items; tune ranking from natural-morning evidence without weakening trust invariants.

These gates permit merging the scoped zero-call/Tier 1 implementation but prevent claiming the overall Morning Brief/OpenSpec program verified or archived.
