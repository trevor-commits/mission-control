# Packet er087-p1-graph-core — chat-graph CLI core

Read FIRST: `~/.cross-agent/delegations/er087-specs/INVARIANTS.md` is embedded below by your governor; also read `docs/MISSION_CONTROL_PLAN.md` §"Part A — chat-graph data layer" + §"Hardening addenda" in your clone. They bind this packet.

## Goal
Create `scripts/chat-graph` (python3-stdlib CLI, executable) + `scripts/chat-graph.test.sh`. This packet = schema + structured collectors + manual commands + durability plumbing. (Transcript scanning/export = next packet — leave clean seams.)

## Build exactly
1. **DB** at `$CHAT_GRAPH_HOME/graph.db` (dir auto-created chmod 700; WAL; `PRAGMA busy_timeout=5000`). Tables per plan §Part A: `sessions`, `edges`, `session_topics`, `open_ends`, `collector_state`, plus `meta(key,value)` with `schema_version=1`; on open: version < code → run linear idempotent migrations; version > code → abort with plain one-line message.
2. **Make-or-break semantics**: edge upsert = `INSERT .. ON CONFLICT(...) DO UPDATE` that NEVER writes `status`; `unlink` sets `status='suppressed'` on matching (pair,type) rows AND pre-inserts a `source='manual'` suppressed row if none exists, so future collectors land on the conflict key and cannot resurrect. `audits` direction = auditor→audited. Undirected types (`related_manual`) canonicalize pair order.
3. **Manual-actions journal**: `link`/`unlink`/`resolve` append one JSON line to `$CHAT_GRAPH_HOME/journal/manual.jsonl` (flush+fsync) BEFORE the DB write. `rebuild` = fresh schema + run collectors + replay journal in order.
4. **Collectors** (subcommand `ingest [--collector NAME]`; each re-lists fully, upsert-idempotent; mkdir-lock `$CHAT_GRAPH_HOME/ingest.lock` around the whole ingest — lock held → print skip notice, exit 0):
   - `delegations`: `$CHAT_GRAPH_CROSS_AGENT_ROOT/delegations/*/state.json` → spawned governor→worker, confidence 1.0 when `handshake_verified` == "yes" else 0.8; evidence JSON {path, handshake}.
   - `mailbox`: `$CHAT_GRAPH_CROSS_AGENT_ROOT/mailbox/<to>/{inbox,read}/*.json` → signaled from→to 1.0; skip `from` absent/"unknown"; tolerate schema field `cross-agent-mailbox/v1`.
   - `titles`: `$CHAT_GRAPH_SESSION_INDEX` (JSONL {id, thread_name}) + best-effort `$CHAT_GRAPH_CHAT_SOURCE list` — patterns CASE-INSENSITIVE + space-tolerant: `^audit:\s*(.+)` → audits auditor→audited (match target by title, 0.7 unique / 0.5 ambiguous+most-recent with note='ambiguous title'); `^worker:\s*(.+?)\s+-\s+` → spawned source→worker.
   - Session metadata cached via `$CHAT_GRAPH_CHAT_SOURCE describe` when available; failure = degraded (keep cached, mark provider in a `stale_providers` note in stats), NEVER fatal. Untitled fallback chain: title → first_prompt 60 chars → `(untitled) <id-prefix-8>`.
5. **Commands**: `ingest`, `link A B --type T [--note ..]`, `unlink A B [--type T]`, `resolve <id> <text-hash>` (suppresses an open_end, journaled), `show <id>` (card + neighbors grouped by type + open ends; prints one-line staleness warning if last ingest > 30 min; NEVER auto-ingests), `stats` (per-collector row counts, cursors, last-run), `doctor` (dirs+perms 700, chat-source resolves + smoke, `PRAGMA quick_check`, journal readable, last-ingest age, free disk > 1 GB, scan-error count — exit 0 healthy / 1 problems, one line each), `rebuild`, `--self-test` (points at the test script). Touch `$CHAT_GRAPH_HOME/last-ingest` marker on every successful ingest.
6. Bare ids: accept full or unique-prefix ids; resolve provider via chat-source when needed; ambiguous → error listing candidates.

## Acceptance = `bash scripts/chat-graph.test.sh` exit 0, covering AT MINIMUM (fixture provenance dirs under mktemp):
- suppression survives re-ingest: link → unlink → ingest twice → still suppressed (THE test).
- journal rebuild: link + unlink → `rm graph.db` → `rebuild` → suppression still active.
- idempotency: ingest twice → identical row counts.
- delegations fixture with handshake_verified yes/no → 1.0 / 0.8.
- mailbox fixture → signaled edge with from/to.
- title drift fixture: BOTH `Audit: Foo` and `audit:Foo` forms match; ambiguous duplicate-title case → 0.5 + note.
- untitled session → fallback title non-empty.
- concurrent ingest: second process while lock held exits 0 with skip notice.
- migration guard: db with schema_version=99 → plain abort message, nonzero exit.
- `doctor` on healthy fixture home → exit 0; on missing journal dir → exit 1 with plain line.
All state via `CHAT_GRAPH_HOME=$(mktemp -d)`.


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
