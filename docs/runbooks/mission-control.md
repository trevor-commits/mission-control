# Runbook: Mission Control Dashboard

This dashboard is a local mission-control shell at `~/.mission-control/index.html` powered by `scripts/dashboard`.
It combines usage, git, chats, and automation feeds from the ER-087 scripts into one local health view.

## What it is + daily entry
- Primary daily command:
  - `scripts/dashboard open`
- One command for install, one for uninstall:
  - `scripts/dashboard install`
  - `launchctl bootout gui/$UID/com.gillettes.mission-control && rm -rf ~/.mission-control`

## State dirs

| Path | What it is | Permission | Delete policy |
|---|---|---:|---|
| `~/.mission-control` | Runtime state and shell cache (`data`, `logs`, copied shell). | `chmod 700` | **Derived state**: safe to delete when you are not relying on the current shell cache. |
| `~/.chat-graph` | Canonical graph DB + journals used by chat links and sessions. | `chmod 700` | **Safe only if no manual links exist**; see warning below. |

> WARNING:
> `~/.chat-graph` may hold manual work after first `chat-graph link`/`unlink` usage.
> NEVER run `rm -rf ~/.chat-graph` after that. Run this backup first:
> `sqlite3 ~/.chat-graph/graph.db ".backup '$HOME/chat-graph-backup.db'"`
> and restore using `chat-graph rebuild` (journal replay) when needed.

## Feed freshness semantics
- Freshness is per-feed from `window.MC.feeds.<feed>.generated_epoch` against each feed cadence.
- Dot states are: green (on time), amber (aging), red (errored/stale).
- “Stale” feeds must show **desaturated visuals + a stale banner** so old data is visibly downgraded.
- A frozen green dot is treated as a defect; report that as a bug and force a rebuild/recollect.

## `--serve` fallback (file:// script blocking)
- Default open uses the local shell path and `file://` file loading.
- If a browser blocks `file://` scripted loads (or local JS feed loading is denied), use:
  - `scripts/dashboard open --serve`
- Run `--serve` when the shell opens but feeds fail to render or feed files do not load as expected.

## Troubleshooting
- Feed is red:
  - `scripts/dashboard refresh <feed>`
  - then read `~/.mission-control/logs/collect.log`
- Chats tab is empty:
  - `scripts/chat-graph doctor`
- Scan errors are accumulating:
  - `~/.chat-graph/logs/scan-errors.log`
- Rebuild chat graph:
  - `scripts/chat-graph rebuild`
- Launchd job is dead or missing:
  - `launchctl list | grep mission-control`
  - if missing/unhealthy: `launchctl bootout gui/$UID/com.gillettes.mission-control && scripts/dashboard install`

## Design rationale
- Full architecture, freshness model, and security posture are defined in
  `docs/MISSION_CONTROL_PLAN.md`.
