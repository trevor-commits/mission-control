# Mission Control

One local, offline dashboard for how your AI coding work is going — chats and how they connect, git health across all repos, model usage/credits, and background-job health — in one page you open with a double-click.

## Use it

```bash
scripts/dashboard install     # copy the runtime + register the 5-min refresher
scripts/dashboard open        # open the dashboard in your browser
```

The page lives at `~/.mission-control/index.html` (installed copy), refreshes itself every 5 minutes, and works fully offline (no build step, no server, no internet). A "Mission Control" app on the Desktop opens it with one click.

## What is inside

| Tool | Job |
|---|---|
| `scripts/dashboard` | The CLI: `open`, `collect`, `refresh`, `status`, `install`, `demo`. Builds the Automation, Usage, Git, Chats, Decisions, and Brief feeds and serves the page. Failed feeds keep last-good data and use bounded per-feed retry backoff; sibling feeds continue and `--force` bypasses the retry window. Synthetic clocks/test seams/feeder overrides fail before writes unless `MISSION_CONTROL_HOME` resolves outside the canonical default state tree. |
| `scripts/chat-graph` | Records how AI chats connect (audits, spawned workers, signals, shared issues) into `~/.chat-graph/graph.db`; `link`/`unlink`/`show`/`export`/`doctor`/`rebuild`. Missing session metadata is enriched through one bounded `chat-source metadata --jsonl` batch, with partial/failed enrichment exported as degraded health rather than blocking the graph. |
| `scripts/automation-status` | Reads the background-job registry (`dashboard/jobs.json`) + the scheduler and reports each job green/amber/red. |
| `scripts/usage-snapshot`, `scripts/scan-unfinished-work` | Vendored data sources for the usage + git tabs. Upstream copies live in the `global-implementations` repo; keep these in sync when the upstream changes. |
| `scripts/loose-ends` | Pick up unfinished work: ranks the open-work ledger, attention board, `todo.md` Active Next Steps, and git state. `show`, `resolve`, and `prompt` (Goal-format resume skeleton). Paired with the `loose-ends` skill in `skills/`. |
| `scripts/loose-end-runner` | Dry-run proposals for stale-branch pushes. never merges, force-pushes, deletes, or edits human docs. |
| `scripts/dashboard attention` | The attention lane: `add`, `resolve`, `list` on `~/.mission-control/attention/queue.jsonl`. |
| `scripts/decision-alert`, `scripts/compose-decision-prompt.py` | Decision delivery lifecycle: raise a decision, take the answer, compose the resume prompt. |
| `scripts/morning-brief`, `scripts/morning-brief-deadman` | The Morning Brief and its independent deadman. |
| `scripts/self-repair`, `scripts/usage-watch`, `scripts/headroom-refresh` | Fail-closed runtime repair, usage silence detection, on-demand headroom. |
| `dashboard/index.html` | The page — one self-contained file (design tokens + layout CSS + renderers). |
| `dashboard/fixtures/*.json` | Synthetic sample feeds for `demo` + the render tests. No real chat ids or transcript text. |

## Repo notes

Start with `AGENTS.md`. The local governance files are intentionally present in
this repo now: `PROJECT_INTENT.md`, `todo.md`, `CONTINUITY.md`, `COHERENCE.md`,
`LINEAR.md`, and `CLAUDE.md`.

## Tests

```bash
scripts/verify.sh
```

That command runs every committed shell/Python/Node suite, the real-browser
desktop/mobile file:// gate, the scanner self-test, strict OpenSpec validation,
and static syntax checks. Focused suites remain available for narrow iteration.

## Safety

State dirs (`~/.chat-graph`, `~/.mission-control`) are created `chmod 700`, never committed, never served on the network (127.0.0.1 only under `--serve`). Committed fixtures are synthetic. Transcript-derived text is redacted before display.

## History

Extracted from `global-implementations` on 2026-07-04 (built there as ER-087; full build history, work records, and the enforcement register stay in that repo). Design + rationale: `docs/MISSION_CONTROL_PLAN.md`.
