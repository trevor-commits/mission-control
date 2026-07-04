# Packet er087-p4c-runbook — operator doc

Read the INVARIANTS block below + `docs/MISSION_CONTROL_PLAN.md` (whole) in your clone. Everything it documents now exists in your clone — verify claims against the actual scripts, do not invent flags.

## Goal
Author `docs/runbooks/mission-control.md` (≤ ~120 lines, plain words first, commands exact).

## Must contain
- What it is (2 lines) + the one-command daily use: `scripts/dashboard open`.
- Install/uninstall: `scripts/dashboard install`; uninstall = `launchctl bootout gui/$UID/com.gillettes.mission-control && rm -rf ~/.mission-control`.
- State dirs table: `~/.mission-control` (derived, safe to delete) vs `~/.chat-graph` — **WARNING block: contains manual links after first `chat-graph link`/`unlink`; NEVER `rm -rf` after that — run `sqlite3 ~/.chat-graph/graph.db ".backup '$HOME/chat-graph-backup.db'"` first; `chat-graph rebuild` replays the manual journal**. chmod 700 on both.
- Freshness semantics (dots, per-feed cadence, stale = desaturate + banner; "a frozen green is a bug, report it").
- `--serve` fallback for file:// script blocking + when to use it.
- Troubleshooting: feed red (run `scripts/dashboard refresh <feed>` and read `~/.mission-control/logs/collect.log`), chats tab empty (`scripts/chat-graph doctor`), scan errors (`~/.chat-graph/logs/scan-errors.log`), rebuild command, launchd job dead (`launchctl list | grep mission-control`, bootout+install).
- Pointer line to `docs/MISSION_CONTROL_PLAN.md` for design rationale.

## Acceptance
`grep -q "chmod 700" docs/runbooks/mission-control.md && grep -q "dashboard install" docs/runbooks/mission-control.md && grep -q "launchctl bootout" docs/runbooks/mission-control.md` → exit 0. Every command in the doc must actually exist in the clone's scripts (verify before writing).


---

# Shared invariants (pasted by reference into every ER-087 packet — read FIRST)

- python3 stdlib only; any shell must be bash-3.2-compatible; no new dependencies; no network calls at test time.
- Tests: `scripts/<name>.test.sh` convention — mktemp fixtures only, one `PASS:`/`FAIL:` line per case, exit 0 only when all pass, whole suite < 90 seconds.
- YOU RUN WRITE-SANDBOXED: writes outside your clone + /tmp are DENIED. All code MUST honor env overrides for state + source roots, and tests MUST use them with mktemp dirs:
  - `CHAT_GRAPH_HOME` (default `~/.chat-graph`), `MISSION_CONTROL_HOME` (default `~/.mission-control`)
  - collector source roots: `CHAT_GRAPH_CROSS_AGENT_ROOT` (default `~/.cross-agent`), `CHAT_GRAPH_CLAUDE_ROOT` (default `~/.claude/projects`), `CHAT_GRAPH_CODEX_ROOT` (default `~/.codex/sessions`), `CHAT_GRAPH_SESSION_INDEX` (default `~/.codex/session_index.jsonl`), `CHAT_GRAPH_CHAT_SOURCE` (default `~/.codex/scripts/chat-source`)
  - dashboard feeder overrides: `DASHBOARD_CMD_USAGE`, `DASHBOARD_CMD_GIT`, `DASHBOARD_CMD_CHATS`, `DASHBOARD_CMD_AUTOMATION` (each replaces the real feeder command in tests); `AUTOMATION_STATUS_LAUNCHCTL` (replaces `launchctl` binary in tests)
  - Tests never read or write real `$HOME` paths.
- Security (hard, not compressible): state dirs created `chmod 700`; transcript-derived display text passes display-time redaction (mirror the redaction pattern in `scripts/search-transcripts` — grep it in your clone); dashboard renderers use `textContent` only, never `innerHTML`; committed fixtures are SYNTHETIC — no real session ids, no real transcript text, no secrets.
- Scope: do not create or modify ANY file outside your packet's scope glob. No scratch/notes/log files.
- Evidence to return in your final message: (1) full diff, (2) verbatim verify-command output incl. exit code, (3) claims list — done / deliberately untouched / uncertain. Missing evidence = automatic fail.
- Context: read `docs/MISSION_CONTROL_PLAN.md` in your clone — it is the authoritative design. Your packet section names the parts that bind you.
