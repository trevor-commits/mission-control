# Background safety: Mission Control

Owner: Codex 01a1a5ca. Self-contained/repo-only. Authorized by Trevor's cross-system background audit and repair request.

Installed source matches repository baseline. Isolated reproduction proves a failed envelope dated epoch1 still plans launchctl kickstart -k. Job verification returns true without health evidence. No real signal was sent.

Repair: red jobs are report-only. Stored status cannot authorize a restart. Job recovery cannot pass without independent verification. Reports record blocked interventions; feed attempts receive a pre-action receipt before existing outcome reporting.

Containment: supported ~/.mission-control/self-repair/DISABLE created by this audit, SHA256 2a67a76ab3619b6ebc9f04ad396a98cfd5e7668eb94a9a1add59ec45ff4bc46e. Verified command stops before scan. Remove only this exact audit sentinel after reviewed clean installation and acceptance; preserve a changed sentinel.

Evidence: Global .git/local-verification/background-safety-01a1a5ca/ holds inventory, installed source hashes, isolated reproduction and containment receipts. Global and Mac Health foreign edits preserved. Whole background-system audit remains open; this record covers only Mission Control.

Pending: regressions, source checks/review, publication, exact runtime installation with preimage, installed isolated checks, natural-run acceptance and global map/ledger delivery. No claim of installed repair yet.


Review follow-up: CodeRabbit correctly identified lost CLI findings on report-write failure and stale observations counted as current heartbeat failures. Source now preserves JSON/text findings and heartbeat errors, stops before unlogged work, carries the original health timestamp/shared freshness verdict, and counts unverified reports separately. The automation summary carries those new counters. Four added self-tests exercise both output formats and stale-source counts; no live executor is used. Prior 42-suite pass belongs to the earlier commit; the revised candidate requires its new gate/review before installation.

Browser gate follow-up: the revised full run passed 41 suites and failed the dashboard canvas check after its fixed 300 ms sleep. Rendering is asynchronous. The check now waits up to Playwright's existing bounded default for the same required canvas; the canvas assertion remains. This repairs readiness synchronization rather than relaxing the result. The previous failure and host-load snapshot remain private evidence. The new candidate requires focused checks and a full check.

Panel review follow-up: report-write errors now survive automation receipt normalization, and the self-check displays an amber report-log warning whenever the error list is non-empty. The panel regression checks errors with failures=0 and an empty error list with failures=3, preserving the distinction from other outcomes. State-home normalization and all 22 panel browser groups pass. Combined collector source remains preserved; new full-source checks and exact review remain required before installation. Runtime acceptance stays with the existing Global audit and collector coordinator.
