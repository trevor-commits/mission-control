# Packet er087-p7-id-resolution — partial-id resolution for link/unlink/resolve (live-found)

Read `docs/MISSION_CONTROL_PLAN.md` §Part A in your clone. `scripts/chat-graph` + `.test.sh` exist and are green — extend, do NOT regress. New test REQUIRED (must fail without the fix).

## The bug (live-reproduced 2026-07-03)
`unlink 541d686b-... 019ecd05 --type spawned` stored a suppression keyed on the LITERAL `019ecd05` — a prefix, not the full stored id `019ecd05-e57e-7c91-87e5-3a68959df3df`. The source-independent suppressions table + NOT EXISTS filter is CORRECT (verified: full-id unlink survives reingest, re-link restores). But `link`/`unlink`/`resolve` accept a bare partial id and write it verbatim, so a user typing a prefix silently suppresses the WRONG (non-existent) key and the real edge stays visible. The packet spec always required "accept full or unique-prefix ids; resolve to the canonical id."

## Fix
Add an id-canonicalizer used by `link`, `unlink`, `resolve` (and `show`) BEFORE any DB write/read on an id:
- exact match in `sessions.id` → that id.
- else unique prefix match against `sessions.id` (and, as a fallback, distinct ids appearing in `edges.src`/`edges.dst`) → the full id.
- zero matches → keep the literal (may be a not-yet-ingested id) BUT print a one-line stderr warning `note: '<id>' not found in graph; using as-is`.
- multiple prefix matches → ERROR listing up to 5 candidates, exit non-zero, write nothing.
Apply to BOTH ids in link/unlink. Journal + suppressions + edges all get the canonical id.

## Acceptance = `bash scripts/chat-graph.test.sh` exit 0, all existing cases green PLUS:
- fixture: ingest an edge whose dst full id is `aaaaaaaa-1111-2222-3333-444444444444`; `unlink <src> aaaaaaaa --type spawned` (PREFIX) → suppression row stores the FULL dst; `show <src>` and `export` exclude the edge (currently they would NOT).
- ambiguous prefix (two sessions share it) → unlink errors with candidate list, exit nonzero, no suppression written.
- unknown id → literal kept + warning; no crash.

Shared invariants as embedded below.
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
