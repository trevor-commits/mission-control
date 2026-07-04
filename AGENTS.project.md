# AGENTS.project.md (Mission Control)

## Scope
Deeper repository-local execution overlay for `/Users/gillettes/Coding Projects/mission-control`.
Read `/Users/gillettes/Coding Projects/mission-control/AGENTS.md` first. Use this file when the task is non-trivial, governance-sensitive, or needs the fuller runtime and delivery rules.

## Repo Principles
[MANDATORY_CONTINUITY] load and enforce local `CONTINUITY.md`; bounded tasks must leave a durable Work Record, honest Self-audit, and explicit `did not verify X because Y` note, and the audit path must permit Claude Code to spot-check at least one claim
[MANDATORY_COHERENCE] load and enforce local `COHERENCE.md`; governed changes require a Ripple Check, same-commit companion-doc updates, and an append-only Dependency Map
[MANDATORY_LINEAR_CORE] load and enforce the local Linear-Core contract; actionable work must have a live Linear issue or an explicit `no-action:` / `self-contained:` disposition, and every live issue must keep a repo-side `Linear Issue Ledger` entry with `todo home:`, `why this exists:`, and `origin source:`
[MANDATORY_CLAUDE_PRINCIPLES] repo-local `CLAUDE.md` must load the same three principles before planning, audit, or state moves, and Claude handoffs must name the durable-record expectations for Codex

- Load `CONTINUITY.md`, `COHERENCE.md`, and the local Linear contract before bounded work.
- Continuity gate: Work Record exists, Self-audit is honest, and unverified scope is named explicitly.
- Coherence gate: Ripple Check runs before commit or state move, and dependent docs drift together or not at all.
- Linear-Core gate: actionable work is issue-backed or explicitly dispositioned, and the repo-side ledger stays current.

## Repository Lineage
- Lineage status: `canonical`.
- Authoritative repo path: `/Users/gillettes/Coding Projects/mission-control`.
- If project scope/runtime changes materially, refresh this file, `PROJECT_INTENT.md`, and the root `todo.md` testing cadence in the same change.

## Stack and Runtime
[MANDATORY_STACK_RUNTIME] stack/runtime profile, risk areas, release gates, boundaries, rollback/ops checks

- Stack/runtime profile:
  - Local static dashboard plus shell/Python collector CLIs.
  - Primary release surface is the installed file:// dashboard, its JSON/JS feeds, and the local CLI commands Trevor runs from this repo or `~/.mission-control/bin/dashboard`.
- Primary risk areas:
  - stale feed timestamps hiding stale underlying sources
  - renderer regressions that leave a dashboard tab blank
  - launchd/install drift between repo copy and `~/.mission-control`
  - leaking transcript text, secrets, or host-local state into git
  - state-dir permission regressions for `~/.mission-control` and `~/.chat-graph`
- Release gates:
  - run `bash scripts/chat-graph.test.sh` when `scripts/chat-graph` changes
  - run `bash scripts/automation-status.test.sh` when job registry or automation-status logic changes
  - run `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell` when dashboard collection, install, or shell logic changes
  - run `node scripts/dashboard-render-smoke.js .` when `dashboard/index.html` or fixtures change
  - record a browser capture for release-sensitive visual or file:// loading changes
- Boundaries:
  - keep changes scoped to this project unless the user explicitly widens the scope
  - prefer no-new-dependency solutions unless the new dependency materially improves reliability or delivery
  - do not change deployment, infrastructure, or secret-handling behavior without explicit intent and verification evidence
  - do not commit `~/.mission-control`, `~/.chat-graph`, raw transcripts, feed output, or local logs
  - keep the default dashboard local/offline; only use `--serve` on `127.0.0.1` as an explicit fallback
- Rollback/ops checks:
  - uncommitted rollback: `git restore -- <path>`
  - committed rollback: `git revert <sha>`
  - document any project-specific smoke, health, or deploy rollback path when release behavior changes

## Operating Principles
[MANDATORY_OPERATING_PRINCIPLES] operating principles aligned to `OPERATING_PRINCIPLES.md`

- Apply `/Users/gillettes/.codex/policies/OPERATING_PRINCIPLES.md` hierarchy first.
- Prefer evidence-first changes and reversible edits.
- Keep solutions reliable, scoped, and easy to verify.
- For meaningful AI-assisted implementation, debugging, code review, unfamiliar API/citation work, or AI-only-operator handoffs, load `/Users/gillettes/.codex/policies/CODER_CRAFT_FORCING_FUNCTIONS.md` and scale the evidence to blast radius.

## Intent Alignment
[MANDATORY_PROJECT_INTENT] canonical project intent documentation + behavior aligned to `PROJECT_INTENT_ALIGNMENT.md`

- Canonical intent doc: `/Users/gillettes/Coding Projects/mission-control/PROJECT_INTENT.md`.
- Refresh this AGENTS runtime profile, release gates, risk areas, docs map, and testing cadence when scope/runtime changes materially.

## Docs Map
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

