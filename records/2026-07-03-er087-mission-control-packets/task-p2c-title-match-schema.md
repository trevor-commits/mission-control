# Packet er087-p2c-title-match-schema — two bounded fixes from live-data proofs

Read `docs/MISSION_CONTROL_PLAN.md` §Part A in your clone. `scripts/chat-graph` + tests exist and are green — extend, do not regress.

## Fix 1 — audits title matching too strict (live: 4 edges from 46 `Audit:`-titled sessions)
Real titles drift: auditor says `Audit: Where was I?`, target is now `Where was I? - Chronicle`. Upgrade target matching in the titles collector, confidence discipline:
- exact (casefold, whitespace-trimmed) unique match → 0.7 (unchanged)
- normalized match (strip trailing ` (fork)`, ` - <suffix>` parentheticals/dash-suffixes) unique → 0.7, note='normalized'
- unique PREFIX match (audited-name is a prefix of exactly one session title, min 8 chars) → 0.6, note='prefix'
- multiple candidates at any tier → most-recent 0.5, note='ambiguous title' (existing behavior)
- no match → no edge (never guess below prefix)

## Fix 2 — edge uniqueness missing `source` (live schema: `UNIQUE(src, dst, type)`)
Plan requires (src, dst, type, source) so a strong delegations edge and a weak title edge for the same pair coexist; weak sources must never overwrite strong ones' evidence/confidence. Implement as REAL migration: bump SCHEMA_VERSION to 2; migration rebuilds edges table with `UNIQUE(src, dst, type, source)` preserving rows; upsert conflict target updated accordingly. `rebuild` path also lands on v2.

## Acceptance = `bash scripts/chat-graph.test.sh` exit 0 — all existing cases still green PLUS:
- fixture: auditor `Audit: Foo Bar` + target titled `Foo Bar - Chronicle` → audits 0.7 note='normalized'; target `Foo Bar Extended Adventures` (only candidate) → 0.6 note='prefix'; two prefix candidates → 0.5 ambiguous.
- fixture: same (src,dst,type) from two sources → TWO rows persist, each with own confidence/evidence; re-ingest doesn't cross-overwrite.
- migration: open a v1-schema fixture DB (build it in-test with the v1 DDL) with pre-existing edges incl. a suppressed one → v2 open migrates, rows preserved, suppression intact, `meta.schema_version`=2.

Shared invariants: as embedded below (unchanged).
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
