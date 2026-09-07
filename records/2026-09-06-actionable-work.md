# Actionable work and accurate resume information

By: Codex, task `01a07221-0541-7970-90e3-f59af1b6862e`. Date: 2026-09-06.
Request: start implementing the dependable-work roadmap after the September 5 assessment.
Scope: first useful dashboard and resume-helper change. Broader executor, Hermes, memory, research, and capture changes remain outside this packet.

## Baseline and ownership

Published source: `2a87d269981286552534a19f3954dde79e04580a`, fetched and verified from the remote main on September 6. It includes the newer full-ingest recovery repair, which this task preserves.

The original checkout was clean on another task's `codex/lean-agent-setup-01a06ff8` branch. This task uses the owner-bound `codex/actionable-work-01a07221` worktree. Creation and acknowledgment succeeded. No foreign branch was switched or edited.

Live feed at `2026-09-06T21:24:54Z`: 18,842 candidate rows, including 13,547 `register_unverified` and 4,893 `chat_open_end`. The other 402 rows include handoffs, todo entries, tracked requests, Git state, and nightly findings. Reproducing default severity/age sorting put 48 unverified-register rows among the first 50.

The CLI already filters those two weak kinds. The dashboard does not. Its open-work rows offer a map detour and a resolve-command copy. The prompt helper writes blank goal, runner, branch, acceptance, and verification fields and hardcodes Claude Opus/high.

These are candidate categories, not proof of accepted obligations. Filtering must be reversible. Search and exact source focus must reach retained candidates. Explicit todo and tracked-request kinds must remain visible.

## Intended change and checks

Use the existing filtering rule in Home and the default Open work view. Verify CLI/dashboard agreement on the same synthetic data. Keep an explicit candidate toggle, search, and exact-item focus. Put copied source/reopen commands on the work row with honest labels.

Replace the resume skeleton with a source-first recovery prompt that preserves the receiving task's selected model and reasoning. Report source freshness and the actual repo snapshot without treating its current branch as writing authority. Unknown acceptance details remain a required source inspection, never invented facts.

Focused CLI and rendered browser tests will verify default filtering, retained candidates, known work, reload behavior, exact copied commands, stale evidence, and the generated recovery prompt. Source tests, committed installation, and fresh-agent recovery are separate results.

## Verification

- The initial browser regression exposed the default mismatch: 50 displayed rows instead of the CLI's four recorded-work fixtures. Filtering now agrees with the CLI and preserves todo, tracked request, handoff, and unfamiliar kinds. Search reaches candidate 59 beyond the display cap; toggling survives reload; exact focus reveals the candidate; copying returns the exact source command.
- The new browser check also caught narrow-screen overflow. Two scoped CSS rules make work rows wrap; document width is now 390px at a 390px viewport. Desktop and mobile captures are under the private task state directory, `browser/actionable-work-{desktop,mobile}.png`.
- `bash scripts/loose-ends.test.sh` passes. It verifies model/effort preservation, explicit unknown facts, stale export and transcript-scan evidence, and provider-bound commands when source IDs collide.
- `node scripts/dashboard-render-smoke.js` passes for all nine tabs and its freshness, privacy, accessibility, and layout checks. Its obsolete temporary-hide expectation was replaced with acceptance and rejection checks for honest copy labels and candidate access.
- `bash scripts/dashboard.test.sh`: **92 pass, 0 fail**. It includes committed installation, file safety, code-only installation without launchd effects, and the existing collector recovery cases. The first run had the obsolete label expectation; the final run includes its correction.
- The first full browser run after the layout repair passed the new cases, then two pre-existing operator navigation checks exceeded their five-second timeout while the shell suite was running. The unchanged serial rerun passed all **348 assertions**. No timeout or assertion was weakened.
- Installed-data inspection then exposed a long repo option stretching the native filter to 794px. A long-name fixture also exposed an unbroken repo label at 1,066px. Bounding native filter width and allowing repo-label wrapping fixed both; the final full browser run again passed **348 assertions**.

The filter uses the existing detector kinds. There is no accepted/deadline override field in the current feed. The fixture verifies a recorded tracked request stays visible; it does not prove every inferred candidate has been classified correctly. All candidates remain searchable and recoverable.

## Status

The first dashboard/helper slice is committed and installed locally from `7efbe22e908b3702a38830fd78d97d5d6d412310`, following implementation commit `36c7ffe91302a882936d0ace2f516e1c7fed78ff`. The code-only installer returned success, skipped launchd installation, and wrote a verified `head` stamp. Source bytes for the dashboard and helper match that commit. Compared with the pre-install backup, only `index.html`, `bin/loose-ends`, the dashboard's baked feeder path, and the install stamp differ. The other runtimes and assets are byte-identical.

