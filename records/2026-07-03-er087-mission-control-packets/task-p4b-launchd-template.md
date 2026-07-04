# Packet er087-p4b-launchd-template — the ticker

Read the INVARIANTS block below. Study `launchd/com.gillettes.nightly-review.plist.template` in your clone and copy its safe-exec + stable-runtime-copy pattern VERBATIM (it exists because the repo worktree can switch branches under a running job — documented in that template).

## Goal
Author `launchd/com.gillettes.mission-control.plist.template`.

## Build exactly
Label `com.gillettes.mission-control`; `StartInterval` 300; RunAtLoad true; runs `scripts/dashboard collect --due` via the same stable-copy exec pattern as the nightly-review template; `__HOME__` + `__REPO__` placeholders exactly like the sibling templates; StandardOut/Err under `__HOME__/.mission-control/logs/launchd.{out,err}.log`; low-priority nice if sibling templates set it.

## Acceptance
`t="$(mktemp -d)/mc.plist"; sed -e "s|__HOME__|$HOME|g" -e "s|__REPO__|$(pwd)|g" launchd/com.gillettes.mission-control.plist.template > "$t" && plutil -lint "$t"` → `OK`.


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
