# CLAUDE.md

Read `AGENTS.md` first before planning, audit, or state moves.
`AGENTS.md` is the canonical repo entry surface for Claude and Codex in this repository.
After reading `AGENTS.md`, load `CONTINUITY.md`, `COHERENCE.md`, and `LINEAR.md` for bounded work, audits, handoff, and state moves.

## Repo Principles

Load `CONTINUITY.md` and `COHERENCE.md` before any task. Their principles, plus `LINEAR.md` `## Linear-at-the-core`, govern planning, audit, state moves, and Codex handoff in this repository.

Before planning, audit, or a state move, verify:
- Continuity Check: the required Work Record exists and Self-audit is honest about what was and was not verified.
- Ripple Check: dependent docs were checked and any drift was updated in the same commit.
- Linear-coverage: actionable work is issue-backed or explicitly dispositioned, and live issues keep a repo-side ledger home in `todo.md`.

## Roles
- Claude Cowork: orchestrator and state-move gatekeeper.
- Claude Code: primary line-by-line auditor and Self-audit spot-checker.
- Codex: primary implementor.
- Trevor: final operator and decision owner.

## What To Read
- `/Users/gillettes/Coding Projects/mission-control/AGENTS.md`
- `CONTINUITY.md`
- `COHERENCE.md`
- `LINEAR.md`
- `/Users/gillettes/Coding Projects/mission-control/AGENTS.project.md` when present and when the task needs the deeper repo-local execution overlay
- `/Users/gillettes/Coding Projects/mission-control/PROJECT_INTENT.md` when present
- `/Users/gillettes/Coding Projects/mission-control/todo.md`

## Codex Handoff
Use the repo's local prompt discipline when it exists. Durable record expectations must name:
- the Work Record entry
- the Completed index entry
- any issue creation or ledger refresh required
- the Ripple Check and Self-audit attestation expected

## Editing Rules
- Do not treat chat memory as durable project state.
- Keep repo docs authoritative and keep Linear as routing and coverage only.
- When a principle doc changes, update the companion docs that depend on it in the same commit.
