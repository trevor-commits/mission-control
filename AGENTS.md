# Mission Control

<!-- agent-entry: shared-v1 -->

Use `/Users/gillettes/.codex/AGENTS.md` as Trevor's shared contract when that file is available (typically on Trevor's Mac). Cloud or Linux checkouts should treat this repo's `AGENTS.md`, `PROJECT_INTENT.md`, and `todo.md` as authoritative when the home-directory contract is not present. This repository owns Mission Control source and the existing loose-ends workflow; `/Users/gillettes/.mission-control` (or `$HOME/.mission-control` on the host) is installed runtime state, not a substitute source checkout.

- `PROJECT_INTENT.md`, `notes/DIRECTION-2026-07-04.md`, and `docs/MISSION_CONTROL_PLAN.md` explain project direction. Read the portion relevant to the current decision.
- `todo.md` under `## Active Next Steps` is the work queue. Its branch, issue, and testing ledgers also hold current state; read them when relevant. `STATE.md` is generated, so verify Git when it disagrees.
- For unfinished work, use `skills/loose-ends/SKILL.md` and its existing helpers. Do not create a second backlog, scheduler, or orchestration system.
- Use the applicable source tests and installation procedure (`CONTRIBUTING.md` for clone-to-verify). A source change, manual collector run, and successful natural collector cycle are different evidence.
- Preserve unrelated work and exact branch ownership. Before handoff or a state move, update the relevant continuity record with checks, rollback, and remaining obligations once.

No provider has a permanent implementor, reviewer, or gatekeeper role. Choose task ownership from the actual request and tool capability; Trevor owns consequential choices.
