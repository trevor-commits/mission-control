# PROJECT_INTENT

## Purpose
Mission Control is Trevor's local, offline operating dashboard for AI coding work.
It shows chat relationships, unfinished handoffs, repository health, usage/credit
signals, and background-job status in one double-clickable page.

This is a serious personal daily coding tool, not an exploration project and not
a public SaaS. The product owner is Trevor. The tool should make his current AI
coding system easier to understand and operate without requiring him to read code
or remember terminal commands.

## Problem Statement
Trevor works across Codex, Claude, Hermes, Cursor, GitHub, local scripts, and
background jobs. The problem is not lack of data; it is scattered status. Work
can be pushed, stale, uncommitted, unreviewed, over quota, or blocked in another
chat without being visible from one place.

## Target Users and Top Jobs
- Primary users: Trevor as solo operator and AI-workflow owner.
- Top jobs:
  - See which chats and repos need attention now.
  - Reopen or inspect the exact chat behind a work item.
  - Confirm local background jobs and data feeds are fresh enough to trust.
  - Decide which model/platform has enough usage headroom for the next task.

## In-Scope Outcomes
- Static offline dashboard installed under `~/.mission-control`.
- `scripts/chat-graph` SQLite relationship store under `~/.chat-graph`.
- `scripts/dashboard` collector/install/open/status CLI.
- `scripts/automation-status` job registry health feed.
- Vendored `scripts/usage-snapshot` and `scripts/scan-unfinished-work` feeds.
- Synthetic fixtures and smoke tests that keep the file-based dashboard working.

## Product Phases
### V1 - make the dashboard understandable
- Home tells Trevor what needs attention and the whole row opens the right place.
- Map explains chat relationships visually: dots are chats, lines are how they
  started, audited, referenced, or continued each other.
- Chats lists individual chats with plain labels: AI, repo, active in last
  30 minutes, unfinished work, Reopen this chat, and Read it.
- Git, Usage, and Automation use operator language before implementation labels.

### V2 - make the dashboard practical
- Usage feeds route future AI work toward the platform/model with usable headroom.
- Autonomous hygiene handles the safe class of cleanup and makes decision-needed
  work glaring on the dashboard and phone.
- More graph layout polish is allowed only after V1 labels and trust signals are
  clear enough for a non-coder to use.

## Non-Goals
- Public web service, hosted dashboard, or multi-user app.
- Committing runtime state, transcript bodies, API keys, or local feed output.
- Replacing GitHub, Linear, Housecall Pro, or provider-native usage sources.
- Rebuilding the dashboard as a framework app while the file:// model works.
- Adding more features before Home, Map, and Chats are plain enough for Trevor to
  understand at a glance.

## Success Metrics and Guardrails
- Leading metrics: status feeds refresh on cadence, graph ingest freshness is
  visible, tests catch renderer/feed drift, and the Desktop app opens the page.
- Lagging metrics: fewer stranded chats, fewer forgotten pushes, faster model
  routing decisions, and fewer silent background-job failures.
- Guardrails: state directories stay `0700`; committed fixtures stay synthetic;
  all transcript-derived display text remains redacted; file:///offline use
  remains the default.

## Primary Journeys and Navigation Model
1. Open the Desktop "Mission Control" app, scan Home for exceptions, then click
   a row to the exact tab or chat map focus.
2. Use Map/Chats to understand chat lineage, copy the reopen/read command, and
   close the loop in the right AI surface.
3. Use Git, Usage, and Automation tabs to decide whether the next action is a
   commit/push, model-route change, or local job repair.

## Content and Wording Principles
- Prefer plain operator wording over implementation labels.
- Avoid claiming a feed is fresh when its underlying source is stale.
- Commands may be copyable, but the primary visible action label should be
  human-readable.

## Technical Strategy and Stack Rationale
- Current project type: `static-site`
- Why this stack now: a single static HTML file plus local JSON/JS feeds opens
  instantly, works offline, needs no server, and has fewer moving parts than a
  framework app. Shell/Python CLIs handle collection; Node is used only for the
  committed render smoke test.

## Constraints, Assumptions, Risks, and Invalidation Triggers
- Constraints: no secrets in git; no network exposure by default; no new
  dependency unless it clearly reduces local-operability risk.
- Assumptions: Trevor is the only user; local macOS paths and launchd are valid;
  `~/.mission-control` and `~/.chat-graph` are host-local state.
- Risks: stale feed timestamps, file:// browser behavior changes, provider usage
  data gaps, transcript parser drift, and confusing UI labels.
- Invalidation triggers: browser blocks local script feeds, state grows beyond
  simple static rendering, or more than one operator needs concurrent access.

## Operability and Quality Bar
- Reliability/diagnosability: `scripts/dashboard status`,
  `scripts/chat-graph doctor`, dashboard tests, and launchd plist checks must
  explain stale or failed feeds without opening raw state.
- Security/privacy: runtime homes are `0700`; fixtures are synthetic; raw
  transcripts and secrets are never committed.
- Accessibility/mobile/responsive needs: dashboard text must stay readable and
  controls must remain usable on narrow screens; no visual-only status signal
  without text nearby.

## Open Questions and Decision Records
- Linear setup for this repo is not yet verified; `LINEAR.md` records repo-only
  mode until Trevor chooses a real Linear team/prefix.
- Usage-routing and autonomy are queued as V2 work. Do not implement them before
  the V1 product clarity pass is verified.
- Original ER-087 plan and build history remain in
  `/Users/gillettes/Coding Projects/global-implementations`; this repo is the
  canonical code/runtime home after the 2026-07-04 extraction.