At `2026-09-06T22:22:18Z`, the actual installed page displayed 50 of 402 default candidates from the last-good feed at `21:24:54Z`, with all 18,440 other candidates disclosed and searchable. Page errors: zero. Mobile document width: 390px at a 390px viewport. Private evidence: `installed-browser.json`, `installed-desktop.png`, `installed-mobile.png`, and `install-after.json` under `/Users/gillettes/.codex/state/actionable-work-01a07221`.

The installed helper generated `prompt-proof/resume-current-pilot.md` for this exact owner task and repository. It preserves model/effort, reports the actual Git snapshot and task source, and requires original-request and duplicate-effect checks. This is generator/readback evidence, not fresh-worker execution.

Keep the local presentation/resume pilot: the measured default first 50 no longer contains the 48 unverified-register rows seen at baseline, and no candidate data was deleted. Reduced operator effort and successful fresh-worker recovery remain unmeasured. The original checkout is still clean on `codex/lean-agent-setup-01a06ff8`; no foreign branch was switched or edited. These commits have not been pushed or merged.

## Remaining acceptance and next action

Use this checkpoint for one fresh-worker recovery trial after source publication and an explicit ownership handoff. Verify that the worker identifies the installed artifact and remaining acceptance before acting, preserves the model/effort choice, and does not reinstall or resolve work merely because an old prompt said to do so. The generated prompt and this record are the handoff inputs; the source task remains `01a07221-0541-7970-90e3-f59af1b6862e`.

Healthy natural collector refresh is not proven. The live status still reports a red automation job, chats backoff/unknown full ingest, and decision-feed errors. The chats error at `22:01:47Z` predates this installation; the collector runtimes are unchanged. This slice must not be described as restoring overall Mission Control or system health.

At the initial delivery, the shared installed skill was an existing untracked file in the separate Codex checkout. Its helper route was correct; its old skeleton/freshness prose remained there. The initial slice preserved that copy. Trevor subsequently requested continued implementation after the roadmap named source/shared-skill publication as the next delivery step; the continuation below records that work. This record itself grants no authority.

## September 6 continuation

Trevor requested continued implementation after the strategy/delta refresh. The source worktree remained clean at `7f92aea047c47634e0599ecc538cace7511f1086`, with the existing owner lease. Remote main remained `2a87d269981286552534a19f3954dde79e04580a`; no existing PR matched this branch.

The current chats error was `feeder timed out after 150s`, attempted at `2026-09-06T23:43:17Z`, with three consecutive failures and a two-hour retry window. Diagnostic runs used private SQLite backups. The current data exported successfully there; one asynchronous Python 3.9 profiler crashed, while simpler read-only export timing completed. No live database repair, timeout increase, interpreter change, or speculative collector patch followed.

The unchanged installed collector then ran normally with `collect --force chats`: **52.916 seconds, exit 0**. Its new feed at `2026-09-07T00:03:37Z` reports `full_ingest_state=fresh`, `ingest_skipped=false`, and no stale providers. The error sidecar was removed. This is a manual recovery, not proof of the historical timeout's cause or a healthy scheduled cycle. Private timings and receipts are under `/Users/gillettes/.codex/state/actionable-work-01a07221/collector-diagnosis`.

The shared skill was backed up before changing only its prompt/freshness paragraphs. Its existing helper route and all provider symlinks were preserved. The backup is `/Users/gillettes/.codex/state/actionable-work-01a07221/shared-skill-before-20260906.md`, SHA-256 `90bb73bb2415cb1aa27740e63ad858b4554ab1dacd6fac55215ad4f65e6ab09b`. `README.md` now describes the recovery prompt, and the runbook points to actual feed-error receipts instead of a nonexistent collection log.

The existing runtime source checkout at `/Users/gillettes/.mission-control/source` is clean and detached at the published collector repair. Reuse it after publication instead of retaining this task worktree as the permanent feeder root. The cross-repository branch check also exposed an unquoted adjacent ledger heading that caused this task's entry to absorb another owner's fields; only that heading's formatting was corrected. Other historical branch-ledger issues remain outside this change.

Rollback: 15 prior installed code, asset, and stamp files were copied with their SHA-256 and modes to `/Users/gillettes/.codex/state/actionable-work-01a07221/runtime-before`. Restore only those exact files after checking for newer changes. Preserve all feeds, source records, and other work. Retain this worktree while the installed dashboard names it as its feeder root; merge/repoint before owner-authenticated cleanup.

Linear: `self-contained: actionable-work`.
