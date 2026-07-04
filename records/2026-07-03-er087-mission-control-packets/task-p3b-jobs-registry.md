# Packet er087-p3b-jobs-registry — the real jobs registry

Read the INVARIANTS block below + `docs/MISSION_CONTROL_PLAN.md` §Part B "Automation health". `scripts/automation-status` exists (previous packet).

## Goal
Author `dashboard/jobs.json` — the committed registry of expected background jobs (expectations as data).

## Build exactly
Survey real labels first: run `launchctl list | grep -i gillette` (read-only) and inspect `~/Library/LaunchAgents/com.gillette*.plist` (read-only) to get true labels/schedules. Declare AT LEAST: `com.gillettes.nightly-review` (calendar 23:30; evidence `~/.claude/nightly-review/reports/` newest file; err log per its plist), `com.gillettes.usage-snapshot` (interval 1800s; evidence `~/.usage-snapshot/history.jsonl`), delegation-audit label as found (evidence `~/.delegation-audit/last-scan.json`), the `com.gillette.repo-state-watch.*` labels (evidence `~/.local/state/repo-state-watcher/last-scan.tsv`), `com.gillette.repo-groom` (interval 10800s; evidence `~/.local/state/repo-state-watcher/groom-last.txt`), mobile-connect poller label as found, `com.gillettes.mission-control` (interval 300s; evidence `~/.mission-control/data/automation.json`) and a `chat-graph-ingest` pseudo-job (kind interval 86400s; evidence `~/.chat-graph/last-ingest`; note: not a launchd label — mark with `"pseudo": true` so automation-status checks evidence only). Every entry: label, plain-words name, kind, schedule string, expected_freshness_s (2× cadence rule of thumb; calendar jobs 26h), evidence paths that ACTUALLY exist today (or are marked expected-offline/pseudo), err_log path from the plist when present. Backup `.plist.bak-*` files ignored. JSON, 2-space indent, keys sorted.

## Acceptance
`scripts/automation-status --json --registry dashboard/jobs.json | python3 -m json.tool >/dev/null && grep -q "com.gillette.repo-state-watch" dashboard/jobs.json && grep -q "com.gillettes.nightly-review" dashboard/jobs.json` → exit 0. In your evidence, include the human-table output of `scripts/automation-status --registry dashboard/jobs.json` against the REAL machine so the governor can sanity-check states.


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
