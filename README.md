# Mission Control

Mission Control is one local, offline dashboard for your AI coding work. It shows chat links, repo health, model usage, and background-job health in a page you open with a double-click.

## Use it

```bash
scripts/dashboard install     # copy the runtime + register the 5-min refresher
scripts/dashboard open        # open the dashboard in your browser
```

The page lives at `~/.mission-control/index.html` (installed copy), refreshes itself every 5 minutes, and works fully offline (no build step, no server, no internet). A "Mission Control" app on the Desktop opens it with one click.

## Included tools

| Tool | Job |
|---|---|
| `scripts/dashboard` | The CLI: `open`, `collect`, `refresh`, `status`, `install`, and `demo`. It builds dashboard feeds and serves the page. Failed feeds retain last-good data and use bounded retry backoff. Sibling feeds continue. `--force` skips the retry window. Test-only clocks, seams, and feeder overrides fail before writes unless `MISSION_CONTROL_HOME` is outside the canonical state tree. |
| `scripts/chat-graph` | Records how AI chats connect in `~/.chat-graph/graph.db`. Commands include `link`, `unlink`, `show`, `export`, `doctor`, and `rebuild`. Missing metadata uses one bounded `chat-source metadata --jsonl` batch. Partial or failed enrichment is reported as degraded health without blocking the graph. |
| `scripts/automation-status` | Reads the background-job registry (`dashboard/jobs.json`) + the scheduler and reports each job green/amber/red. |
| `scripts/usage-snapshot`, `scripts/scan-unfinished-work` | Vendored data sources for the usage + git tabs. Upstream copies live in the `global-implementations` repo. Reconcile local hardening with upstream before copying, then keep these copies in sync when upstream changes. |
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

Extracted from `global-implementations` on 2026-07-04. It was built there as ER-087. Full build history, work records, and the enforcement register remain there. Design and rationale: `docs/MISSION_CONTROL_PLAN.md`.
