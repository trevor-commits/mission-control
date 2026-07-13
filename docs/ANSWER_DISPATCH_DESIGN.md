# Answer Dispatch Design (ER-141)

Goal: when Trevor answers a decision in Mission Control, the answer becomes a
model-tuned goal prompt that is actually sent to the right agent — same chat,
new chat, or a different platform — chosen by fitness and usage headroom, with
quality/reliability as the primary concern. Register entry:
`global-implementations/records/requested-enforcements/2026-07-13-mission-control-answer-dispatch.md`.

## Principles

1. Reuse first. Every stage maps to an existing, already-hardened surface;
   this feature is plumbing between them, not new invention.
2. The dashboard stays file://-safe. The browser never sends anything; it
   queues. Sending is owned by a local dispatcher process.
3. Deterministic composition. Prompts are template-filled from structured
   decision data — no model call is needed to write the prompt, so
   composition is testable, lintable, and cheap.
4. Fail loud, hold safe. A prompt that fails the handoff lint, or a route
   with no healthy target, becomes a visible dashboard row — never a silent
   drop, never a degraded send.

## Pipeline (five stages)

Click → Queue → Compose → Route → Send + Receipt

### 1. Click → Queue
`dashboard decide answer <id> <n>` (existing transactional queue) gains a
dispatch step: after recording the answer it writes
`~/.mission-control/dispatch/queue/<decision-id>.json` carrying the decision
text, chosen option text, source chat key (provider:id) when the decision
came from a chat, repo, and severity. Entry points, in order of directness:
- Menu-bar panel app: runs the command directly — true one-click.
- Dashboard in `--serve` mode: a localhost POST can trigger the same command (later slice).
- Dashboard on file://: the option button copies the command (today's behavior, universal fallback).

### 2. Dispatcher process
`scripts/dispatch-runner` (Python stdlib, Bash 3.2-safe wrapper), installed as
a launchd interval job like the existing loose-end runner. Drains the queue;
each request is compose → route → send → receipt, single-flight per decision
id, idempotent by receipt existence, fail-open on malformed entries (skip +
surface, never crash the drain loop).

### 3. Compose — model-tuned goal prompts
Templates live in `dispatch/templates/<target>.md`. Every template produces
the goal-prompt handoff shape: first token `Goal:`, then `Runner:`, `Model:`,
`Reasoning:`/`Effort:`, context (decision text, chosen option, repo, evidence
paths, source chat), requirements, exact verification commands, durable-record
instructions (Work Record + Ripple + Self-audit for repo work), a 2-attempt
stop condition, and — for strong models — a Delegation defaults block (pinned
cheap helpers, one-tier escalation, no unpinned inheritance). Composition
rules that differ by target model:

| Target | Shape emphasis |
|---|---|
| Codex gpt-5.6-sol (high) | Full packet: explicit file scope, "Do not" fence, evidence-paste list; Codex works best with hard boundaries and named verification commands. |
| Claude (Fable/Opus) | Thick goal, thin process: state the outcome, constraints, and hard gates; delegate judgment; include the workflow cue for broad tasks; never over-script steps. |
| Claude-compatible GLM worker | Bounded mechanical slice: single outcome, exact commands, small diff scope, return-evidence contract (diff + verify output + claims). |
| Cursor | Repo-local slice with file list and no cross-repo reach; no stronger-model calls per the implement-parent rule. |

Every composed prompt must pass
`~/.codex/scripts/prompt-handoff-lint --response` (4,000-char limit spills to
a durable prompt file + `Prompt file:` pointer automatically). Lint failure =
hold in queue + red dashboard row.

### 4. Route — same chat, new chat, or new platform
Inputs: chat-graph export (is the source chat live? same repo?), usage feed
`~/.mission-control/data/usage.json` (headroom per platform), tiered-delegation
policy (minimum tier for the task class).

Decision order:
1. Tier floor first: security / auth / migration / merge-gate / governance
   decisions route UP (native Claude Opus+ or Codex high) regardless of headroom.
2. Same chat when the source chat is live, in the same repo, and the answer
   continues that chat's own open question → `cross-agent-mailbox send --to
   <session-id>` (pull-mailbox; the receiver fences it as untrusted context).
3. New chat when the source chat is stale/closed or the answer opens a fresh
   work packet → `spawn-claude-worker` / `spawn-codex-worker` with the
   composed prompt; child-binding proof rules apply before any follow-up.
4. New platform when the preferred platform's usage decision is "Wait"
   (≥90% or hard limit) and another platform at-or-above the tier floor reads
   "Can use" → spawn there instead; record the routing reason.
5. No healthy target → hold + dashboard red row ("dispatch blocked: no
   platform with headroom at the required tier").

### 5. Send + Receipt
Every dispatch writes `~/.mission-control/dispatch/receipts/<decision-id>.json`:
target platform/model/chat id, composed prompt path, lint result, routing
reason, send transcript (spawn output / mailbox ack), attempts. The decisions
feed carries receipt state so the dashboard shows "Dispatched → Codex
gpt-5.6-sol (new chat) · view prompt" or the failure. Two failed attempts
escalate to a new decision instead of retrying forever.

## Safety boundaries
- The dispatcher only acts on decisions whose options were pre-declared in
  the decision queue; it never derives new scope from free text beyond the
  decision's own body.
- Outward-facing / irreversible / secret-requiring work stays human-gated:
  the composed prompt instructs the worker on hard gates; the dispatcher
  itself never merges, pushes to main, publishes, or spends money.
- Mailbox bodies remain untrusted inter-agent notes on the receiving side.
- No network beyond the existing spawn/mailbox helpers; no new dependencies.

## Delivery sequencing
- Slice 1 (Codex packet): queue writer + dispatch-runner + composer + lint
  gate + receipts, with the sender STUBBED (writes the prompt file and a
  would-send receipt). Proves composition and routing decisions safely.
- Slice 2 (separate packet, after slice 1 is audited): wire real
  `spawn-codex-worker` / `spawn-claude-worker` / `cross-agent-mailbox` sends
  behind a per-platform allowlist; five-dispatch live proof.
- Slice 3: panel one-click + `--serve` POST endpoint; dashboard receipt UI
  (Claude-owned `index.html` work).
- Template authorship: Claude (Fable) writes and maintains
  `dispatch/templates/*` — prompt wording is design work; Codex consumes them.
