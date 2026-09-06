# COHERENCE

## Scope

Check the actual consumers affected by a change, including relevant tests and documentation. Repair contradictions in the same scoped change. This is not a requirement to read every companion document or produce a separate attestation for every task.

## Dependency Map

Use this map as a navigation aid. Update useful entries when their dependencies change. It is not append-only or a mandatory startup reading list.

| Changed surface | Dependent surface | Why the dependency exists |
|---|---|---|
| `PROJECT_INTENT.md` and local source-of-truth docs | `/Users/gillettes/Coding Projects/mission-control/AGENTS.md`, `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md` | task routing and authority statements depend on the docs map remaining accurate |
| optional repo-local companions such as `README.md`, `GUIDE.md`, `PROMPTS.md`, `RULES.md`, `STRUCTURE.md` | local principle docs | companion docs should point to the same principle surfaces rather than drifting separately |
| `scripts/mc-panel.swift` / `dashboard/panel.html` / `dashboard/index.html` lowest-quota glance | `~/.mission-control/data/headroom.json` `summary.lowest_quota` plus live signed-in quota rows | glance percent is the lowest ok+live+fresh remaining; signed-out Claude cannot blank Codex, Cursor, or GLM |
| `dashboard/index.html` / `dashboard/panel.html` per-window reset countdown | headroom `resets_epoch` plus honest fallbacks when the provider omits a clock | every visible window keeps a 12px countdown; empty rows wait in red; unused 5-hour GLM says the clock starts on next use; prepaid balances say there is no scheduled reset |
| `scripts/decision-alert` decision follow-through lifecycle | `scripts/compose-decision-prompt.py`, chat-graph `loose_end_changes`, `dashboard/index.html`, `dashboard/panel.html`, `docs/runbooks/mission-control.md`, `openspec/specs/rollup-answer/spec.md`, and `STATE.md` | single and rollup answers stay non-terminal; source-bound exact receipts, delivery-fresh graph proof, lifecycle counts, and every operator-facing label must preserve `answered_pending -> delivered -> consumed -> running -> live_result_verified -> closed`; a pre-source rollup upgrades only through exact immutable predecessor and artifact lineage |
| `skills/loose-ends/SKILL.md` / `scripts/loose-ends` | `/Users/gillettes/Coding Projects/mission-control/AGENTS.md` unfinished-work route, `README.md` tool table, `scripts/verify.sh` (`loose-ends.test.sh`), `scripts/mission_control_common.py` `REQUIRED_INSTALL_RUNTIMES`, `scripts/dashboard` install list, the four tool skill symlinks under `~/.agents/skills/loose-ends` | the loop is one skill and one helper. the route, the install set, and the symlinks must name the same files |
| `STATE.md` | `/Users/gillettes/Coding Projects/mission-control/AGENTS.md` Companion Docs, `git log` | STATE.md is a generated snapshot indexed from AGENTS.md. it drifts from git and must be regenerated or read with `git log` |

## Maintenance

Keep real dependency information useful and current. Historical map entries do not restore retired startup instructions, per-task paperwork, or fixed provider duties.

`AGENTS.md` remains the entry point. `CONTINUITY.md` provides optional handoff guidance. `LINEAR.md` records the repository-only tracking mode.
