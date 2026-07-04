# Packet er087-p4a-dashboard-cli — collectors + CLI plumbing

Read the INVARIANTS block below + `docs/MISSION_CONTROL_PLAN.md` §Part B (serving model, cadence table, envelope) + §Hardening in your clone. `scripts/automation-status`, `scripts/chat-graph`, `dashboard/jobs.json`, `dashboard/fixtures/chats.json` all exist.

## Goal
Create `scripts/dashboard` (bash-3.2-safe wrapper + embedded python3 where JSON is built — NEVER string-concat JSON) + `scripts/dashboard.test.sh`.

## Build exactly
1. Subcommands: `collect [--due|--force] [feed]`, `refresh [feed]` (= collect --force), `status` (text table: feed, age, ok/error, freshness verdict; exit nonzero if any feed red/stale-beyond-6x or automation feed reports any red job), `open` (collect --due, then `open "$MISSION_CONTROL_HOME/index.html"`, print one freshness line per feed), `open --serve` (python3 -m http.server bound 127.0.0.1, random free port, serve state dir, print URL), `install` (copy `dashboard/index.html` → `$MISSION_CONTROL_HOME/index.html` when present; sed `__HOME__`/`__REPO__` into the launchd template → `~/Library/LaunchAgents/`, `launchctl bootstrap gui/$UID` guarded; chmod 700 state dir; idempotent), `demo` (build feeds from `dashboard/fixtures/*.json` into a mktemp state dir + open).
2. Four collectors per the plan cadence table; each: mkdir-lock, `timeout` (git 120s, chats 60s), write `data/<feed>.json` then `data/<feed>.js` (`window.MC = window.MC||{feeds:{}}; window.MC.feeds.<feed> = <json>;`) via tmp+`mv` both; `json.dumps(..., ensure_ascii=True)`. Envelope `{schema:1, feed, generated_at, generated_epoch, cadence_s, ok, error, data}`. Feeder commands come from env overrides (`DASHBOARD_CMD_USAGE` etc.) defaulting to the real tools (`usage-snapshot` history-tail-else `--no-ccusage`; `scan-unfinished-work --json`; `chat-graph export --json` reading the snapshot file; `automation-status --json`). A feeder failure/KeyError → envelope `ok:false, error:"..."` written, last-good `.json` NOT clobbered (write `<feed>.error.json` note instead) — feeds fail independently.
3. `--due` gating: per-feed cadence (300/900/1800/1800) vs existing `generated_epoch`.

## Acceptance = `bash scripts/dashboard.test.sh` exit 0 (all feeders stubbed via env; `MISSION_CONTROL_HOME=$(mktemp -d)`):
- `collect --force` writes 8 files atomically; every `.json` envelope-valid.
- `.js` transport == `.json` canonical: strip the JS wrapper, parse, deep-compare — including a hostile stub title (apostrophe + emoji + `</script>`).
- failing stub feeder → that feed `ok:false`, other three still written; prior good `.json` preserved.
- `--due` honors cadence (fresh feed skipped, stale re-collected).
- `status` exit 0 on all-green fixtures; nonzero when automation fixture contains a red job.
- `demo` builds from fixtures into mktemp and does NOT invoke `open` when `DASHBOARD_NO_OPEN=1` (add that guard for tests/CI).
- shell-contract section: when `dashboard/index.html` absent → prints SKIP lines cleanly; under `--require-shell` flag those cases are MANDATORY: file exists, three fenced section markers (`=== TOKENS ===`, `=== LAYOUT CSS ===`, `=== RENDERERS ===`), contains `window.MC`, ZERO `innerHTML` occurrences, no `http://`/`https://` resource loads, every `dashboard/fixtures/*.json` parses against the envelope.


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
