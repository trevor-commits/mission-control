# Packet er087-p3a-automation-status — background-job health collector

Read the INVARIANTS block below + `docs/MISSION_CONTROL_PLAN.md` §Part B "Automation health" + §Hardening (jobs.json guards) in your clone.

## Goal
Create `scripts/automation-status` (python3-stdlib, executable) + `scripts/automation-status.test.sh`.

## Build exactly
1. Reads a registry JSON (`--registry PATH`, default `dashboard/jobs.json` relative to repo root; tolerate missing → `ok:false` envelope): entries {label, name, kind: interval|calendar|keepalive, schedule (human string), expected_freshness_s, evidence: [{role, path}], err_log, retired?: bool}.
2. Truth sources: `launchctl list` output (binary overridable via `AUTOMATION_STATUS_LAUNCHCTL` for tests; parse the stable 3-column PID/status/label form; parse failure → every registry job state `degraded`, NEVER all-red), evidence file mtimes (`~` expanded; `/Volumes/T7/...` path with T7 unmounted → state `offline-media`, never red), err_log tail (last line, ≤200 chars).
3. States: `green` (loaded + freshest evidence within expected_freshness_s; keepalive additionally requires PID), `yellow` (loaded but evidence stale OR last exit nonzero), `red` (not loaded, or stale AND nonzero exit), `offline-media`, `retired` (flag true → grey, excluded from exception counts), `degraded`, plus top-level `unregistered: []` for live `com.gillette*` labels absent from the registry.
4. Output: human table (default) and `--json` wearing the standard feed envelope (`feed:"automation"`, cadence_s 300, data{checked_at, t7_mounted, jobs[], unregistered[]}). Exit 0 always when it could run; data carries the states (the dashboard CLI decides exit codes).

## Acceptance = `bash scripts/automation-status.test.sh` exit 0 (fixture registry + stub launchctl script via env; mktemp evidence files):
- green job (fresh evidence + loaded).
- broken job → red (not loaded, stale evidence) with err_log last line captured.
- loaded but stale evidence → yellow.
- T7-style path with root dir absent → offline-media.
- live label missing from registry → in unregistered[].
- retired:true → state retired, excluded from any exception counting field.
- stub launchctl printing garbage → all jobs degraded, exit still 0, ok:true with note.
- `--json` parses + envelope fields present.


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
