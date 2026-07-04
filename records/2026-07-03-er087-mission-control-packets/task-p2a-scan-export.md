# Packet er087-p2a-scan-export — transcript scanner + open-ends + export

Read FIRST: the INVARIANTS block below + `docs/MISSION_CONTROL_PLAN.md` §Part A + §"Hardening addenda" (first-scan design binds you) in your clone. `scripts/chat-graph` core exists (previous packet) — extend it; do not regress its tests.

## Goal
Extend `scripts/chat-graph` + `scripts/chat-graph.test.sh`: one incremental transcript scanner, open-ends, export snapshot, validate-export.

## Build exactly
1. **Scanner** (`ingest` gains it; `--full` rescans all, `--limit-files N` caps to N newest and writes cursors but no completion marker): walks `$CHAT_GRAPH_CLAUDE_ROOT/**/*.jsonl` (session id = filename) + `$CHAT_GRAPH_CODEX_ROOT/**/rollout-*.jsonl` (thread id from filename). Per-source cursors (mtime+size) in `collector_state`; unchanged files skipped; ONE DB transaction per file. Enumerate first, newest-first; stderr progress every 2s (`[scan] n/total · pct · ETA · errors k`; `\r` when TTY else plain lines). Per-line JSONDecodeError → count + append `path:lineno: reason` to `$CHAT_GRAPH_HOME/logs/scan-errors.log`; per-file OSError/UnicodeDecodeError → skip+log; NEVER abort the pass; exit 1 only if >20% of files errored. Skip+warn files >200 MB. Line prefilter before json.loads: substring any of `Spawned-`, `Session Closeout`, `ER-`, `GR-`, or a UUID-shaped candidate.
2. **Signals — from user+assistant message text ONLY, never tool_result/system/hook content** (Claude JSONL: use message role + content blocks of type text; Codex: payload equivalents):
   - `Spawned-by: parent_provider=.. parent_id=.. handshake=..` in a session → spawned parent→this 1.0 (source `spawn_header`); `Spawned-child: provider=.. child_id=..` → spawned this→child 0.95.
   - Foreign known-session-id mentions (ids seen in sessions table or filenames) → references mentioner→mentioned 0.9; exclude self, exclude pairs already covered by spawn headers.
   - `\b(ER|GR|HB|HR)-\d{3}\b` → `session_topics` rows; per-session cap 8 (keep most frequent). NO pairwise same_issue edges.
   - Resume-fork: record each session's FIRST message `uuid`; two sessions sharing it → continues later→earlier 1.0 (source `resume-fork`); dedupe open_ends across the pair by text_hash.
   - `Session Closeout` blocks: `Handoff:` non-trivial text → open_ends (kind `closeout_handoff`, sha1 text_hash); sets sessions.closeout_seen. Open_end auto-resolve (`resolved_at`) when the signal disappears on a later pass. Second open-end source: session mentions a register code whose row in `ENFORCEMENT_REQUESTS.md` (path via env `CHAT_GRAPH_REGISTER` default the repo file) is not `verified` → kind `register_unverified`.
   - `sessions.first_seen_at` set on first insert.
3. **Export**: `export --json [--out PATH]` → atomic tmp+rename to `$CHAT_GRAPH_HOME/export/graph.json`, envelope `{schema:1, feed:"chats", generated_at, generated_epoch, cadence_s:1800, ok, error, data:{nodes[], edges[], topics[], repo_annotations[], stale_providers[], counts{new_today, scan_errors_24h, signal_yield}}}`. Nodes: provider, id, title(redacted), repo, last_activity, first_seen_at, live(<30 min), closeout_seen, open_ends[], `resume_cmd` (`claude --resume <id>` / codex equivalent), `view_cmd` (`chat-source full <id>`). Edges: src `provider:id`, dst, type, source, confidence, note; sub-0.7 edges add `unlink_cmd`. Topic groups from session_topics (≥2 members). repo_annotations from `scan-unfinished-work --json` when runnable (env `CHAT_GRAPH_SCAN_CMD` override; absent → empty + note). Export runs incremental ingest first when cursors stale >30 min (the ONLY catch-up entry).
4. **`validate-export <file>`**: envelope + required fields + non-empty titles + confidence ranges; exit 0/1 with plain-line errors.
5. `stats` gains: `signal_yield` (files scanned vs files yielding ≥1 signal; >100 scanned with 0 → warning line), `scan_errors_24h`.

## Acceptance = `bash scripts/chat-graph.test.sh` exit 0 — ALL packet-1 cases still green PLUS:
- fixture Claude session with a `Spawned-by:` header line → spawned 1.0 edge.
- hook-noise fixture: register code inside a tool_result block → ZERO topics extracted (the role filter).
- resume-fork fixture pair (shared first uuid) → continues 1.0 + open_ends deduped.
- garbage fixture: truncated JSON line mid-file → scan completes, error logged, other lines ingested.
- cursor proof: rescan with nothing changed → "0 new/changed files".
- `--limit-files 2` on a 5-file fixture → exactly 2 scanned, cursors written.
- closeout fixture → open_end created; second pass with block removed → resolved_at set.
- export → validate-export round-trip green; export atomicity (no partial file on simulated interrupt is OK to skip — tmp+rename pattern asserted by filename check).
- hostile title fixture (apostrophe + emoji) → export JSON parses, title intact.


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

---

## Carry-over findings from packet 1 live proof (fix in THIS packet; same scope glob)
1. **chat-source bridge is a dead end as built**: `chat_source("list")` (~line 287) — the REAL `chat-source list` scans all six provider stores and takes >2 minutes (measured; the 8s timeout always fires) → every ingest reports `degraded providers: chat-source` and session metadata stays empty (`(untitled)`, repo `-`). Replace with lazy per-session enrichment: after collectors run, select ≤50 sessions missing title/repo (newest first), call `chat-source describe <id>` per session (timeout 8s each; abort enrichment after 3 consecutive failures → mark degraded), parse the `key: value` block, cache into sessions table (only refresh rows older than 7 days). NEVER call `list`. Test: stub chat-source script whose `describe` prints the real output shape (`=== <id> ===` header + `  provider:`/`  title:`/`  repo:` lines) and whose `list` writes a marker file — assert marker file absent after ingest (list never invoked) + titles cached.
2. Efficiency note: session_index seeding creates ~2.2k session rows — the scanner's foreign-id `references` matching must use an in-memory set of known ids (loaded once), never a per-line DB query.
