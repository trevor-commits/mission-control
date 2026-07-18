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

## Desktop-first glance surface (ER-134)

- **Home** opens light by default with at most three **Needs you** decisions; use **Show more details** for the full depth view. Toggle **Dark mode** in the top strip.
- **Corner panel:** `dashboard panel` installs `~/.mission-control/panel.html`, stages `~/.mission-control/Mission Control Panel.app` (LSUIElement), launches the menu-bar app (`MC`), and idempotently installs `com.gillettes.mc-panel` KeepAlive+RunAtLoad so MC returns after login/reboot. First launch may compile `scripts/mc-panel.swift` with `swiftc`.
- **Answer a choice:** `dashboard decide answer <decision-id> <n>` writes a Goal prompt under `~/.mission-control/prompts/` and resolves the decision. Menu-bar option clicks run `dashboard decide answer` directly via the `mcDecide` bridge; Home browser option buttons still copy that command.

## Decision-queue admission, rollup, and severity bypass (Phase 0 item 0.3)

`scripts/queue_admission.py` is a pure classification/rollup module (no
subprocess, no exec — see its module docstring for the authority invariant)
consumed by `scripts/decision-alert`:

- **Admission classification** — every open row gets exactly one of
  `noop` / `workorder` / `operator_decision`, deterministically, via
  `queue_admission.classify_row()`. A `workorder` packet
  (`build_workorder_packet()`) is advisory data only, pointed at
  `~/.cross-agent/autonomous-loop/ready-packets/`; it carries an
  `authority_envelope` (capability/risk/expiry/rollback) but grants no
  execution — the loop's own authority policy (Agency v2, currently no live
  runtime effect) is the only thing that could ever act on it.
- **Rollup, not row-dedup** — `decision-alert rollup` presents one card per
  exact-normalized-text group (`queue_admission.normalize_text()`), members
  kept underneath for provenance. Answering a card supersedes a member
  ONLY when the STRICTER **action + owner + target** equivalence contract
  holds (`queue_admission.same_equivalence()` / `plan_rollup_supersession()`)
  — identical wording from different chat sessions does not auto-close
  every occurrence. See the docstring on `same_equivalence()` for the exact
  contract text.
- **One queue, lane views** — `decision-alert lanes` derives
  business/personal/infra/faith-personal-projects counts from the `domain`
  field; there is no physical per-lane queue.
- **Group re-ask suppression** — in the automatic alert path, a NEW decision
  whose normalized text matches a different decision already alerted within
  the last 7 days is not re-presented identically: it folds silently into
  the group (reported under `suppressed_group` with the prior-alerted peer
  id) unless its stored severity outranks the alerted peer, in which case
  it is allowed through and a `group_escalation` event is recorded. The
  same decision's own 24-hour re-alert cadence and the explicit
  `--decision-id` targeted bypass are unchanged.
- **Severity bypass** — `decision-alert alert --decision-id <id> [--decision-id <id> ...] [--send]`
  targets specific decisions directly, bypassing normal eligibility
  ordering AND `--fresh-within` (a queue-age filter would defeat the point
  of surfacing an old, buried security item). Without `--send` it previews
  the exact would-send text (`would_send_message`, built via the existing
  `_alert_message()` formatter — never a new notifier) with zero external
  side effects. `--decision-id` still respects the 24h alert-receipt /
  60s in-flight-reservation dedup, so it cannot double-fire a ping that
  already went out.
- **Deploy gate** — the new `admission_class` / `admission_rule` / `domain` /
  `severity` / `required_action` / `deadline` / `snoozed_until` columns are
  additive (mirrors the existing `anchor_ref` migration) and OFF by default:
  set `MISSION_CONTROL_ADMISSION_SCHEMA=1` in the installed job's
  environment to activate the migration + ingest-time stamping. `rollup`
  and `lanes` work read-only regardless of that flag (they recompute
  classification fresh from `text` every call). Tests:
  `scripts/queue_admission.test.py` (equivalence contract, classification
  determinism, authority invariant) plus the existing
  `scripts/decision-alert.test.sh` / `scripts/dashboard.test.sh` suites,
  which cover the new `rollup`/`lanes`/`alert --decision-id` surfaces via
  regression (all green as of this change).
