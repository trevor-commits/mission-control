# Packet er087-p2b-chats-fixture — synthetic chats contract fixture

Read the INVARIANTS block below + `docs/MISSION_CONTROL_PLAN.md` §Part B (feed envelope) + §Part A (export contract) in your clone. `scripts/chat-graph validate-export` exists (previous packet).

## Goal
Author `dashboard/fixtures/chats.json` — the shared contract artifact between the chat-graph exporter and the dashboard renderer.

## Build exactly
One JSON file, SYNTHETIC ONLY (invented ids like `claude:aaaaaaaa-1111-...`, invented titles — no real session ids, no transcript text): full `schema:1` feed envelope (`feed:"chats"`, plausible generated_at/epoch, cadence_s 1800, ok true, error null) whose `data` contains: ≥8 nodes across ≥2 providers (one `live:true`, one with 2 open_ends incl. kinds closeout_handoff + register_unverified, every node with non-empty title/repo/resume_cmd/view_cmd, one title containing an apostrophe + emoji for renderer hostility); ≥2 connected clusters; edges covering EVERY v1 type (spawned, audits, signaled, references, continues, related_manual) with source + confidence spread incl. one sub-0.7 edge carrying `unlink_cmd`; ≥1 topic group with 3 members; repo_annotations for 2 repos; stale_providers ["hermes"]; counts{new_today, scan_errors_24h, signal_yield}.

## Acceptance
`python3 scripts/chat-graph validate-export dashboard/fixtures/chats.json` → exit 0. File pretty-printed (2-space indent), < 15 KB.


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
