# AGENTS.md (Mission Control)

## Purpose
This is the canonical AI-first entry surface for `/Users/gillettes/Coding Projects/mission-control`.
Read this file before any action. It explains the repo's logic, tells the agent what is authoritative, and routes to the smallest set of companion docs needed for the task.

## Start Here
- Read this file before any action.
- Apply `/Users/gillettes/.codex/AGENTS.md` as the global baseline, then use this file as the repo-specific contract.
- After this file, load only the downstream docs required for the task:
  - `/Users/gillettes/Coding Projects/mission-control/PROJECT_INTENT.md`.
  - `/Users/gillettes/Coding Projects/mission-control/AGENTS.project.md` when the task needs the deeper repo-local execution overlay.
  - `/Users/gillettes/Coding Projects/mission-control/CONTINUITY.md`, `/Users/gillettes/Coding Projects/mission-control/COHERENCE.md`, and `/Users/gillettes/Coding Projects/mission-control/LINEAR.md` for bounded work, audits, handoff, or state moves.
  - `/Users/gillettes/Coding Projects/mission-control/todo.md` for operational state, branch history, audit records, and test evidence.
  - `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md` when the actor is Claude or the task involves Claude/Codex handoff.

## Core Logic
- `AGENTS.md` is the mandatory first-read repo contract.
- This root file stays thin and non-duplicative; detailed mandatory markers live
  in `AGENTS.project.md`.
- `AGENTS.project.md` is a deeper execution overlay, not the first-read contract.
- `todo.md` is operational state, not chat memory.
- `CONTINUITY.md`, `COHERENCE.md`, and `LINEAR.md` govern durable records, ripple checks, and actionable follow-up routing.

## Task Routing
- Implementation or bugfix: read `/Users/gillettes/Coding Projects/mission-control/PROJECT_INTENT.md`, `/Users/gillettes/Coding Projects/mission-control/AGENTS.project.md`, and the relevant source files; load the principle docs before commit or state changes.
- Audit or review: read `/Users/gillettes/Coding Projects/mission-control/PROJECT_INTENT.md`, `/Users/gillettes/Coding Projects/mission-control/AGENTS.project.md`, `/Users/gillettes/Coding Projects/mission-control/todo.md`, and the principle docs before drawing conclusions.
- Planning or next-steps work: read `/Users/gillettes/Coding Projects/mission-control/PROJECT_INTENT.md`, `/Users/gillettes/Coding Projects/mission-control/AGENTS.project.md`, and `/Users/gillettes/Coding Projects/mission-control/todo.md`.
- Governance or repo-structure work: read this file, `/Users/gillettes/Coding Projects/mission-control/AGENTS.project.md`, and any touched global scripts/policies before editing.
- Claude/Codex handoff: read `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md` and name the expected durable records explicitly.

## Situation Routing
- Ambiguity or conflicting instructions: ask the smallest focused question only after targeted repo inspection.
- Repo-wide or authoritative-process changes: update the touched contract plus every dependent companion doc in the same change.
- Changes under `/Users/gillettes/.codex`: run `/Users/gillettes/.codex/scripts/validate-global-policy-stack.sh` after editing.
- High-risk or state-moving work: apply Continuity, Coherence, and Linear-Core gates before closeout.
- Missing context that could materially change the answer: treat context ingestion as prerequisite work.

## Companion Docs
- `/Users/gillettes/Coding Projects/mission-control/CONTINUITY.md`.
- `/Users/gillettes/Coding Projects/mission-control/COHERENCE.md`.
- `/Users/gillettes/Coding Projects/mission-control/LINEAR.md`.
- `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md`.
- `/Users/gillettes/Coding Projects/mission-control/README.md` when present.
- `/Users/gillettes/Coding Projects/mission-control/PROJECT_INTENT.md`.
- `/Users/gillettes/Coding Projects/mission-control/todo.md`.
- `/Users/gillettes/Coding Projects/mission-control/docs/MISSION_CONTROL_PLAN.md`.
- `/Users/gillettes/Coding Projects/mission-control/notes/DIRECTION-2026-07-04.md`.
- `/Users/gillettes/Coding Projects/mission-control/records/`.
- Add stack-specific runbooks, API specs, deployment docs, and troubleshooting docs here as they become canonical.

## Non-Negotiables
- Do not treat `AGENTS.project.md` or `CLAUDE.md` as alternate first-read specs.
- Do not duplicate the full repo contract inside `CLAUDE.md`.
- Route outward to companion docs instead of bloating this file.
- When the entry contract changes, update the dependent docs, validators, and verification checks in the same change.
