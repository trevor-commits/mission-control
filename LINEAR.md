# LINEAR

## Purpose
This file is the repo-local Linear/Core routing contract for `mission-control`. The full Trevor-standard workflow lives in `/Users/gillettes/Coding Projects/Linear/LINEAR.md`; repo docs remain authoritative for truth.

## Local Mode
- Current mode: `repo-only`.
- Reason: no Mission Control Linear team/prefix has been verified yet.
- Trevor has been asked whether to set up Linear for this project.
- Until a live team and prefix are verified, do not invent issue IDs or automation settings.

## Linear-at-the-core
Linear holds scheduling and coverage; repo docs hold truth. Any audit finding, feedback decision, suggestion, or surfaced follow-up that implies future work gets a live Linear issue in the same commit, or an explicit `no-action:` / `self-contained:` disposition in the durable record. Nothing actionable sits un-Linearized.

## Coverage Invariant
- Every live issue has a matching `todo.md` `Linear Issue Ledger` entry with `status:`, `todo home:`, `why this exists:`, and `origin source:`.
- Every `Active Next Steps` item has a matching issue ID annotated inline when the repo has a live Linear surface.
- Every durable log entry that implies future work resolves `linear:` in the same record.
- If this repo is intentionally `repo-only`, record that mode explicitly instead of silently drifting away from the principle.

## State-move Gate
Before state moves or bounded-task closeout, verify Continuity Check, Ripple Check, and Linear-coverage.

## Where The Rules Live
- `CONTINUITY.md`
- `COHERENCE.md`
- `/Users/gillettes/Coding Projects/mission-control/AGENTS.md`
- `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md`
- `/Users/gillettes/Coding Projects/mission-control/todo.md`
- `/Users/gillettes/Coding Projects/Linear/LINEAR.md`
