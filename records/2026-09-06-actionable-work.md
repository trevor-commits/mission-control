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
- The first full browser run after the layout repair passed the new cases, then two pre-existing operator navigation checks exceeded their five-second timeout while the shell suite was running. A serial browser rerun is pending. No timeout or assertion was weakened.

The filter uses the existing detector kinds. There is no accepted/deadline override field in the current feed. The fixture verifies a recorded tracked request stays visible; it does not prove every inferred candidate has been classified correctly. All candidates remain searchable and recoverable.

## Status

Source implementation and focused checks are complete; full browser rerun and committed local installation are pending. Publication is not authorized by this record. The original source checkout remains untouched.

The shared installed skill is an existing untracked file in the separate Codex checkout. Its helper route is correct; its old skeleton/freshness prose remains there. This task changes the owning Mission Control skill source and preserves the newer installed-helper routing paragraph, without overwriting the foreign untracked copy. Shared skill publication and fresh-agent recovery remain explicit follow-up work.

Rollback: 15 prior installed code, asset, and stamp files were copied with their SHA-256 and modes to `/Users/gillettes/.codex/state/actionable-work-01a07221/runtime-before`. Restore only those exact files after checking for newer changes. Preserve all feeds, source records, and other work. Retain this worktree while the installed dashboard names it as its feeder root; merge/repoint before owner-authenticated cleanup.

Linear: `self-contained: actionable-work`.
