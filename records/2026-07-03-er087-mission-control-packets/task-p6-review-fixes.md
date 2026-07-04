# Packet er087-p6-review-fixes — three blocking findings from cross-model review (CONFIRMED)

Read `docs/MISSION_CONTROL_PLAN.md` in your clone. `scripts/chat-graph`, `scripts/automation-status`, `scripts/dashboard` + their `.test.sh` exist and are green — extend, do NOT regress. Each fix REQUIRES a new regression test that FAILS without the fix.

## BLOCKING 1 (critical — the core durability promise): manual unlink is bypassed by future collector rows
After the v2 migration made edge uniqueness `(src,dst,type,source)`, unlink's pre-inserted `source='manual'` suppressed sentinel no longer blocks a later collector inserting the SAME (src,dst,type) under a DIFFERENT source (e.g. delegations) as ACTIVE — the unlinked pair reappears. Suppression must be SOURCE-INDEPENDENT.
Fix (dedicated table, cleanest): add table `suppressions(src, dst, type, PRIMARY KEY(src,dst,type))`. `unlink` writes a row there (canonical pair order) in addition to journaling. `link` (and re-link of the same pair/type) DELETES the matching suppression row. Export AND `show` MUST exclude any edge whose (src,dst,type) is in `suppressions` (join/NOT EXISTS), regardless of source or status. Keep the existing per-row `status='suppressed'` behavior too (belt and suspenders) but the suppressions table is now the authority. `rebuild` replays the journal so suppressions survive DB loss. Bump SCHEMA_VERSION to 3 with a forward migration creating the table + backfilling from existing `status='suppressed'` manual rows.
REQUIRED test: link A B; unlink A B; ingest a fixture delegations/state.json that yields edge A->B under source='delegations'; ingest; assert `show A` and `export` do NOT show A->B (currently they WOULD). Also: re-link (`link A B`) then ingest → edge reappears.

## BLOCKING 2: installed ticker execs a path install never creates
`launchd/com.gillettes.mission-control.plist.template:16` runs `__HOME__/.mission-control/bin/dashboard`, but `do_install` (scripts/dashboard ~line 337) copies only index.html + plist — never `scripts/dashboard` → `~/.mission-control/bin/dashboard`. The job fails every 300s (file not found).
Fix: `do_install` creates `$MISSION_CONTROL_HOME/bin` + `$MISSION_CONTROL_HOME/logs`, copies the running `scripts/dashboard` to `$MISSION_CONTROL_HOME/bin/dashboard`, `chmod +x`. The copied dashboard must locate the repo (it needs REPO_ROOT): have install write the resolved `REPO_ROOT` into the copied copy (e.g. sed a `REPO_ROOT_DEFAULT=` line) OR the plist passes `REPO_ROOT` via EnvironmentVariables — pick one, make `collect --due` work from the installed copy. REQUIRED test: run `do_install` into `MISSION_CONTROL_HOME=$(mktemp -d)` (stub launchctl via PATH so bootstrap no-ops), assert `$MCH/bin/dashboard` exists, is executable, and `$MCH/bin/dashboard collect --force` (feeders stubbed) writes feeds.

## BLOCKING 3: pseudo job false-reds
`dashboard/jobs.json` marks `chat-graph-ingest` `"pseudo": true` (not a launchd label — it's the nightly refresh). `scripts/automation-status` never reads `pseudo`, so it checks launchctl-loaded, finds none, marks red forever.
Fix: when `entry.pseudo` is true, SKIP all launchctl loaded/exit checks; classify state from evidence freshness ONLY (green if evidence within expected_freshness_s, yellow if stale, never red-for-unloaded). REQUIRED test: pseudo job with fresh evidence file → green; with stale/missing evidence → yellow; NEVER red for being unloaded.

## NON-BLOCKING (fold in — cheap): schema guard ordering
Move the `meta.schema_version > code` future-version abort BEFORE any DDL/migration so a newer DB is never mutated by older code. Test: open a schema_version=99 DB, assert NO tables altered (row counts unchanged) + plain abort message + nonzero exit.

## Acceptance = all three suites green: `bash scripts/chat-graph.test.sh && bash scripts/automation-status.test.sh && bash scripts/dashboard.test.sh --require-shell` all exit 0, INCLUDING the four new regression tests above. Shared invariants as embedded below.
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