## Todo Governance
[MANDATORY_TODO_ADD] add follow-up work to project `todo.md`
[MANDATORY_TODO_SUGGESTIONS] maintain a persistent `Suggested Recommendation Log` in `todo.md`; record every materially new suggested action there, avoid duplicate entries by reusing matching items, keep history instead of deleting entries, and check items off when completed
[MANDATORY_TODO_CHECKOFF] auto-check completed verified `todo.md` items
[MANDATORY_PLAN_TRACKING] capture durable chat-created plans in `todo.md` by recording the overall goal plus concrete steps, then mark them complete in the same file/log when verified
[MANDATORY_FEEDBACK_DECISIONS] maintain a durable `Feedback Decision Log` in root `todo.md`; record outside feedback, the reasoning response, final decision, and any linked implementation/audit/test evidence there; update existing entries instead of duplicating the same feedback thread
[MANDATORY_TESTING_GOVERNANCE] testing is required delivery evidence; keep `Test Evidence Convention`, `Test Evidence Log`, and `Testing Cadence Matrix` in root `todo.md`, and document what ran or what remains untested
[MANDATORY_BRANCH_LIFECYCLE] maintain `Active Branch Ledger` and `Branch History` in root `todo.md`; every non-trivial branch must record purpose, responsible/source chat, last refreshed by chat, linked issue, plugin mirror status, merge expectation, exit checklist, delete-vs-retain outcome, retain reason when applicable, and delete/cleanup trigger

- Track actionable work in `/Users/gillettes/Coding Projects/mission-control/todo.md` with priority, owner, and target date.
- Keep `todo.md` `Work Record Log` current for bounded tasks and audits that would otherwise lose reasoning between chats.
- When this repo has a live Linear surface, mirror every live issue in `todo.md` `Linear Issue Ledger` with current status, `todo home:`, `why this exists:`, and `origin source:`.
- When an audit creates actionable execution work, put those items at the top of `Active Next Steps` in dependency order; keep deferred, optional, or not-yet-execution-ready audit recommendations in `Suggested Recommendation Log`.
- When the current chat creates or discovers more urgent execution-ready work than the existing queue reflects, persist and move those items to the top of `Active Next Steps` before handoff so the chat is not the only durable record.
- Keep audit records durable: show source/work chat, audit chat, implementation/disposition chat, tested scope, not-tested scope, findings, disposition, and verification evidence.
- Keep outside feedback decisions durable in `Feedback Decision Log` so the same reasoning trail can be reused later.

## Worktree and Concurrency
[MANDATORY_WORKTREE] proportional worktree rule for concurrent chats in same repo; separate worktrees only for same-file overlap, disruptive branch switching, or risky/long-running work

- Default to the current checkout when branch purpose matches the task and rollback is straightforward.
- Use a task branch or worktree only when it materially improves review, rollback, handoff, or safety.
- Use separate worktrees for concurrent chats only when they would edit the same files, disrupt branch switching, or run risky/long-running work.
- When this repo has a live tracking plugin, create or reuse the issue before branching, prefer the plugin-generated branch name when available, and keep the repo ledger plus plugin mirror current through review, merge, and cleanup.
- Keep one branch per intended outcome with an explicit merge target, review path, and delete-or-retain decision.

## Pragmatic Delivery
[MANDATORY_PRAGMATIC] pragmatic improvement mindset

- Favor small, reversible reliability improvements over broad rewrites.

## Audit and Planning
[MANDATORY_FULL_AUDIT] full-audit behavior aligned to `FULL_AUDIT.md`
[MANDATORY_NEXT_STEPS] next-steps behavior aligned to `NEXT_STEPS_ORCHESTRATION.md`, including `todo.md`-grounded and independently inferred recommendations; when the user explicitly asks for reasoning/model guidance or autonomous planning, include recommended reasoning levels without defaulting the first chat to `extra high`; when an audit or the current chat creates or discovers more urgent execution-ready work, persist and move those items to the top of `Active Next Steps` and reserve `Suggested Recommendation Log` for deferred, optional, or not-yet-execution-ready items; if none remain, explicitly state `No further steps required.`

- Full audits follow `/Users/gillettes/.codex/policies/FULL_AUDIT.md`.
- Non-trivial implementation should receive a separate follow-up audit chat unless explicitly waived; if waived or blocked, record that in the audit trail.

## Clarification and Safety
[MANDATORY_CLARIFY] ask focused clarifying question(s), explain the conflict/misalignment, and pause risky changes until clarified

- Ask clarifying questions only when scope, conflict, or risk prevents safe execution.

## Credit and Verification Posture
[MANDATORY_CREDIT_IMPACT] prioritize correctness/reliability and flag significant low-upside credit waste with efficient reliable alternatives
[MANDATORY_NO_COMMIT_BLOCK] verification commands provide evidence and do not block commits/pushes unless the user explicitly requests strict gates

- Verification evidence is mandatory in handoff notes for repository changes.

## Execution Defaults
[MANDATORY_NO_APPROVAL_PROMPTS] execute requested actions end-to-end without repeated approval prompts; ask only when blocked by platform constraints or missing requirements
[MANDATORY_IGNORE_UNRELATED_CHANGES] treat unrelated tracked edits as valid concurrent work; do not block execution/cleanup, and never revert them unless explicitly requested
[MANDATORY_COMMIT_OWN_CHANGES] commit every file edited in the current task before completion unless the user explicitly says not to; never let unrelated dirty state prevent committing task files
[MANDATORY_AUTO_PUSH] after edits in a git repository, automatically commit and push every task-touched file that remains changed unless the user explicitly says not to push; if push fails, stop and report the exact failing command/output
[MANDATORY_TASK_CLASSIFICATION] classify task tier per `TASK_CLASSIFICATION.md`; match verification depth and playbook loading to tier
[MANDATORY_TRUST_GATE] evaluate Trust Gate triggers at session intake per `session-intake-closeout` skill; when `on`, require decision labels, challenge findings, and uncertainty handling at closeout
[MANDATORY_ANTI_THRASH] after 2 grounded attempts, narrow scope, request missing artifact, or escalate; do not retry unchanged approach

- Execute directly for implementation requests.
- Keep unrelated tracked changes intact.
