# 2026-08-21 — Full Mission Control Audit

## Scope and fingerprint

- Requested outcome: thoroughly audit Mission Control, make safe improvements, and remove repository clutter where evidence supports it.
- Scope: the local dashboard, collectors, installer, test gates, launchd templates, repository hygiene, and project records.
- Repository: `/Users/gillettes/Coding Projects/mission-control`.
- Branch: `claude/silence-is-a-state`.
- Starting state: commit `30ecbea` after merging `origin/main`. One tracked deletion was present: `.claude/launch.json`.
- Tooling observed: Python 3.14.6, Node 26.3.1, OpenSpec installed, macOS host.
- Prior audit record: `records/2026-08-15-main-only-repository-consolidation.md`. The repository changed materially after that audit through the silence-state, usage, panel, and monitoring work.

## Purpose alignment

Mission Control still fits its stated job: a local, offline dashboard that shows what needs attention across AI chats, repositories, usage limits, and background jobs.

The static file-based design remains the right fit. The app opens offline, keeps runtime state outside Git, and avoids a server or framework without losing the main operator workflows.

One product question remains outside this audit: Trevor still needs to decide when to activate the pending Morning Brief and Outcome Extractor work. Existing `todo.md` entries own that decision.

## Evidence gathered

- Baseline and final full matrix: `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh`.
- Focused usage collector test: `/bin/bash scripts/usage-snapshot.test.sh`.
- Final results: full verifier `SUITES PASS=30 FAIL=0`. Focused collector `PASS=32 FAIL=0`.
- AGENTS compliance: `/Users/gillettes/.codex/scripts/verify-project-agents-compliance.sh "/Users/gillettes/Coding Projects/mission-control"`.
- Static checks: `git diff --check`, added-line secret and unsafe-call scan, `xcrun swiftc -parse scripts/mc-panel.swift`, and shellcheck error-level scan of pure shell files.
- Audit-report prose check: `errors=0 warnings=0`.
- `todo.md` report-only output shows 1,883 legacy errors. Durable records are exempt, so this audit did not rewrite unrelated history.
- Source review: installer and stamp-manifest paths, collector timeout paths, dashboard render safety, launchd templates, test gates, Git state, vendored-source comparison, and read-only runtime feed inspection.
- UI checks: dashboard render/browser gates are part of the full matrix. A direct source scan found no `innerHTML` in `dashboard/index.html` or `dashboard/panel.html`. The generated legacy usage page received hostile cache and credit-label tests. It now normalizes labels and escapes render-time text.

## Findings and disposition

| Priority | Finding | Evidence | Disposition |
|---|---|---|---|
| P1 | A committed Claude debug launch file pointed to a deleted private temporary directory. | `.claude/launch.json` used `/private/tmp/.../scratchpad/serve`. It had no project role. | Fixed. Removed in commit `30ecbea`. The working tree is now free of it. |
| P1 | A future-dated GLM headroom cache could look live and allow a quota-sensitive route. | A controlled `generated_epoch = now + 600` fixture emitted `confidence:"live"`, `health:"ok"`, and a negative age. | Fixed. Future and malformed timestamps now become stale with an operator-readable note. A regression test prevents the false-green state. |
| P1 | A cached GLM health string could reach the optional usage HTML ledger as raw markup. | A controlled health value containing an `<img>` error handler appeared unescaped in `dashboard.html`. | Fixed. Cached health is normalized to an inert status token before it reaches JSON or HTML. A hostile-input test proves raw markup is absent. |
| P2 | The branch lacked two `main` commits. The merge conflicted in job registry and records. | `git log HEAD..origin/main` showed `c46d8b4` and `099654c`. Conflicts appeared in `dashboard/jobs.json` and `todo.md`. | Fixed. Merged `origin/main` and retained every registry and record entry. |
| P2 | The dashboard installer held two runtime lists. One was unused and omitted `chat-graph`. | `scripts/dashboard` listed an unused stale variable and a different hardcoded loop. Canonical set is `REQUIRED_INSTALL_RUNTIMES` in `scripts/mission_control_common.py`. | Fixed. The loop now consumes the scoped list. The separately installed dashboard runtime keeps its baked repository path. |
| P2 | Vendored usage collector lagged its upstream source. | Local `scripts/usage-snapshot` was Aug. 18. Upstream was Aug. 19 with timeout, reset-time, and Kimi-health hardening. | Fixed. Synchronized upstream changes, then kept three documented local hardening changes for cache timestamps, renderer-visible tokens, and render-time text. Updated tests cover both input paths. |
| P2 | The Python syntax gate did not compile `outcome_sources.py`. | `scripts/outcome-extractor` imports it, but `scripts/verify.sh` omitted it. | Fixed. The syntax gate now compiles it directly. |
| P3 | The active branch had no ledger entry. | `todo.md` Active Branch Ledger lacked `claude/silence-is-a-state`. | Fixed. Added its purpose, base, target, and cleanup condition. |

No P0 finding was found.

## Reliability and privacy results

- The installer still fails closed if its stamped runtime set differs from the canonical manifest.
- All audited subprocess launches are time-bounded.
- The synced collector distinguishes a normal timeout from an unconfirmed termination.
- The collector test now confirms that Kimi receives fixed arguments and that a termination problem becomes a visible down state.
- The collector test also confirms that a future GLM timestamp becomes stale and cannot look live.
- Cached GLM health now becomes an inert token before it reaches the optional HTML ledger. A hostile-input test proves raw tags are absent.
- Independent agent reviews found the timestamp and raw-markup defects. This audit reproduced each before fixing it.
- Synthetic test token strings were the only secret-pattern matches. No credential or runtime-state content was found in the change.
- The dashboard uses text-based rendering rather than `innerHTML` in both audited HTML surfaces.

## What was not tested

- A live `dashboard install` was not run because it changes the active local installation and LaunchAgent state. Hermetic installer and attestation tests passed instead.
- A natural scheduled collector run was not awaited. The collector’s behavior was tested with controlled inputs.
- No separate human reviewer has reviewed this change. Three isolated agent reviews were used. The first found the timestamp defect. The second found raw cache markup. The third passed the normalizer and recommended render-time escaping, which this audit then added and tested.

## Skeptical second pass

If starting today, the same static architecture would still be chosen. The strongest improvement was not a rewrite. It was removing drift between the installer, the canonical manifest, and the upstream collector.

A future rewrite becomes justified only if local files no longer support the data volume or if more than one operator needs concurrent access. Neither condition is present.

## Follow-up status

No new P0 or P1 follow-up remains. The existing operator decisions in `todo.md` remain the correct queue. No further audit-created work is required.

## Ownership

- by: ox-alpha through Hermes, x-alpha profile.
- triggered by: Trevor’s 2026-08-21 full audit request.
- linear: self-contained. The repository remains in repo-only mode.
