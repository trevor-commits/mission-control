# Outcome extractor and newer-answer repair

Owner: Codex `01a15e1d-56ed-78d2-811d-19817731d768`.
Request: keep daily unfinished-work review; fix outcome extraction; check newer answers before asking Trevor again.
Scope: existing Mission Control extractor, loose-ends instructions, and the existing native heartbeat. No new scheduler, model switch, paid API, account change, chat resumption, or old-project execution.
Checkout: canonical clean main at b121c8b, no branch/worktree required. `lanes check` clear; foreign work absent at intake. Integration: origin/main. Linear: self-contained, repo-only.
Acceptance: precise 401/403 classification; one call then provider-wide persisted hold; zero calls on later held runs; explicit recovery; deterministic fallback retained; primary/escalation and corrupt-hold regression checks; daily confirmed and newer-answer checks active; normal source gates and remote containment; runtime path/parity readback. External subscription restoration and a future natural successful Tier 2 run are separate gates.
Evidence: synthetic installed Claude wrapper probe returned api_error_status403, subscription access disabled by organization, zero input/output tokens. Existing day counters show22failures/0successes. No private transcript egress in the probe. Earlier database-lock log is separate; no database repair is undertaken without a reproducing failure.
Changes: structured401/403classification; content-free provider-wide hold; primary/escalation stop; explicit recovery only after successful config write. Corrupt holds remain blocking. Historical failures remain intact. Daily heartbeat retains08:00Pacific and checks exact newer source/continuation answers before asking. Shared loose-ends guidance carries the same check.
Focused validation: extractor regression suite ALL PASS, including the new access-denial/hold/recovery cases. Full verifier:41functional suites PASS, including the added recovery-write-failure check; final source-artifact gate FAIL because a pre-existing September29 mission_control_common Python cache remained in scripts/__pycache__. Preserved that exact directory by rename outside the checkout, with unchanged SHA256 and no byte deletion. Required normal pre-push gate provides the final complete rerun.
Newer-answer live checks: native project inventory confirms gmail-briefing registration and active continuation01a15f66-36d1-7453-a527-857a2518a8cb. Source website user says unlocked. Three existing ledger items now retain agent work without repeating those settled questions. The storage reply Both are approved at11:00UTC predates later T10/Passwords proposals and is not reused as their approval.
Provider auth status: loggedIn true, authMethod oauth_token, firstParty, no API key source. This does not override the synthetic request403. Existing model defaults, calibrated caps and credentials remain unchanged.
Publication preflight: repo PUBLIC, default main, only workflow_dispatch trigger, ubuntu-latest standard runner. No hosted workflow dispatched or trigger changed.
Delivery evidence: exact remote containment, final normal gate and live no-call hold readback are recorded privately at /Users/gillettes/.codex/automation-state/unfinished-work-review/repair-delivery.json. Source publication does not imply account recovery. Existing installed dashboard routes extract-outcomes to the canonical source checkout; no aggregate installer or service restart is needed.
Rollback: disable Tier2 through the existing set-enabled0 control before reverting source that predates the access hold; restore prior exact extractor/skill bytes. Keep the daily direct-source review unless Trevor stops it. Prior heartbeat prompt and runtime files are preserved privately under the existing unfinished-work-review state directory.


## Hosted verification platform repair

The normal42-suite Mac gate passed and2028106 reached origin/main. GitHub accepted the direct push under its configured bypass while the expected Verify status was absent. The existing manual public workflow was dispatched as run39644561367 to obtain that proof, not treated as green from the push.

That run failed27/42 suites passing. Logs prove the workflow used Ubuntu for required macOS AppKit, Keychain, plutil and Chrome-path checks. Extractor assertions passed; its cleanup also relies on the Mac test-root contract. No test was removed or weakened.

The verification job now uses the standard macos-15 label, Homebrew ShellCheck, and an explicit native prerequisite check. The existing manual-only trigger, one job,20-minute bound, pinned actions and no-mutation permission remain. The focused workflow test accepts the Mac configuration and rejects Ubuntu/Linux package setup. No deployment/operational workflow changed.

GitHub's current runner reference lists macos-15 as standard and states standard runners are free in public repositories: https://docs.github.com/en/actions/reference/runners/github-hosted-runners . Repository visibility was verified PUBLIC. This is a bounded verification run, not recurring CI activation. Preserve the failed Ubuntu evidence; final Mac CI status belongs in the existing private delivery receipt.

## Authorized Codex replacement

Trevor requested the same extractor use Codex instead of Claude. Scope: replace only the classifier engine and its private access hold, preserving source flags, budgets, deterministic Tier 1, newer-answer review, existing schedules and foreground model/access settings. Current clean main checkout is reused; integration target origin/main. Exit condition: affected tests, full required gate, remote containment and one bounded uncached installed Codex result. Natural-run acceptance remains separate.

The bundled CLI succeeded with fictional JSON using gpt-6.1-sol/max and the existing local desktop route. Homebrew CLI probes rejected that selected model, so production pins the bundled executable. Historical Claude denial remains preserved. Cache version and provider identity isolate old results. No provider fallback or new scheduler is added. Rollback: revert this migration commit; the historical Claude hold will resume blocking calls rather than retrying its account failure.

Validation and live delivery receipt: private `unfinished-work-review/codex-delivery.json`; report and checkpoint retain natural-run acceptance.

Observed manual installed proof: days=1, limit=1; 25 candidate sources inspected, 11 eligible, one uncached call, one success, zero failures. Focused extractor suite passes, including credential stripping, loopback-only route, tool/incomplete response rejection and historical Claude-hold preservation. Full pre-push verification and remote containment are recorded in the private delivery receipt after completion.
