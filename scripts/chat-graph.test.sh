#!/usr/bin/env bash
# chat-graph.test.sh — acceptance suite for scripts/chat-graph (ER-087 Part A core).
# bash-3.2 compatible; python3 stdlib only; mktemp fixtures only; no network; no real $HOME.
# One PASS:/FAIL: line per case; exit 0 only when all pass.
set -u
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "$0")" && pwd)"
CG="$HERE/chat-graph"
FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
ok()   { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (want=$1 got=$2)"; fi; }

# query graph.db with a python one-liner; prints the scalar result.
q() { python3 - "$1" <<'PY'
import sqlite3, sys, os
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db)
print(con.execute(sys.argv[1]).fetchone()[0])
PY
}

# fresh isolated environment for a case
new_env() {
  export CHAT_GRAPH_HOME="$(mktemp -d)"
  export CHAT_GRAPH_CROSS_AGENT_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_SESSION_INDEX="$(mktemp -d)/session_index.jsonl"
  # scanner roots + register MUST be mktemp — never the real ~/.claude corpus.
  export CHAT_GRAPH_CLAUDE_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_CODEX_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_CURSOR_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_HERMES_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_HERMES_STATE_DB="$(mktemp -d)/state.db"
  export CHAT_GRAPH_COPILOT_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_CODING_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_REPO_ROOTS="$(mktemp -d)"
  export CHAT_GRAPH_NIGHTLY_REPORT_GLOB="$(mktemp -d)/*.md"
  export CHAT_GRAPH_SCAN_CMD="/bin/echo []"
  export CHAT_GRAPH_GIT_FEED="$(mktemp -d)/git.json"
  export CHAT_GRAPH_REGISTER="$(mktemp -d)/register.md"; : > "$CHAT_GRAPH_REGISTER"
  # stub chat-source: 'present' checks pass; describe returns provider only (no
  # title) so untitled-fallback cases survive enrichment; list writes a marker so
  # the carry-over test can prove it is NEVER invoked.
  local stub="$(mktemp -d)/chat-source"
  cat > "$stub" <<SH
#!/usr/bin/env bash
case "\$1" in
  list) echo called > "$CHAT_GRAPH_HOME/LIST_CALLED" ;;
  describe) echo "provider: claude" ;;
  resolve) echo "\$2" ;;
esac
exit 0
SH
  chmod +x "$stub"
  export CHAT_GRAPH_CHAT_SOURCE="$stub"
  : > "$CHAT_GRAPH_SESSION_INDEX"
}

mk_delegation() { # dir gov worker verified
  local d="$CHAT_GRAPH_CROSS_AGENT_ROOT/delegations/$1"
  mkdir -p "$d"
  cat > "$d/state.json" <<JSON
{ "id":"$1", "to":"codex", "governor":{"id":"$2","provider":"claude"},
  "worker_child_id":"$3", "handshake":"hs-$1", "handshake_verified":"$4" }
JSON
}

mk_mailbox() { # to from
  local d="$CHAT_GRAPH_CROSS_AGENT_ROOT/mailbox/$1/inbox"
  mkdir -p "$d"
  cat > "$d/1-nonce.json" <<JSON
{ "schema":"cross-agent-mailbox/v1", "id":"1-nonce.json", "to":"$1",
  "from":"$2", "from_provider":"claude", "message":"hi" }
JSON
}

idx_add() { printf '{"id":"%s","thread_name":"%s"}\n' "$1" "$2" >> "$CHAT_GRAPH_SESSION_INDEX"; }

# --- 1. THE test: suppression survives re-ingest ---------------------------
new_env
"$CG" link SESSA SESSB --type related_manual >/dev/null
"$CG" unlink SESSA SESSB >/dev/null
"$CG" ingest >/dev/null
"$CG" ingest >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE type='related_manual' AND status='suppressed'")" \
   "suppression survives two re-ingests (THE test)"

# --- 2. discriminating: collector-derived edge cannot resurrect ------------
new_env
mk_delegation dlgA GOVA WORKB yes
"$CG" ingest >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE src='GOVA' AND dst='WORKB' AND type='spawned' AND status='active'")" \
   "delegations collector produced spawned edge"
"$CG" unlink GOVA WORKB --type spawned >/dev/null
"$CG" ingest >/dev/null
"$CG" ingest >/dev/null
ok suppressed "$(q "SELECT status FROM edges WHERE src='GOVA' AND dst='WORKB' AND type='spawned'")" \
   "unlinked collector edge stays suppressed after re-ingest"

# --- 3. journal rebuild: suppression survives total DB loss -----------------
new_env
"$CG" link RA RB --type related_manual >/dev/null
"$CG" unlink RA RB >/dev/null
rm -f "$CHAT_GRAPH_HOME/graph.db" "$CHAT_GRAPH_HOME/graph.db-wal" "$CHAT_GRAPH_HOME/graph.db-shm"
"$CG" rebuild >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE type='related_manual' AND status='suppressed'")" \
   "journal rebuild restores suppression after rm graph.db"

# --- 4. idempotency: identical row counts across two ingests ----------------
new_env
mk_delegation d1 G1 W1 yes
mk_mailbox T1 F1
idx_add A1 "Foo"
idx_add A2 "Audit: Foo"
"$CG" ingest >/dev/null
C1="$(q "SELECT COUNT(*) FROM edges")"
"$CG" ingest >/dev/null
C2="$(q "SELECT COUNT(*) FROM edges")"
ok "$C1" "$C2" "ingest is idempotent (edge count stable: $C1)"

# --- 5. delegations confidence: verified 1.0 vs unverified 0.8 --------------
new_env
mk_delegation dyes GYES WYES yes
mk_delegation dno  GNO  WNO  no
"$CG" ingest >/dev/null
ok 1.0 "$(q "SELECT confidence FROM edges WHERE src='GYES' AND dst='WYES'")" \
   "handshake_verified=yes -> confidence 1.0"
ok 0.8 "$(q "SELECT confidence FROM edges WHERE src='GNO' AND dst='WNO'")" \
   "handshake_verified=no -> confidence 0.8"

# --- 6. mailbox: signaled edge with from/to --------------------------------
new_env
mk_mailbox INBOXTO SENDERFROM
"$CG" ingest >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE src='SENDERFROM' AND dst='INBOXTO' AND type='signaled'")" \
   "mailbox collector produced signaled from->to edge"
mk_mailbox UNK unknown
"$CG" ingest >/dev/null
ok 0 "$(q "SELECT COUNT(*) FROM edges WHERE dst='UNK'")" \
   "mailbox skips from=unknown"

# --- 7. title drift: both Audit: and audit: forms match; ambiguous -> 0.5 ---
new_env
idx_add TGTFOO "Foo"
idx_add AUD_SP "Audit: Foo"
idx_add AUD_LC "audit:Foo"
idx_add DUP1 "Dup"
idx_add DUP2 "Dup"
idx_add AUD_DUP "Audit: Dup"
"$CG" ingest >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE src='AUD_SP' AND dst='TGTFOO' AND type='audits'")" \
   "spaced 'Audit: Foo' matches target"
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE src='AUD_LC' AND dst='TGTFOO' AND type='audits'")" \
   "lowercase 'audit:Foo' matches target"
ok 0.5 "$(q "SELECT confidence FROM edges WHERE src='AUD_DUP' AND type='audits'")" \
   "ambiguous duplicate-title audit -> confidence 0.5"
ok "ambiguous title" "$(q "SELECT note FROM edges WHERE src='AUD_DUP' AND type='audits'")" \
   "ambiguous audit carries note"

# --- 8. untitled session -> non-empty fallback title ------------------------
new_env
mk_delegation d8 G8 WORKER8NODE yes
"$CG" ingest >/dev/null
SHOW="$("$CG" show WORKER8NODE)"
if echo "$SHOW" | grep -q "(untitled)"; then pass "untitled session gets non-empty fallback title"
else fail "untitled session fallback title"; fi

# --- 9. concurrent ingest: locked -> exit 0 with skip notice ----------------
new_env
mkdir -p "$CHAT_GRAPH_HOME/ingest.lock"
OUT="$("$CG" ingest 2>&1)"; RC=$?
rmdir "$CHAT_GRAPH_HOME/ingest.lock"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qi "lock held"; then
  pass "second ingest while lock held exits 0 with skip notice"
else fail "concurrent ingest lock (rc=$RC out=$OUT)"; fi

# --- 9b. crashed ingest: stale lock is cleared instead of wedging forever ---
new_env
mkdir -p "$CHAT_GRAPH_HOME/ingest.lock"
python3 - "$CHAT_GRAPH_HOME/ingest.lock" <<'PY'
import os, sys, time
old = time.time() - 31 * 60
os.utime(sys.argv[1], (old, old))
PY
OUT="$("$CG" ingest 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qi "removed stale ingest lock" \
   && [ ! -d "$CHAT_GRAPH_HOME/ingest.lock" ]; then
  pass "stale ingest lock is cleared and ingest continues"
else fail "stale ingest lock recovery failed (rc=$RC out=$OUT)"; fi

# --- 9c. an old lock whose exact process identity is live is never stolen ---
new_env
mkdir -p "$CHAT_GRAPH_HOME/ingest.lock"
python3 - "$CHAT_GRAPH_HOME/ingest.lock" "$$" <<'PY'
import json, os, subprocess, sys, time
lock, pid = sys.argv[1], int(sys.argv[2])
p = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)],
                   capture_output=True, text=True, timeout=2)
start = p.stdout.strip()
assert p.returncode == 0 and start
json.dump({"pid": pid, "token": "live-old-test", "start": start},
          open(os.path.join(lock, "owner.json"), "w"))
old = time.time() - 31 * 60
os.utime(lock, (old, old))
PY
OUT="$("$CG" ingest 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qi "lock held" && \
   [ -f "$CHAT_GRAPH_HOME/ingest.lock/owner.json" ]; then
  pass "old ingest lock with exact live process start is not stolen"
else fail "old live ingest lock was stolen (rc=$RC out=$OUT)"; fi
rm -f "$CHAT_GRAPH_HOME/ingest.lock/owner.json" 2>/dev/null || true
rmdir "$CHAT_GRAPH_HOME/ingest.lock" 2>/dev/null || true

# --- 9d. a reused live PID with the wrong process start is stale ------------
new_env
mkdir -p "$CHAT_GRAPH_HOME/ingest.lock"
python3 - "$CHAT_GRAPH_HOME/ingest.lock" "$$" <<'PY'
import json, os, sys, time
lock, pid = sys.argv[1], int(sys.argv[2])
json.dump({"pid": pid, "token": "reused-pid-test", "start": "not-this-process"},
          open(os.path.join(lock, "owner.json"), "w"))
old = time.time() - 31 * 60
os.utime(lock, (old, old))
PY
OUT="$("$CG" ingest 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qi "removed stale ingest lock" && \
   [ ! -d "$CHAT_GRAPH_HOME/ingest.lock" ]; then
  pass "stale lock with reused PID and mismatched start is reclaimed"
else fail "PID-reuse fencing failed (rc=$RC out=$OUT)"; fi

# --- 10. migration guard: schema_version=99 -> plain abort, nonzero exit ----
new_env
"$CG" ingest >/dev/null
python3 - <<'PY'
import sqlite3, os
con = sqlite3.connect(os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db"))
con.execute("INSERT OR REPLACE INTO meta VALUES('schema_version','99')")
con.commit()
PY
OUT="$("$CG" stats 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && echo "$OUT" | grep -qi "newer"; then
  pass "schema_version=99 aborts with plain message, nonzero exit"
else fail "migration guard (rc=$RC out=$OUT)"; fi

# --- 10b. future-version guard fires BEFORE any DDL/migration (no mutation) --
# a newer-than-code DB must be aborted UNTOUCHED. Regression: old code ran the
# executescript (which implicit-commits) + the v1->v2 rebuild BEFORE the guard,
# orphaning edges into edges_v1 and losing rows on a DB it does not understand.
new_env
python3 - <<'PY'
import sqlite3, os
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db)
con.executescript("""
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  CREATE TABLE edges(src TEXT, dst TEXT, type TEXT, source TEXT,
    confidence REAL, evidence TEXT, note TEXT, status TEXT DEFAULT 'active',
    UNIQUE(src, dst, type));
""")
con.execute("INSERT INTO meta VALUES('schema_version','99')")
con.execute("INSERT INTO edges VALUES('A','B','spawned','x',1.0,'{}',NULL,'active')")
con.commit(); con.close()
PY
OUT="$("$CG" stats 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && echo "$OUT" | grep -qi "newer"; then
  pass "future-version guard: plain abort, nonzero exit"
else fail "future-version guard abort (rc=$RC out=$OUT)"; fi
ok 1 "$(q "SELECT COUNT(*) FROM edges")" \
   "future-version guard leaves edges untouched (row count unchanged)"
ok 0 "$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='edges_v1'")" \
   "future-version guard did NOT begin the v1->v2 rebuild (no edges_v1 orphan)"

# --- 11. doctor: healthy -> 0; missing journal dir -> 1 ---------------------
new_env
"$CG" link DA DB --type related_manual >/dev/null   # creates journal dir
"$CG" ingest >/dev/null
"$CG" doctor >/dev/null; RC=$?
ok 0 "$RC" "doctor on healthy home exits 0"
rm -rf "$CHAT_GRAPH_HOME/journal"
"$CG" doctor >/dev/null; RC=$?
ok 1 "$RC" "doctor with missing journal dir exits 1"

# --- 11a. full-ingest health uses the nightly SLA, not catch-up cadence -------
new_env
"$CG" link DA DB --type related_manual >/dev/null
"$CG" ingest >/dev/null
python3 - "$CHAT_GRAPH_HOME/last-ingest" <<'PYEOF'
import os, sys, time
stamp = time.time() - 3 * 3600
os.utime(sys.argv[1], (stamp, stamp))
PYEOF
"$CG" doctor >/dev/null; RC=$?
ok 0 "$RC" "doctor accepts a 3h-old full ingest inside the 30h nightly SLA"
if "$CG" show DA 2>&1 | grep -q "warning: last ingest"; then
  fail "show warns for a healthy 3h-old nightly full ingest"
else
  pass "show accepts a 3h-old full ingest inside the 30h nightly SLA"
fi
python3 - "$CHAT_GRAPH_HOME/last-ingest" <<'PYEOF'
import os, sys, time
stamp = time.time() - 31 * 3600
os.utime(sys.argv[1], (stamp, stamp))
PYEOF
"$CG" doctor >/dev/null; RC=$?
ok 1 "$RC" "doctor rejects a 31h-old full ingest outside the 30h nightly SLA"
"$CG" show DA 2>&1 | grep -q "warning: last ingest" \
  && pass "show warns for a genuinely stale 31h-old full ingest" \
  || fail "show omits warning for a stale 31h-old full ingest"
python3 - "$CHAT_GRAPH_HOME/last-ingest" <<'PYEOF'
import os, sys, time
stamp = time.time() + 3600
os.utime(sys.argv[1], (stamp, stamp))
PYEOF
"$CG" doctor >/dev/null; RC=$?
ok 1 "$RC" "doctor rejects a future-dated full-ingest marker"
"$CG" show DA 2>&1 | grep -q "warning: full-ingest marker is future-dated" \
  && pass "show warns for a future-dated full-ingest marker" \
  || fail "show omits warning for a future-dated full-ingest marker"
rm -f "$CHAT_GRAPH_HOME/last-ingest"
"$CG" doctor >/dev/null; RC=$?
ok 1 "$RC" "doctor rejects a missing full-ingest marker"

# --- 11b. FIX 7: transient scan-errors WARN (exit 0); large count FAILs ------
new_env
"$CG" link DA DB --type related_manual >/dev/null   # journal dir + healthy home
"$CG" ingest >/dev/null
mkdir -p "$CHAT_GRAPH_HOME/logs"
printf '/tmp/x.jsonl:3: json decode error\n' > "$CHAT_GRAPH_HOME/logs/scan-errors.log"
"$CG" doctor >/dev/null 2>&1; RC=$?
ok 0 "$RC" "doctor with 1 transient scan-error WARNs, does not FAIL (exit 0)"
"$CG" doctor 2>&1 | grep -qi "WARN.*scan-error" && pass "doctor prints WARN for the scan-error" || fail "no WARN line for scan-error"
: > "$CHAT_GRAPH_HOME/logs/scan-errors.log"; for i in $(seq 1 25); do printf 'f%d:1: err\n' "$i" >> "$CHAT_GRAPH_HOME/logs/scan-errors.log"; done
"$CG" doctor >/dev/null 2>&1; RC=$?
ok 1 "$RC" "doctor with a LARGE scan-error count (>20) FAILs (exit 1)"

# --- 12. security: secret in title is redacted at display time --------------
new_env
SECRET="sk-$(printf 'a%.0s' $(seq 1 24))"
idx_add SECRETID "leak $SECRET here"
"$CG" ingest >/dev/null
SHOW="$("$CG" show SECRETID)"
if echo "$SHOW" | grep -q "REDACTED-SECRET" && ! echo "$SHOW" | grep -q "$SECRET"; then
  pass "secret in title redacted in show output"
else fail "redaction (show=$SHOW)"; fi

# helpers: write a claude transcript file (session id = filename) from a python
# heredoc so JSON text (emoji, apostrophes, embedded JSON) stays exact.
cl_root() { echo "$CHAT_GRAPH_CLAUDE_ROOT/proj"; }
# usage: user_line '<text>'  -> one claude user-message JSONL line, given uuid
umsg() { python3 - "$1" "$2" <<'PY'
import json, sys
print(json.dumps({"type":"user","uuid":sys.argv[2],
                  "message":{"role":"user","content":[{"type":"text","text":sys.argv[1]}]}}))
PY
}

# --- 13. scanner: Spawned-by header -> spawned 1.0 edge --------------------
new_env
mkdir -p "$(cl_root)"
umsg "hello Spawned-by: parent_provider=claude parent_id=PARENT13 handshake=hs13" u13 \
  > "$(cl_root)/CHILD13.jsonl"
"$CG" ingest >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE src='PARENT13' AND dst='CHILD13' AND type='spawned' AND source='spawn_header'")" \
   "Spawned-by header -> spawned parent->child edge"
ok 1.0 "$(q "SELECT confidence FROM edges WHERE src='PARENT13' AND dst='CHILD13' AND type='spawned'")" \
   "Spawned-by edge confidence 1.0"

# --- 14. role filter: register code in tool_result -> ZERO topics ----------
new_env
mkdir -p "$(cl_root)"
python3 - <<'PY' > "$CHAT_GRAPH_CLAUDE_ROOT/proj/NOISE14.jsonl"
import json
# a user turn whose ONLY content is a tool_result carrying an ER code
print(json.dumps({"type":"user","uuid":"u14","message":{"role":"user","content":[
  {"type":"tool_result","content":"see ER-099 in the hook output"}]}}))
PY
"$CG" ingest >/dev/null 2>&1
ok 0 "$(q "SELECT COUNT(*) FROM session_topics WHERE session_id='NOISE14'")" \
   "register code inside tool_result yields ZERO topics (role filter)"

# --- 15. resume-fork: shared first uuid -> continues + open_ends deduped ----
new_env
mkdir -p "$(cl_root)"
CO="Session Closeout Handoff: finish the migration and verify"
umsg "$CO" SHARED15 > "$(cl_root)/FORKA15.jsonl"
umsg "$CO" SHARED15 > "$(cl_root)/FORKB15.jsonl"
touch -t 202601010000 "$(cl_root)/FORKA15.jsonl"   # A older
touch -t 202606010000 "$(cl_root)/FORKB15.jsonl"   # B newer
"$CG" ingest >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE type='continues' AND source='resume-fork' AND src='FORKB15' AND dst='FORKA15'")" \
   "resume-fork: newer->older continues 1.0 edge"
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE resolved_at IS NULL AND kind='closeout_handoff'")" \
   "resume-fork dedupes identical open_ends across the pair (1 unresolved)"

# --- 16. garbage: truncated JSON line -> logged, other lines ingested -------
new_env
mkdir -p "$(cl_root)"
{ umsg "topic ER-055 here" g1;
  echo '{"type":"user","uuid":"gBAD","message": Spawned-truncated';   # bad + prefilter hit
  umsg "second good line ER-055" g2; } > "$(cl_root)/GARB16.jsonl"
"$CG" ingest >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM session_topics WHERE session_id='GARB16' AND code='ER-055'")" \
   "garbage file: good lines still ingested (topic present)"
if [ -s "$CHAT_GRAPH_HOME/logs/scan-errors.log" ]; then pass "garbage file: json error logged"
else fail "garbage file: scan-errors.log empty"; fi

# --- 17. cursor: rescan with nothing changed -> '0 new/changed files' -------
new_env
mkdir -p "$(cl_root)"
umsg "plain hello no signals" u17 > "$(cl_root)/SESS17.jsonl"
"$CG" ingest >/dev/null 2>&1
OUT="$("$CG" ingest 2>&1)"
if echo "$OUT" | grep -q "0 new/changed files"; then pass "unchanged rescan reports 0 new/changed files"
else fail "cursor skip (out=$OUT)"; fi

# --- 18. --limit-files 2 on 5 files -> exactly 2 scanned, cursors written ----
new_env
mkdir -p "$(cl_root)"
for n in 1 2 3 4 5; do umsg "file $n hello" "u18$n" > "$(cl_root)/S18$n.jsonl"; done
"$CG" ingest --limit-files 2 >/dev/null 2>&1
ok 2 "$(q "SELECT COUNT(*) FROM file_cursors")" "--limit-files 2 writes exactly 2 cursors"
"$CG" ingest --limit-files 2 >/dev/null 2>&1
ok 4 "$(q "SELECT COUNT(*) FROM file_cursors")" "successive bounded ingest advances to the next files"
"$CG" ingest --limit-files 2 >/dev/null 2>&1
ok 5 "$(q "SELECT COUNT(*) FROM file_cursors")" "bounded ingest eventually covers the full source set"
if [ ! -f "$CHAT_GRAPH_HOME/last-ingest" ]; then pass "--limit-files writes NO completion marker"
else fail "--limit-files wrote a completion marker"; fi

# --- 19. carry-over: describe enriches title, list NEVER invoked ------------
new_env
# richer stub: describe prints the real `=== id ===` + indented block shape and
# a title; list writes a marker so we can prove it is never called.
STUB19="$(mktemp -d)/chat-source"
cat > "$STUB19" <<SH
#!/usr/bin/env bash
case "\$1" in
  list) echo called > "$CHAT_GRAPH_HOME/LIST_CALLED" ;;
  describe) echo "=== \$2 ==="; echo "  provider: codex"; echo "  title: Enriched Title"; echo "  repo: myrepo" ;;
  resolve) echo "\$2" ;;
esac
exit 0
SH
chmod +x "$STUB19"; export CHAT_GRAPH_CHAT_SOURCE="$STUB19"
# real-shaped ids so enrichment applies (FIX 4 skips synthetic ids); one synthetic
# 'agent-*' worker to prove it is NOT re-described / does not degrade every run.
mk_delegation d19 aaaaaaaa-1111-2222-3333-444444444444 bbbbbbbb-5555-6666-7777-888888888888 yes
mk_delegation d19b cccccccc-9999-0000-1111-222222222222 agent-synthetic-xyz yes
"$CG" ingest >/dev/null 2>&1
if [ ! -f "$CHAT_GRAPH_HOME/LIST_CALLED" ]; then pass "ingest never invokes chat-source list"
else fail "chat-source list was invoked"; fi
ok "Enriched Title" "$(q "SELECT title FROM sessions WHERE id='bbbbbbbb-5555-6666-7777-888888888888'")" \
   "describe enrichment cached title onto real-shaped worker session"
# FIX 4: synthetic id skipped (enriched_at stamped, no title fetched), so a 2nd
# ingest does NOT keep retrying it and does NOT report chat-source degraded.
D19OUT="$("$CG" ingest 2>&1)"
if printf '%s' "$D19OUT" | grep -qi "degraded.*chat-source"; then
  fail "synthetic 'agent-*' id still trips chat-source degraded on re-ingest"
else pass "synthetic id skipped — no chat-source degraded on steady-state ingest"; fi
ok "1" "$(q "SELECT CASE WHEN enriched_at IS NOT NULL THEN 1 ELSE 0 END FROM sessions WHERE id='agent-synthetic-xyz'")" \
   "synthetic id stamped enriched (leaves the retry pool)"

# --- 20. closeout open-end created, then auto-resolved when block removed ----
new_env
mkdir -p "$(cl_root)"
umsg "Session Closeout Handoff: wire the collector into the dashboard next" u20 \
  > "$(cl_root)/CLOSE20.jsonl"
"$CG" ingest >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='CLOSE20' AND kind='closeout_handoff' AND resolved_at IS NULL")" \
   "closeout Handoff -> open_end created"
umsg "just a normal follow-up message now" u20b > "$(cl_root)/CLOSE20.jsonl"
"$CG" ingest --full >/dev/null 2>&1
ok 0 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='CLOSE20' AND resolved_at IS NULL")" \
   "open_end auto-resolved when closeout block disappears on later pass"

# --- 21. export -> validate-export round-trip green + atomic (no tmp left) ---
new_env
mkdir -p "$(cl_root)"
export CHAT_GRAPH_SCAN_CMD="/bin/echo []"   # hermetic repo_annotations stub
umsg "hello Spawned-by: parent_provider=claude parent_id=PARENT21 handshake=hs21" u21 \
  > "$(cl_root)/CHILD21.jsonl"
idx_add TITLED21 "My Chat Title"
"$CG" ingest >/dev/null 2>&1
"$CG" export --json >/dev/null 2>&1
EXP="$CHAT_GRAPH_HOME/export/graph.json"
if [ -f "$EXP" ]; then pass "export wrote graph.json"; else fail "export missing graph.json"; fi
if ls "$CHAT_GRAPH_HOME/export/"*.tmp.* >/dev/null 2>&1; then fail "export left a .tmp file (not atomic)"
else pass "export left no .tmp file (atomic rename)"; fi
"$CG" validate-export "$EXP" >/dev/null 2>&1; RC=$?
ok 0 "$RC" "validate-export accepts the exported snapshot"
# a broken envelope must fail validation
echo '{"schema":2,"data":{}}' > "$CHAT_GRAPH_HOME/bad.json"
"$CG" validate-export "$CHAT_GRAPH_HOME/bad.json" >/dev/null 2>&1; RC=$?
ok 1 "$RC" "validate-export rejects a malformed export"

# --- 22. hostile title (apostrophe + emoji) survives export round-trip -------
new_env
export CHAT_GRAPH_SCAN_CMD="/bin/echo []"
idx_add HOSTILE22 "O'Brien 🚀 </script> chat"
"$CG" ingest >/dev/null 2>&1
"$CG" export --json >/dev/null 2>&1
TITLE_OK=$(python3 - "$CHAT_GRAPH_HOME/export/graph.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))              # must parse
t = {n["id"]: n["title"] for n in d["data"]["nodes"]}
print("yes" if "O'Brien" in t.get("HOSTILE22","") and "🚀" in t.get("HOSTILE22","") else "no")
PY
)
ok yes "$TITLE_OK" "hostile title parses back intact (apostrophe + emoji)"

# --- 23. title match tiers: normalized 0.7 / prefix 0.6 / ambiguous prefix 0.5 -
# NOTE: packet rule says prefix "min 8 chars" but its own fixture uses 'Foo Bar'
# (7 chars); resolved by measuring the CANDIDATE TITLE length (>=8), which the
# grammar supports and all fixture titles satisfy. See claims list.
new_env   # normalized: 'Foo Bar - Chronicle' drift matches 'Audit: Foo Bar'
idx_add TGT23N "Foo Bar - Chronicle"
idx_add AUD23N "Audit: Foo Bar"
"$CG" ingest >/dev/null 2>&1
ok 0.7 "$(q "SELECT confidence FROM edges WHERE src='AUD23N' AND dst='TGT23N' AND type='audits'")" \
   "normalized title match -> confidence 0.7"
ok normalized "$(q "SELECT note FROM edges WHERE src='AUD23N' AND dst='TGT23N' AND type='audits'")" \
   "normalized title match carries note='normalized'"

new_env   # prefix: audited-name is a prefix of the only candidate title
idx_add TGT23P "Foo Bar Extended Adventures"
idx_add AUD23P "Audit: Foo Bar"
"$CG" ingest >/dev/null 2>&1
ok 0.6 "$(q "SELECT confidence FROM edges WHERE src='AUD23P' AND dst='TGT23P' AND type='audits'")" \
   "unique prefix title match -> confidence 0.6"
ok prefix "$(q "SELECT note FROM edges WHERE src='AUD23P' AND dst='TGT23P' AND type='audits'")" \
   "unique prefix title match carries note='prefix'"

new_env   # two prefix candidates -> most-recent 0.5 ambiguous
idx_add PFX1 "Foo Bar Extended Adventures"
idx_add PFX2 "Foo Bar Longer Journey"
idx_add AUD23A "Audit: Foo Bar"
"$CG" ingest >/dev/null 2>&1
ok 0.5 "$(q "SELECT confidence FROM edges WHERE src='AUD23A' AND type='audits'")" \
   "two prefix candidates -> confidence 0.5"
ok "ambiguous title" "$(q "SELECT note FROM edges WHERE src='AUD23A' AND type='audits'")" \
   "two prefix candidates carry note='ambiguous title'"

# --- 24. edge uniqueness includes source: two sources coexist, no cross-overwrite
new_env
mkdir -p "$(cl_root)"
mk_delegation d24 PARENT24 CHILD24 no    # delegations spawned PARENT24->CHILD24 @ 0.8
umsg "hi Spawned-by: parent_provider=claude parent_id=PARENT24 handshake=hs24" u24 \
  > "$(cl_root)/CHILD24.jsonl"           # spawn_header spawned PARENT24->CHILD24 @ 1.0
"$CG" ingest >/dev/null 2>&1
ok 2 "$(q "SELECT COUNT(*) FROM edges WHERE src='PARENT24' AND dst='CHILD24' AND type='spawned'")" \
   "same (src,dst,type) from two sources persists TWO rows"
ok 0.8 "$(q "SELECT confidence FROM edges WHERE src='PARENT24' AND dst='CHILD24' AND type='spawned' AND source='delegations'")" \
   "delegations row keeps its own confidence 0.8"
ok 1.0 "$(q "SELECT confidence FROM edges WHERE src='PARENT24' AND dst='CHILD24' AND type='spawned' AND source='spawn_header'")" \
   "spawn_header row keeps its own confidence 1.0"
"$CG" ingest --full >/dev/null 2>&1     # re-ingest must not cross-overwrite
ok 2 "$(q "SELECT COUNT(*) FROM edges WHERE src='PARENT24' AND dst='CHILD24' AND type='spawned'")" \
   "re-ingest keeps both rows (no cross-overwrite)"
ok 0.8 "$(q "SELECT confidence FROM edges WHERE src='PARENT24' AND dst='CHILD24' AND type='spawned' AND source='delegations'")" \
   "re-ingest: weak delegations confidence not clobbered by strong spawn_header"

# --- 25. v1 -> v2 migration: rows preserved, suppression intact, version bumped -
new_env
python3 - <<'PY'
import sqlite3, os
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db)
con.executescript("""
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  CREATE TABLE edges(src TEXT, dst TEXT, type TEXT, source TEXT,
    confidence REAL, evidence TEXT, note TEXT, status TEXT DEFAULT 'active',
    UNIQUE(src, dst, type));
""")
con.execute("INSERT INTO meta VALUES('schema_version','1')")
con.execute("INSERT INTO edges VALUES('A','B','spawned','delegations',1.0,'{}',NULL,'active')")
con.execute("INSERT INTO edges VALUES('C','D','audits','titles',0.5,'{}','x','suppressed')")
con.commit(); con.close()
PY
"$CG" stats >/dev/null 2>&1              # any DB open triggers _migrate
ok 7 "$(q "SELECT value FROM meta WHERE key='schema_version'")" \
   "v1 DB open migrates meta.schema_version to 7"
ok 2 "$(q "SELECT COUNT(*) FROM edges")" \
   "migration preserves all rows"
ok suppressed "$(q "SELECT status FROM edges WHERE src='C' AND dst='D' AND type='audits'")" \
   "migration preserves suppressed status"
# prove the new key gained source: same (src,dst,type) + new source coexists
python3 - <<'PY'
import sqlite3, os
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db)
con.execute("INSERT INTO edges VALUES('A','B','spawned','spawn_header',0.9,'{}',NULL,'active')")
con.commit(); con.close()
PY
ok 2 "$(q "SELECT COUNT(*) FROM edges WHERE src='A' AND dst='B' AND type='spawned'")" \
   "post-migration UNIQUE key includes source (two sources coexist)"

# --- 26. BLOCKING: suppression is SOURCE-INDEPENDENT (collector cannot bypass) -
# post-v2 the edge UNIQUE key is (src,dst,type,source), so a manual suppressed
# sentinel could NOT block a later collector inserting the same (src,dst,type)
# under a DIFFERENT source. The suppressions table is now the authority.
new_env
export CHAT_GRAPH_SCAN_CMD="/bin/echo []"   # hermetic repo_annotations stub
edge_in_export() { python3 - "$CHAT_GRAPH_HOME/export/graph.json" "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
a, b = sys.argv[2], sys.argv[3]
print(sum(1 for e in d["data"]["edges"]
          if e["src"].endswith(":" + a) and e["dst"].endswith(":" + b) and e["type"] == "spawned"))
PY
}
"$CG" link SUPA SUPB --type spawned >/dev/null   # manual edge of the type the collector emits
"$CG" unlink SUPA SUPB >/dev/null                # no --type: discovers 'spawned', suppresses it
mk_delegation dsup SUPA SUPB yes                 # collector emits SUPA->SUPB spawned @ source=delegations
"$CG" ingest >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE src='SUPA' AND dst='SUPB' AND type='spawned' AND source='delegations' AND status='active'")" \
   "collector inserts an ACTIVE row under a different source (the source-independence hole)"
"$CG" export --json >/dev/null 2>&1
ok 0 "$(edge_in_export SUPA SUPB)" \
   "export EXCLUDES the unlinked pair despite an active delegations row"
SHOW="$("$CG" show SUPA)"
if echo "$SHOW" | grep -q "SUPB"; then fail "show still lists the suppressed neighbor SUPB"
else pass "show EXCLUDES the suppressed neighbor"; fi
"$CG" link SUPA SUPB --type spawned >/dev/null   # re-link clears the suppression
"$CG" ingest >/dev/null
"$CG" export --json >/dev/null 2>&1
ok 1 "$(edge_in_export SUPA SUPB)" \
   "re-link clears suppression -> edge reappears in export"

# --- 24. partial-id resolution: prefix unlink canonicalizes to the full id ---
# link/unlink/resolve accept a unique prefix and MUST resolve it to the stored
# canonical id before any journal/db write, else a typed prefix suppresses the
# wrong (non-existent) key and the real edge stays visible.
new_env
export CHAT_GRAPH_SCAN_CMD="/bin/echo []"
FULLDST="aaaaaaaa-1111-2222-3333-444444444444"
mk_delegation dlgP SRCP "$FULLDST" yes            # spawned edge SRCP -> FULLDST
"$CG" ingest >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM edges WHERE src='SRCP' AND dst='$FULLDST' AND type='spawned' AND status='active'")" \
   "fixture: full-id spawned edge ingested"
"$CG" unlink SRCP aaaaaaaa --type spawned >/dev/null 2>&1   # PREFIX for dst
ok "$FULLDST" "$(q "SELECT dst FROM suppressions WHERE src='SRCP' AND type='spawned'")" \
   "prefix unlink stores the FULL canonical dst in suppressions"
SHOWP="$("$CG" show SRCP)"
if echo "$SHOWP" | grep -q "aaaaaaaa"; then fail "show still lists the prefix-unlinked neighbor"
else pass "show EXCLUDES the prefix-unlinked edge"; fi
"$CG" export --json >/dev/null 2>&1
ok 0 "$(edge_in_export SRCP "$FULLDST")" \
   "export EXCLUDES the prefix-unlinked edge (suppression keyed on full id)"
"$CG" link SRCP aaaaaaaa --type spawned >/dev/null 2>&1   # PREFIX re-link (pins link path)
ok "$FULLDST" "$(q "SELECT dst FROM edges WHERE src='SRCP' AND type='spawned' AND source='manual'")" \
   "prefix link canonicalizes dst to the full id"

# --- 25. ambiguous prefix -> unlink errors, exit nonzero, writes nothing -----
new_env
mk_delegation dlgB1 SRCB "bbbbbbbb-1111-1111-1111-111111111111" yes
mk_delegation dlgB2 SRCB "bbbbbbbb-2222-2222-2222-222222222222" yes
"$CG" ingest >/dev/null
"$CG" unlink SRCB bbbbbbbb --type spawned >/dev/null 2>&1; RCB=$?
if [ "$RCB" -ne 0 ]; then pass "ambiguous prefix unlink exits nonzero"
else fail "ambiguous prefix unlink should exit nonzero (got rc=$RCB)"; fi
ok 0 "$(q "SELECT COUNT(*) FROM suppressions")" \
   "ambiguous prefix unlink writes NO suppression"

# --- 26. unknown id -> literal kept + warning, no crash ---------------------
new_env
ERRX="$("$CG" unlink SRCX cccccccc --type spawned 2>&1 >/dev/null)"; RCX=$?
if [ "$RCX" -eq 0 ]; then pass "unknown-id unlink does not crash"
else fail "unknown-id unlink crashed (rc=$RCX)"; fi
case "$ERRX" in
  *"not found in graph; using as-is"*) pass "unknown id prints using-as-is warning" ;;
  *) fail "unknown id missing warning (err=$ERRX)" ;;
esac
ok 1 "$(q "SELECT COUNT(*) FROM suppressions WHERE dst='cccccccc'")" \
   "unknown id kept literal in suppression"

# --- 27. cold export --catchup-limit 2 -> bounded catch-up, valid snapshot --
# On a cold home export must trigger a catch-up ingest AND still reach its atomic
# rename within budget. --catchup-limit 2 bounds the scan to 2 of 5 files.
new_env
mkdir -p "$(cl_root)"
for n in 1 2 3 4 5; do umsg "cold file $n hello" "u27$n" > "$(cl_root)/S27$n.jsonl"; done
EXP27="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" export --json --catchup-limit 2 >/dev/null 2>&1
if [ -f "$EXP27" ]; then pass "cold export --catchup-limit reaches rename (snapshot written)"
else fail "cold export --catchup-limit wrote no snapshot"; fi
"$CG" validate-export "$EXP27" >/dev/null 2>&1; ok 0 "$?" "cold bounded export snapshot validates"
ok 2 "$(q "SELECT COUNT(*) FROM file_cursors")" "catch-up bounded to 2 of 5 files (not full scan)"
if [ ! -f "$CHAT_GRAPH_HOME/last-ingest" ]; then pass "bounded catch-up writes NO completion marker"
else fail "bounded catch-up wrote a completion marker"; fi
if python3 - "$EXP27" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
c = d["data"]["counts"]
assert "last_full_ingest_epoch" in c
assert "last_full_ingest_age_s" in c
assert c["last_full_ingest_epoch"] is None
assert c["last_full_ingest_age_s"] is None
assert c["full_ingest_sla_s"] == 30 * 3600, c
assert c["full_ingest_state"] == "unknown", c
assert c["full_ingest_stale"] is True, c
PYEOF
then pass "bounded export surfaces missing full-ingest marker in counts"
else fail "bounded export missing full-ingest freshness counts"; fi

# --- 28. lock-held catch-up export stays honest via ingest_skipped ----------
new_env
mkdir -p "$CHAT_GRAPH_HOME/ingest.lock"
EXP28="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
if python3 - "$EXP28" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["data"]["counts"].get("ingest_skipped") is True
PYEOF
then pass "export marks ingest_skipped=true when catch-up lock is held"
else fail "export missing ingest_skipped=true while catch-up lock held"; fi
rmdir "$CHAT_GRAPH_HOME/ingest.lock" 2>/dev/null || true

# --- 29. loose-ends: todo.md source inserts, exports, and auto-resolves ----
new_env
R29="$CHAT_GRAPH_HOME/repo-alpha"; mkdir -p "$R29"
export CHAT_GRAPH_REPO_ROOTS="$R29"
cat > "$R29/todo.md" <<'MD'
## Active Work
- [ ] Wire the usage routing pointer into the dashboard
MD
"$CG" ingest --collector todo_open >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='todo_open' AND resolved_at IS NULL")" \
   "todo_open collector inserts unchecked repo todo item"
HASH29="$(q "SELECT text_hash FROM open_ends WHERE kind='todo_open' AND resolved_at IS NULL LIMIT 1")"
"$CG" resolve "repo:repo-alpha" "$HASH29" >/dev/null
ok 0 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='todo_open' AND resolved_at IS NULL")" \
   "manual resolve hides a source-backed todo_open item once"
"$CG" ingest --collector todo_open >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='todo_open' AND resolved_at IS NULL")" \
   "todo_open reappears after refresh when the source is still open"
EXP29="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
if python3 - "$EXP29" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
items = d["data"]["loose_ends"]
assert any(x["kind"] == "todo_open" and x["source_node"] == "repo:repo-alpha" for x in items)
assert all("action_hint" in x and "resolve_cmd" in x for x in items)
PYEOF
then pass "export includes flat loose_ends from todo_open"
else fail "export missing todo_open loose_ends shape"; fi
cat > "$R29/todo.md" <<'MD'
## Active Work
- [x] Wire the usage routing pointer into the dashboard
MD
"$CG" ingest --collector todo_open >/dev/null
ok 0 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='todo_open' AND resolved_at IS NULL")" \
   "todo_open auto-resolves after the todo item is checked off"

# --- 30. loose-ends: repo_dirty accepts scanner rc=1 and resolves clean -----
new_env
SCAN30="$(mktemp -d)/scan"
cat > "$SCAN30" <<'SH'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"repo":"repo-beta","dirty":true,"dirty_files":2,"ahead":1,
   "detached":false,"branches":[{"name":"old-work","age_days":12}]}
]
JSON
exit 1
SH
chmod +x "$SCAN30"
export CHAT_GRAPH_SCAN_CMD="$SCAN30"
"$CG" ingest --collector repo_dirty >/dev/null
ok 3 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='repo_dirty' AND resolved_at IS NULL")" \
   "repo_dirty collector accepts scan-unfinished-work rc=1 findings"
cat > "$SCAN30" <<'SH'
#!/usr/bin/env bash
echo '[]'
exit 0
SH
"$CG" ingest --collector repo_dirty >/dev/null
ok 0 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='repo_dirty' AND resolved_at IS NULL")" \
   "repo_dirty auto-resolves when scanner returns clean"

# --- 30a. fresh dashboard Git feed replaces the duplicate portfolio scan ---
new_env
SCAN30A="$(mktemp -d)/scan"
SCAN30A_MARKER="$CHAT_GRAPH_HOME/scanner-called"
export SCAN30A_MARKER
cat > "$SCAN30A" <<'SH'
#!/usr/bin/env bash
: > "$SCAN30A_MARKER"
echo '[]'
SH
chmod +x "$SCAN30A"
export CHAT_GRAPH_SCAN_CMD="$SCAN30A"
python3 - "$CHAT_GRAPH_GIT_FEED" <<'PYEOF'
import json, sys, time
now = int(time.time())
json.dump({
    "schema": 1, "feed": "git", "generated_epoch": now,
    "cadence_s": 900, "ok": True, "error": None,
    "data": {"repos": [{"repo": "cached-repo", "dirty": True,
                           "dirty_files": 2, "ahead": 0, "detached": False,
                           "branches": []}]},
}, open(sys.argv[1], "w"))
PYEOF
"$CG" ingest --collector repo_dirty >/dev/null
if [ ! -e "$SCAN30A_MARKER" ] && \
   [ "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='repo_dirty' AND resolved_at IS NULL")" = 1 ]; then
  pass "fresh dashboard Git feed avoids a duplicate portfolio scan"
else
  fail "fresh dashboard Git feed was ignored or repo annotations were missing"
fi

# --- 30b. malformed cached envelope falls back to the canonical scanner -----
new_env
SCAN30B="$(mktemp -d)/scan"
cat > "$SCAN30B" <<'SH'
#!/usr/bin/env bash
echo '[{"repo":"fallback-repo","dirty":true,"dirty_files":1,"ahead":0,"detached":false,"branches":[]}]'
exit 1
SH
chmod +x "$SCAN30B"
export CHAT_GRAPH_SCAN_CMD="$SCAN30B"
printf '[]\n' > "$CHAT_GRAPH_GIT_FEED"
"$CG" ingest --collector repo_dirty >/dev/null 2>&1
if [ "$?" = 0 ] && \
   [ "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='repo_dirty' AND resolved_at IS NULL")" = 1 ]; then
  pass "malformed dashboard Git envelope falls back to the scanner"
else
  fail "malformed dashboard Git envelope blocked the scanner fallback"
fi

# --- 30c. cached Git envelope is strict and honors state/override routing ----
new_env
MCH30C="$(mktemp -d)"
if MISSION_CONTROL_HOME="$MCH30C" python3 - "$CG" "$CHAT_GRAPH_GIT_FEED" <<'PYEOF'
import copy, importlib.machinery, importlib.util, json, os, sys, time
tool, explicit_feed = sys.argv[1:]
sys.path.insert(0, os.path.dirname(tool))
loader = importlib.machinery.SourceFileLoader("chat_graph_cache_contract", tool)
spec = importlib.util.spec_from_loader(loader.name, loader)
cg = importlib.util.module_from_spec(spec); loader.exec_module(cg)
now = int(time.time())
row = {"repo": "cached", "dirty": True, "dirty_files": 1, "ahead": 0,
       "detached": False, "branches": []}
base = {"schema": 1, "feed": "git", "generated_epoch": now,
        "cadence_s": 900, "ok": True, "error": None,
        "data": {"repos": [row]}}
def write(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f: json.dump(value, f)
def load(value):
    write(explicit_feed, value); cg._REPO_ANNOTATIONS_CACHE = None
    return cg._fresh_git_feed_repos()
assert load(base) == [row]
bad = []
for key, value in (("schema", True), ("cadence_s", 10**9),
                   ("generated_epoch", now + 1)):
    item = copy.deepcopy(base); item[key] = value; bad.append(item)
for mutation in (
    lambda r: 42,
    lambda r: dict(r, ahead="abc"),
    lambda r: dict(r, dirty="false"),
    lambda r: dict(r, dirty_files=True),
    lambda r: dict(r, branches=[{"name": "old", "age_days": "7"}]),
):
    item = copy.deepcopy(base); item["data"]["repos"] = [mutation(row)]; bad.append(item)
for item in bad:
    assert load(item) is None, item

# No explicit feed path: canonical Mission Control home wins over process HOME.
os.environ.pop("CHAT_GRAPH_GIT_FEED", None)
expected = os.path.join(os.environ["MISSION_CONTROL_HOME"], "data", "git.json")
assert cg.GIT_FEED() == expected, (cg.GIT_FEED(), expected)
write(expected, base)

# An explicit scanner with only an implicit cache keeps scanner precedence.
os.environ["CHAT_GRAPH_SCAN_CMD"] = "/bin/echo []"
cg._REPO_ANNOTATIONS_CACHE = None
repos, notes = cg._repo_annotations()
assert repos == [] and notes == [], (repos, notes)

# Supplying both paths explicitly makes cache-first an intentional override.
os.environ["CHAT_GRAPH_GIT_FEED"] = expected
cg._REPO_ANNOTATIONS_CACHE = None
repos, notes = cg._repo_annotations()
assert repos == [row] and notes == [], (repos, notes)
PYEOF
then pass "Git cache rejects malformed rows and honors state/override precedence"
else fail "Git cache trust or routing contract"; fi

# --- 30d. same-cycle Git failure preserves unresolved repo truth ------------
new_env
DIRTY30D="$(mktemp -d)/scan"
cat > "$DIRTY30D" <<'SH'
#!/usr/bin/env bash
echo '[{"repo":"preserve-me","dirty":true,"dirty_files":1,"ahead":0,"detached":false,"branches":[]}]'
exit 1
SH
chmod +x "$DIRTY30D"
export CHAT_GRAPH_SCAN_CMD="$DIRTY30D"
"$CG" ingest --collector repo_dirty >/dev/null 2>&1
CLEAN30D="$(mktemp -d)/scan"
printf '#!/usr/bin/env bash\necho "[]"\n' > "$CLEAN30D"
chmod +x "$CLEAN30D"
export CHAT_GRAPH_SCAN_CMD="$CLEAN30D"
# A prior successful Git cycle can leave a still-fresh last-good cache. The
# explicit same-cycle failure signal must win over that cache.
python3 - "$CHAT_GRAPH_GIT_FEED" <<'PYEOF'
import json, sys, time
json.dump({"schema": 1, "feed": "git", "generated_epoch": int(time.time()),
           "cadence_s": 900, "ok": True, "error": None,
           "data": {"repos": []}}, open(sys.argv[1], "w"))
PYEOF
CHAT_GRAPH_SKIP_REPO_SCAN=dashboard-git-error \
  "$CG" ingest --collector repo_dirty >/dev/null 2>&1
EXP30D="$CHAT_GRAPH_HOME/export/graph.json"
CHAT_GRAPH_SKIP_REPO_SCAN=dashboard-git-error "$CG" export --json >/dev/null 2>&1
if [ "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='repo_dirty' AND resolved_at IS NULL")" = 1 ] && \
   python3 - "$EXP30D" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1]))["data"]
assert d["repo_annotations"] == []
assert any("repo annotations unavailable" in n for n in d["notes"]), d["notes"]
PYEOF
then pass "same-cycle Git failure preserves dirty truth and exports uncertainty"
else fail "same-cycle Git failure falsely reconciled repo truth"; fi

# --- 30e. SIGTERM unwinds the real ingest lock ------------------------------
new_env
SLOW30E="$(mktemp -d)/scan"
CHILD30E="$CHAT_GRAPH_HOME/slow-child.pid"
export CHILD30E
cat > "$SLOW30E" <<'SH'
#!/usr/bin/env bash
echo $$ > "$CHILD30E"
trap 'exit 0' TERM INT
while :; do sleep 1; done
SH
chmod +x "$SLOW30E"
export CHAT_GRAPH_SCAN_CMD="$SLOW30E"
"$CG" ingest --collector repo_dirty >/dev/null 2>&1 &
PARENT30E=$!
for _ in $(seq 1 100); do
  [ -d "$CHAT_GRAPH_HOME/ingest.lock" ] && [ -f "$CHILD30E" ] && break
  sleep 0.05
done
OWNER30E="$(python3 - "$CHAT_GRAPH_HOME/ingest.lock/owner.json" <<'PYEOF' 2>/dev/null
import json, sys
try: print(json.load(open(sys.argv[1])).get("pid", ""))
except Exception: print("")
PYEOF
)"
kill -TERM "$PARENT30E" 2>/dev/null || true
wait "$PARENT30E" 2>/dev/null || true
CPID30E="$(cat "$CHILD30E" 2>/dev/null || true)"
[ -z "$CPID30E" ] || kill -TERM "$CPID30E" 2>/dev/null || true
if [ "$OWNER30E" = "$PARENT30E" ] && [ ! -d "$CHAT_GRAPH_HOME/ingest.lock" ]; then
  pass "SIGTERM unwinds its owner-identified chat-graph ingest lock"
else
  rm -f "$CHAT_GRAPH_HOME/ingest.lock/owner.json" 2>/dev/null || true
  rmdir "$CHAT_GRAPH_HOME/ingest.lock" 2>/dev/null || true
  fail "SIGTERM lock owner/cleanup contract (owner=$OWNER30E parent=$PARENT30E)"
fi

# --- 30f. malformed/duplicate scanner rows preserve prior repo truth --------
new_env
SCAN30F="$(mktemp -d)/scan"
cat > "$SCAN30F" <<'SH'
#!/usr/bin/env bash
echo '[{"repo":"keep-open","dirty":true,"dirty_files":1,"ahead":0,"detached":false,"branches":[]}]'
SH
chmod +x "$SCAN30F"
export CHAT_GRAPH_SCAN_CMD="$SCAN30F"
"$CG" ingest --collector repo_dirty >/dev/null 2>&1
cat > "$SCAN30F" <<'SH'
#!/usr/bin/env bash
echo '[{"repo":"bad-row","dirty":false,"dirty_files":"one","ahead":0,"detached":false,"branches":[]}]'
SH
MALFORMED30F="$CHAT_GRAPH_HOME/export/malformed.json"
"$CG" ingest --collector repo_dirty >/dev/null 2>&1; RC30F=$?
"$CG" export --json >/dev/null 2>&1; EX30F=$?
cp "$CHAT_GRAPH_HOME/export/graph.json" "$MALFORMED30F" 2>/dev/null || true
if [ "$RC30F" = 0 ] && [ "$EX30F" = 0 ] && \
   [ "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='repo_dirty' AND resolved_at IS NULL AND session_id='repo:keep-open'")" = 1 ] && \
   python3 - "$MALFORMED30F" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))["data"]
assert d["repo_annotations"] == []
assert any("scanner output invalid" in n for n in d["notes"]), d["notes"]
PYEOF
then pass "malformed fallback rows are unavailable and preserve repo truth"
else fail "malformed fallback rows crashed or reconciled repo truth"; fi

cat > "$SCAN30F" <<'SH'
#!/usr/bin/env bash
echo '[{"repo":"dup","dirty":true,"dirty_files":1,"ahead":0,"detached":false,"branches":[]},{"repo":"dup","dirty":true,"dirty_files":1,"ahead":0,"detached":false,"branches":[]}]'
SH
"$CG" export --json >/dev/null 2>&1; DUPRC30F=$?
if [ "$DUPRC30F" = 0 ] && python3 - "$CHAT_GRAPH_HOME/export/graph.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))["data"]
assert d["repo_annotations"] == []
assert any("scanner output invalid" in n for n in d["notes"]), d["notes"]
PYEOF
then pass "duplicate fallback repo names are unavailable, not reconciled"
else fail "duplicate fallback repo names were trusted"; fi

# --- 31. loose-ends: register rows insert and resolve after verification ----
new_env
cat > "$CHAT_GRAPH_REGISTER" <<'MD'
| ER-999 | test requested behavior | open |
MD
"$CG" ingest --collector register_open >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='register_open' AND resolved_at IS NULL")" \
   "register_open collector inserts open enforcement row"
cat > "$CHAT_GRAPH_REGISTER" <<'MD'
| ER-999 | test requested behavior | verified |
MD
"$CG" ingest --collector register_open >/dev/null
ok 0 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='register_open' AND resolved_at IS NULL")" \
   "register_open auto-resolves after verified status"

# --- 32. loose-ends: severity rules are computed from kind/text/age ---------
new_env
"$CG" ingest --collector todo_open >/dev/null
python3 <<'PYEOF'
import os, sqlite3, time
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db)
now = int(time.time())
rows = [
    ("repo:global-implementations", "register_open", "ER-001 P0 security request still open", "sev-register", now),
    ("CHAT-HANDOFF", "closeout_handoff", "finish the old handoff", "sev-handoff", now - 22 * 86400),
    ("repo:repo-git", "repo_dirty", "repo-git: 2 unpushed commits", "sev-unpushed", now - 8 * 86400),
    ("repo:repo-git", "repo_dirty", "repo-git: detached HEAD needs a decision", "sev-detached", now),
]
for sid, kind, text, h, first_seen in rows:
    con.execute("""INSERT INTO open_ends(
                session_id, kind, text, text_hash, item_key,
                first_seen_at, updated_at, last_change_type)
                VALUES(?,?,?,?,?,?,?,'new')""",
                (sid, kind, text, h, 'item-' + h, first_seen, first_seen))
con.commit()
PYEOF
EXP32="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
if python3 - "$EXP32" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
sev = {x["text"]: x["severity"] for x in d["data"]["loose_ends"]}
assert sev["ER-001 P0 security request still open"] == "red"
assert sev["finish the old handoff"] == "grey"
assert sev["repo-git: 2 unpushed commits"] == "amber"
assert sev["repo-git: detached HEAD needs a decision"] == "red"
PYEOF
then pass "loose_end severity rules cover register, stale handoff, and repo_dirty cases"
else fail "loose_end severity rules missing documented cases"; fi

# --- 33. loose-ends: latest nightly report inserts and resolves -------------
new_env
N32="$(mktemp -d)"
export CHAT_GRAPH_NIGHTLY_REPORT_GLOB="$N32/*.md"
cat > "$N32/old.md" <<'MD'
- mission-control needs a follow-up after failed smoke test
MD
touch -t 202607080100 "$N32/old.md"
"$CG" ingest --collector nightly_finding >/dev/null
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='nightly_finding' AND resolved_at IS NULL")" \
   "nightly_finding collector inserts latest report finding"
cat > "$N32/new.md" <<'MD'
- all watched jobs green
MD
touch -t 202607080200 "$N32/new.md"
"$CG" ingest --collector nightly_finding >/dev/null
ok 0 "$(q "SELECT COUNT(*) FROM open_ends WHERE kind='nightly_finding' AND resolved_at IS NULL")" \
   "nightly_finding auto-resolves when newer report omits it"

# --- 34. validate-export requires the loose_ends contract -------------------
new_env
EXP33="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
"$CG" validate-export "$EXP33" >/dev/null 2>&1
ok 0 "$?" "validate-export accepts snapshot with loose_ends"
BAD33="$CHAT_GRAPH_HOME/export/bad.json"
python3 - "$EXP33" "$BAD33" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["data"].pop("loose_ends", None)
json.dump(d, open(sys.argv[2], "w"))
PYEOF
"$CG" validate-export "$BAD33" >/dev/null 2>&1; RC33=$?
if [ "$RC33" -ne 0 ]; then pass "validate-export rejects snapshot missing loose_ends"
else fail "validate-export accepted snapshot missing loose_ends"; fi

# --- 35. v4 -> v7 outcome/open-work/Tier-2 migration is additive + idempotent
new_env
python3 - <<'PYEOF'
import os, sqlite3
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db)
con.executescript("""
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  CREATE TABLE sessions(
    id TEXT PRIMARY KEY, provider TEXT, title TEXT, repo TEXT,
    first_prompt TEXT, last_activity TEXT,
    closeout_seen INTEGER DEFAULT 0, open_end_count INTEGER DEFAULT 0,
    first_seen_at INTEGER, first_msg_uuid TEXT, enriched_at INTEGER);
  CREATE TABLE open_ends(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT, kind TEXT, text TEXT, text_hash TEXT,
    resolved_at INTEGER, first_seen_at INTEGER, UNIQUE(session_id, text_hash));
""")
con.execute("INSERT INTO meta VALUES('schema_version','4')")
con.execute("INSERT INTO sessions(id,provider,title,repo,first_seen_at) VALUES(?,?,?,?,?)",
            ('repo:alpha','repo','Repo: alpha','alpha',100))
con.execute("INSERT INTO sessions(id,provider,title,first_seen_at) VALUES(?,?,?,?)",
            ('CHAT35','claude','Chat 35',101))
con.execute("INSERT INTO open_ends(session_id,kind,text,text_hash,first_seen_at) VALUES(?,?,?,?,?)",
            ('CHAT35','closeout_handoff','finish it','legacy-hash',102))
con.commit(); con.close()
PYEOF
"$CG" stats >/dev/null 2>&1
"$CG" stats >/dev/null 2>&1
ok 7 "$(q "SELECT value FROM meta WHERE key='schema_version'")" \
   "v4 DB migrates to schema 7 exactly once"
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE text_hash='legacy-hash' AND text='finish it'")" \
   "v5 migration preserves the legacy open-end row"
ok repo "$(q "SELECT node_kind FROM sessions WHERE id='repo:alpha'")" \
   "migration backfills repo node_kind"
ok chat "$(q "SELECT node_kind FROM sessions WHERE id='CHAT35'")" \
   "migration backfills allowlisted chat node_kind"
ok 5 "$(q "SELECT COUNT(*) FROM pragma_table_info('open_ends') WHERE name IN ('item_key','updated_at','resolution_evidence_type','resolution_evidence_ref','last_change_type')")" \
   "v5 adds stable item/update/resolution fields"
ok 1 "$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='session_outcomes'")" \
   "v7 creates additive session_outcomes storage"
ok 3 "$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('outcome_extraction_cache','outcome_extraction_health','outcome_extraction_attempts')")" \
   "v7 creates private Tier 2 cache, health, and retry storage"
ok 1 "$(q "SELECT COUNT(*) FROM (SELECT i.name FROM pragma_index_list('session_outcomes') i JOIN pragma_index_info(i.name) c WHERE i.[unique]=1 GROUP BY i.name HAVING group_concat(c.name)='session_id,tail_hash,method,variant')")" \
   "v7 permits immutable Tier 2 variants for one source tail"

# --- 36. provider/node-kind hygiene preserves repos and hides raw garbage ---
python3 - <<'PYEOF'
import os, sqlite3
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db)
con.execute("INSERT INTO sessions(id,provider,title,node_kind,first_seen_at) VALUES(?,?,?,?,?)",
            ('BAD36','${PARENT_PROVIDER}','Bad provider','unknown',103))
con.execute("INSERT INTO sessions(id,provider,title,node_kind,first_seen_at) VALUES(?,?,?,?,?)",
            ('CODEX36','codex','Codex 36','chat',104))
con.execute("INSERT INTO edges VALUES(?,?,?,?,?,?,?,?)",
            ('BAD36','CODEX36','continues','test',1.0,'{}',None,'active'))
con.execute("INSERT INTO edges VALUES(?,?,?,?,?,?,?,?)",
            ('CHAT35','CODEX36','continues','test',1.0,'{}',None,'active'))
con.commit(); con.close()
PYEOF
EXP36="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
if python3 - "$EXP36" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); nodes = {n['id']: n for n in d['data']['nodes']}
assert nodes['repo:alpha']['node_kind'] == 'repo'
assert nodes['repo:alpha']['provider'] == 'repo'
assert nodes['BAD36']['node_kind'] == 'unknown'
assert nodes['BAD36']['provider'] == 'unknown'
assert '${PARENT_PROVIDER}' not in json.dumps(d)
edges = {(e['src'], e['dst'], e['type']) for e in d['data']['edges']}
assert any('CHAT35' in a and 'CODEX36' in b for a,b,t in edges if t == 'continues')
assert not any('BAD36' in a or 'BAD36' in b for a,b,t in edges)
assert d['data']['counts']['unknown_provider_nodes'] >= 1
PYEOF
then pass "export preserves repo nodes, labels unknown safely, and excludes malformed lineage"
else fail "provider/node-kind hygiene export contract"; fi

# --- 37. same text under distinct kinds coexists; chat omission never resolves
python3 - <<'PYEOF'
import os, sqlite3, time
db = os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db")
con = sqlite3.connect(db); now = int(time.time())
for kind, key, text_hash in [('chat_open_end','item-chat','hash-chat'),
                             ('closeout_handoff','item-handoff','hash-handoff')]:
    con.execute("INSERT INTO open_ends(session_id,kind,text,text_hash,item_key,first_seen_at,updated_at,last_change_type) VALUES(?,?,?,?,?,?,?,?)",
                ('CHAT35',kind,'identical text',text_hash,key,now,now,'new'))
con.commit(); con.close()
PYEOF
ok 2 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='CHAT35' AND text='identical text'")" \
   "same text under two kinds has two stable items"
mkdir -p "$(cl_root)"
umsg "Session Closeout Handoff: finish a different item" u37 > "$(cl_root)/CHAT35.jsonl"
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='CHAT35' AND kind='chat_open_end' AND item_key='item-chat' AND resolved_at IS NULL")" \
   "finalized extraction omission does not resolve chat_open_end"

# --- 38. manual resolution records evidence and exports a bounded change ----
HASH38="$(q "SELECT text_hash FROM open_ends WHERE session_id='CHAT35' AND kind='chat_open_end' LIMIT 1")"
"$CG" resolve CHAT35 "$HASH38" >/dev/null
ok manual "$(q "SELECT resolution_evidence_type FROM open_ends WHERE session_id='CHAT35' AND kind='chat_open_end'")" \
   "manual resolve stores resolution evidence type"
ok journal "$(q "SELECT resolution_evidence_ref FROM open_ends WHERE session_id='CHAT35' AND kind='chat_open_end'")" \
   "manual resolve stores journal evidence reference"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
if python3 - "$EXP36" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); changes = d['data']['loose_end_changes']
hit = [c for c in changes if c['source_id'] == 'CHAT35' and c['kind'] == 'chat_open_end']
assert hit and hit[0]['change_type'] == 'resolved'
assert hit[0]['resolution_evidence_type'] == 'manual'
assert hit[0]['resolution_evidence_ref'] == 'journal'
assert len(changes) <= 500
PYEOF
then pass "export includes bounded stable loose_end_changes with resolution evidence"
else fail "loose_end_changes export contract"; fi

# --- 39. validate-export requires the loose_end_changes contract ------------
"$CG" validate-export "$EXP36" >/dev/null 2>&1
ok 0 "$?" "validate-export accepts snapshot with loose_end_changes"
BAD39="$CHAT_GRAPH_HOME/export/bad-changes.json"
python3 - "$EXP36" "$BAD39" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d['data'].pop('loose_end_changes', None)
json.dump(d, open(sys.argv[2], 'w'))
PYEOF
"$CG" validate-export "$BAD39" >/dev/null 2>&1; RC39=$?
if [ "$RC39" -ne 0 ]; then pass "validate-export rejects snapshot missing loose_end_changes"
else fail "validate-export accepted snapshot missing loose_end_changes"; fi

# --- 40. synthetic real-shape Tier 1 fixture grammar -----------------------
if python3 - "$HERE/chat-graph" "$HERE/../tests/fixtures/outcomes" <<'PYEOF'
import importlib.machinery, importlib.util, json, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
loader = importlib.machinery.SourceFileLoader("chat_graph", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
cg = importlib.util.module_from_spec(spec); loader.exec_module(cg)
root = sys.argv[2]
for name in sorted(os.listdir(root)):
    fixture = json.load(open(os.path.join(root, name)))
    if "messages" not in fixture:
        continue
    card = cg.tier1_parse_outcome(fixture["session_id"], fixture["provider"], fixture["messages"])
    want = fixture["expected"]
    assert card["classification"] == want["classification"], (name, card)
    assert card["grammar"] == want["grammar"], (name, card)
    if "finalized" in want:
        assert card["finalized"] is want["finalized"], (name, card)
    if "provider" in want:
        assert card["provider"] == want["provider"], (name, card)
    if "commit" in want:
        assert want["commit"] in card["anchors"]["commits"], (name, card)
    if "command" in want:
        assert want["command"] in card["anchors"]["commands"], (name, card)
    if "needs_you" in want:
        assert any(item["section"] == "needs_you" and item["text"] == want["needs_you"]
                   for item in card["open_work"]), (name, card)
    if want["classification"] == "authored_handoff":
        assert card["did"] == ["Authored a handoff packet"]
        assert not any("Implement SQLite" in item for item in card["did"])
PYEOF
then pass "Tier 1 parses reply-v5/Codex/audit/handoff/unstructured/unknown shapes honestly"
else fail "Tier 1 synthetic grammar fixtures"; fi

# --- 41. bounded parser ignores content outside the assistant tail ---------
if python3 - "$HERE/chat-graph" <<'PYEOF'
import importlib.machinery, importlib.util, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
loader = importlib.machinery.SourceFileLoader("chat_graph_bound", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
cg = importlib.util.module_from_spec(spec); loader.exec_module(cg)
messages = [{"role":"assistant", "content":"Outcome\nold should be excluded\nStatus: complete"}]
messages += [{"role":"user", "content":"tool-like user noise"} for _ in range(15)]
messages += [{"role":"assistant", "content":"plain tail %d" % i} for i in range(13)]
card = cg.tier1_parse_outcome("BOUND41", "claude", messages)
assert card["grammar"] == "unstructured"
assert "old should be excluded" not in str(card)
assert card["source_span"]["message_count"] <= 12
assert card["source_span"]["bytes"] <= 32768
PYEOF
then pass "Tier 1 consumes only the bounded assistant tail"
else fail "Tier 1 assistant-tail bound"; fi

# --- 41b. stable item identity, exact ACTION fields, counters, hard bytes ----
if python3 - "$HERE/chat-graph" <<'PYEOF'
import importlib.machinery,importlib.util,os,sys
sys.path.insert(0,os.path.dirname(sys.argv[1]))
l=importlib.machinery.SourceFileLoader("chat_graph_edges",sys.argv[1])
s=importlib.util.spec_from_loader(l.name,l)
cg=importlib.util.module_from_spec(s); l.exec_module(cg)
def card(items, suffix=""):
    body="\n".join("- "+x for x in items)
    text=("Re: stable\n\nAnswer\nWorking.\n\nDone\n- Safe work.\n\nNext\n"+body+
          "\n\nDetails\nVerification: `bash /Users/gillettes/Downloads/private/check.sh`"+suffix)
    return cg.tier1_parse_outcome("STABLE41","claude",[
        {"id":suffix or "a","role":"assistant","content":text}])
a=card(["Alpha task","Beta task"])
b=card(["Beta task","Alpha task"]," ")
ka={x["text"]:x["item_key"] for x in a["open_work"]}
kb={x["text"]:x["item_key"] for x in b["open_work"]}
assert ka==kb
assert a["anchors"]["commands"]==["bash /Users/gillettes/Downloads/private/check.sh"]
assert a["egress_counters"]["path_redactions"]>=1
pa=cg.tier1_parse_outcome("PATH41","claude",[{"id":"pa","role":"assistant",
 "content":"Outcome\nSafe.\nVerification: `bash /Users/gillettes/Downloads/a.sh`\nStatus: complete"}])
pb=cg.tier1_parse_outcome("PATH41","claude",[{"id":"pb","role":"assistant",
 "content":"Outcome\nSafe.\nVerification: `bash /Users/gillettes/Downloads/b.sh`\nStatus: complete"}])
assert pa["tail_hash"]!=pb["tail_hash"] and pa["anchors"]!=pb["anchors"]
messages=[{"id":str(i),"role":"assistant","content":"x"*4000} for i in range(12)]
bounded=cg.tier1_parse_outcome("BYTES41","claude",messages)
assert bounded["source_span"]["bytes"]<=32768
expanded=cg.tier1_parse_outcome("EXPAND41","claude",[
    {"id":"expand","role":"assistant","content":("/tmp/a "*4000)}])
assert expanded["source_span"]["bytes"]<=32768
private=cg.tier1_parse_outcome("PRIVATE41","claude",[
    {"id":"p","role":"assistant","content":"Outcome\nowner@example.com\nStatus: complete"}])
assert private["egress_counters"]["dropped_fields"]>=1
multi=cg.tier1_parse_outcome("COHERENT41","codex",[{"id":"m","role":"assistant",
 "content":"Re: repair\n\nNEEDS YOU\nA token must be rotated.\n1. Run:\n```bash\n# exact operator procedure\nexport API_MODE=safe\ncurl https://example.invalid/health\necho arbitrary fragment\nlaunchctl print gui/501/example \\\n  --verbose\njq '.ok' result.json\ncd /tmp/private\n./rotate-token\n```\n2. Approve browser authorization.\n3. Confirm:\n```bash\n./verify-token\n```\nDo not paste the token.\n\nAnswer: Everything else is complete and must not enter the decision.\n\nDone\n- Repair shipped."}])
needs=[x for x in multi["open_work"] if x["section"]=="needs_you"]
assert len(needs)==1, needs
assert "A token must be rotated" in needs[0]["text"]
assert "Approve browser authorization" in needs[0]["text"]
for fragment in ("```","./rotate-token","export API_MODE","curl ","arbitrary fragment"):
    assert fragment not in needs[0]["text"], needs
assert "Everything else is complete" not in needs[0]["text"]
for command in ("export API_MODE=safe","curl https://example.invalid/health",
                "echo arbitrary fragment","launchctl print gui/501/example --verbose",
                "jq '.ok' result.json","cd /tmp/private","./rotate-token",
                "./verify-token"):
    assert command in multi["anchors"]["commands"], (command,multi["anchors"])
assert not any("exact operator procedure" in x for x in multi["anchors"]["commands"])
assert multi["parser_version"]==5
PYEOF
then pass "Tier 1 uses stable content keys, field-aware actions/counters, and hard byte cap"
else fail "Tier 1 stable/action/counter/byte contract"; fi

# Parser-version changes reprocess unchanged source, replace its representation,
# and explicitly supersede old split items rather than leaving cache/ledger dirt.
new_env
if python3 - "$HERE/chat-graph" <<'PYEOF'
import importlib.machinery,importlib.util,os,sys
sys.path.insert(0,os.path.dirname(sys.argv[1]))
l=importlib.machinery.SourceFileLoader("chat_graph_parser_migration",sys.argv[1])
s=importlib.util.spec_from_loader(l.name,l); cg=importlib.util.module_from_spec(s); l.exec_module(cg)
con=cg.connect(); sid="PARSER-MIGRATION-41"
cg.touch_session(con,sid,provider="codex",title="Parser migration")
messages=[{"id":"same-source","role":"assistant","content":
 "Re: migration\n\nNEEDS YOU\nRotate the token.\n1. Run:\n```bash\n./rotate-token\n```\n2. Confirm the browser.\n\nDone\n- Repair shipped."}]
real=cg._coherent_needs_you_items
cg.TIER1_PARSER_VERSION=1; cg._coherent_needs_you_items=lambda lines: lines
old=cg._persist_tier1_outcome(con,sid,"codex",messages,"fixture"); con.commit()
old_keys={x["item_key"] for x in old["open_work"]}
assert len(old_keys)>1
cg.TIER1_PARSER_VERSION=5; cg._coherent_needs_you_items=real
new=cg._persist_tier1_outcome(con,sid,"codex",messages,"fixture"); con.commit()
new_keys={x["item_key"] for x in new["open_work"]}
assert len(new_keys)==1 and not (new_keys & old_keys)
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id=?",(sid,)).fetchone()[0]==2
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id=? AND resolved_at IS NULL",(sid,)).fetchone()[0]==1
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id=? AND resolution_evidence_type='parser_migration'",(sid,)).fetchone()[0]==len(old_keys)
# A parser upgrade with a different/unstructured selected source is omission,
# not compaction evidence, so every prior open fragment stays open.
sid2="PARSER-OMISSION-41"; cg.touch_session(con,sid2,provider="codex")
cg.TIER1_PARSER_VERSION=1; cg._coherent_needs_you_items=lambda lines: lines
old2=cg._persist_tier1_outcome(con,sid2,"codex",messages,"fixture"); con.commit()
cg.TIER1_PARSER_VERSION=5; cg._coherent_needs_you_items=real
cg._persist_tier1_outcome(con,sid2,"codex",[
 {"id":"different-source","role":"assistant","content":"Unstructured later tail."}],"fixture")
con.commit()
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id=? AND resolved_at IS NULL",(sid2,)).fetchone()[0]==len(old2["open_work"])
# Reusing a provider message ID with changed content is still a changed source;
# message identity alone can never authorize parser_migration resolution.
sid3="PARSER-REWRITE-41"; cg.touch_session(con,sid3,provider="codex")
cg.TIER1_PARSER_VERSION=1; cg._coherent_needs_you_items=lambda lines: lines
old3=cg._persist_tier1_outcome(con,sid3,"codex",[
 {"id":"rewritten-id","role":"assistant","content":
  "Re: rewrite\n\nNEEDS YOU\nChoose A.\n1. Confirm A.\n\nDone\n- Waiting."}],"fixture")
con.commit(); old3_keys={x["item_key"] for x in old3["open_work"]}
cg.TIER1_PARSER_VERSION=5; cg._coherent_needs_you_items=real
cg._persist_tier1_outcome(con,sid3,"codex",[
 {"id":"rewritten-id","role":"assistant","content":
  "Re: rewrite\n\nNEEDS YOU\nChoose B.\n\nDone\n- Changed."}],"fixture")
con.commit()
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id=? AND item_key IN (%s) AND resolved_at IS NULL" % ",".join("?"*len(old3_keys)),(sid3,*old3_keys)).fetchone()[0]==len(old3_keys)
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id=? AND resolution_evidence_type='parser_migration'",(sid3,)).fetchone()[0]==0
con.close()
PYEOF
then pass "parser version reprocesses source and supersedes split open items"
else fail "Tier 1 parser-version migration"; fi

# Normal incremental ingestion (not a direct parser call) must reprocess an
# unchanged file when its stored parser version is older.
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/PARSER-INCREMENTAL-41.jsonl" <<'JSONL'
{"id":"same-incremental-source","role":"assistant","type":"assistant","content":"Re: migration\n\nNEEDS YOU\nRotate the token.\n1. Run:\n```bash\n./rotate-token\n```\n2. Confirm the browser.\n\nDone\n- Repair shipped."}
JSONL
if python3 - "$HERE/chat-graph" <<'PYEOF'
import importlib.machinery,importlib.util,os,sys
sys.path.insert(0,os.path.dirname(sys.argv[1]))
l=importlib.machinery.SourceFileLoader("chat_graph_incremental_migration",sys.argv[1])
s=importlib.util.spec_from_loader(l.name,l); cg=importlib.util.module_from_spec(s); l.exec_module(cg)
real=cg._coherent_needs_you_items
con=cg.connect(); cg.TIER1_PARSER_VERSION=1; cg._coherent_needs_you_items=lambda lines: lines
cg.scan_transcripts(con,full=True)
before=con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id='PARSER-INCREMENTAL-41'").fetchone()[0]
assert before==1
cg.TIER1_PARSER_VERSION=5; cg._coherent_needs_you_items=real
cg.scan_transcripts(con,full=False)
assert con.execute("SELECT parser_version FROM file_cursors").fetchone()[0]==5
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id='PARSER-INCREMENTAL-41'").fetchone()[0]==2
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id='PARSER-INCREMENTAL-41' AND resolved_at IS NULL").fetchone()[0]==1
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id='PARSER-INCREMENTAL-41' AND resolution_evidence_type='parser_migration'").fetchone()[0]>1
con.close()
PYEOF
then pass "incremental ingest invalidates unchanged sources on parser upgrade"
else fail "incremental parser-version invalidation"; fi

# --- 42. persisted cards are stable, additive, and emit late updates -------
new_env
mkdir -p "$(cl_root)"
python3 - "$HERE/../tests/fixtures/outcomes/late-closeout.json" "$(cl_root)/66666666-6666-4666-8666-666666666666.jsonl" 0 <<'PYEOF'
import json, sys
f = json.load(open(sys.argv[1])); version = f["versions"][int(sys.argv[3])]
with open(sys.argv[2], "w") as out:
    for i, m in enumerate(version):
        out.write(json.dumps({"id":"late-%d" % i,"role":m["role"],"type":m["role"],"content":m["content"]}) + "\n")
PYEOF
"$CG" ingest --full >/dev/null 2>&1
CARD42A="$(q "SELECT json_extract(outcome_json,'$.card_id') FROM session_outcomes WHERE session_id='66666666-6666-4666-8666-666666666666' ORDER BY rowid LIMIT 1")"
ok 0 "$(q "SELECT finalized FROM session_outcomes WHERE session_id='66666666-6666-4666-8666-666666666666' ORDER BY rowid LIMIT 1")" \
   "working tail persists a non-finalized outcome card"
python3 - "$HERE/../tests/fixtures/outcomes/late-closeout.json" "$(cl_root)/66666666-6666-4666-8666-666666666666.jsonl" 1 <<'PYEOF'
import json, sys
f = json.load(open(sys.argv[1])); version = f["versions"][int(sys.argv[3])]
with open(sys.argv[2], "w") as out:
    for i, m in enumerate(version):
        out.write(json.dumps({"id":"late-final-%d" % i,"role":m["role"],"type":m["role"],"content":m["content"]}) + "\n")
PYEOF
"$CG" ingest --full >/dev/null 2>&1
CARD42B="$(q "SELECT json_extract(outcome_json,'$.card_id') FROM session_outcomes WHERE session_id='66666666-6666-4666-8666-666666666666' ORDER BY rowid DESC LIMIT 1")"
ok "$CARD42A" "$CARD42B" "outcome card_id stays stable across changed tails"
ok 2 "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='66666666-6666-4666-8666-666666666666'")" \
   "changed late closeout preserves both outcome versions"
ok 1 "$(q "SELECT finalized FROM session_outcomes WHERE session_id='66666666-6666-4666-8666-666666666666' ORDER BY rowid DESC LIMIT 1")" \
   "late closeout persists finalized state"
EXP42="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
if python3 - "$EXP42" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); data = d["data"]
cards = [x for x in data["outcomes"] if x["session_id"].startswith("66666666")]
updates = [x for x in data["outcome_updates"] if x["session_id"].startswith("66666666")]
assert len(cards) == 1 and cards[0]["finalized"] is True
assert len(updates) >= 1 and updates[-1]["change_type"] == "late_update"
assert updates[-1]["previous_finalized"] is False and updates[-1]["finalized"] is True
PYEOF
then pass "additive export emits latest outcome and late-update event"
else fail "outcome/late-update export contract"; fi

# A rewind A -> B -> A keeps immutable versions but makes the latest observation A.
new_env
if python3 - "$HERE/chat-graph" <<'PYEOF'
import importlib.machinery,importlib.util,os,sys,time
sys.path.insert(0,os.path.dirname(sys.argv[1]))
l=importlib.machinery.SourceFileLoader("chat_graph_rewind",sys.argv[1]); s=importlib.util.spec_from_loader(l.name,l)
cg=importlib.util.module_from_spec(s); l.exec_module(cg)
con=cg.connect()
def messages(label,mid):
    return [{"id":mid,"role":"assistant","content":
      "Outcome\n%s\nStatus: complete" % label}]
cg._persist_tier1_outcome(con,"REWIND42","claude",messages("A","a"),"fixture")
cg._persist_tier1_outcome(con,"REWIND42","claude",messages("B","b"),"fixture")
cg._persist_tier1_outcome(con,"REWIND42","claude",messages("A","a"),"fixture")
con.commit()
cards,updates=cg._outcome_export(con,0)
card=[x for x in cards if x["session_id"]=="REWIND42"][0]
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id='REWIND42'").fetchone()[0]==2
assert con.execute("SELECT COUNT(*) FROM session_outcome_observations WHERE session_id='REWIND42'").fetchone()[0]==3
assert card["did"]==["A"] and len([u for u in updates if u["session_id"]=="REWIND42"])==2
PYEOF
then pass "outcome observations preserve A-B-A current ordering"
else fail "outcome A-B-A observation ordering"; fi

# --- 43. chat open work resolves only through exact explicit evidence ------
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/ORIGIN43.jsonl" <<'JSONL'
{"id":"o43","role":"assistant","type":"assistant","content":"Re: parser\n\nAnswer\nWorking.\n\nDone\n- Added the grammar.\n\nNext\n- Finish the privacy review."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ITEM43="$(q "SELECT item_key FROM open_ends WHERE session_id='ORIGIN43' AND kind='chat_open_end' AND resolved_at IS NULL LIMIT 1")"
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='ORIGIN43' AND kind='chat_open_end' AND resolved_at IS NULL")" \
   "Tier 1 creates stable chat_open_end item"
# Omission is not evidence.
cat > "$(cl_root)/ORIGIN43.jsonl" <<'JSONL'
{"id":"o43b","role":"assistant","type":"assistant","content":"A later message omits the open item."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='ORIGIN43' AND kind='chat_open_end' AND resolved_at IS NULL")" \
   "later omission does not resolve outcome open work"
# Unverified downstream mention is not evidence.
cat > "$(cl_root)/CHILD43.jsonl" <<JSONL
{"id":"c43","role":"assistant","type":"assistant","content":"Resolves: $ITEM43"}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='ORIGIN43' AND item_key='$ITEM43' AND resolved_at IS NULL")" \
   "unlinked downstream marker cannot resolve an item"
# Verified spawn edge plus exact key resolves and records the downstream source.
mk_delegation dlg43 ORIGIN43 CHILD43 yes
touch "$(cl_root)/CHILD43.jsonl"
"$CG" ingest --full >/dev/null 2>&1
ok downstream_explicit "$(q "SELECT resolution_evidence_type FROM open_ends WHERE session_id='ORIGIN43' AND item_key='$ITEM43'")" \
   "verified downstream exact key stores explicit evidence type"
ok CHILD43 "$(q "SELECT resolution_evidence_ref FROM open_ends WHERE session_id='ORIGIN43' AND item_key='$ITEM43'")" \
   "verified downstream exact key stores resolving session"

new_env
if python3 - "$HERE/chat-graph" <<'PYEOF'
import importlib.machinery,importlib.util,os,sys
sys.path.insert(0,os.path.dirname(sys.argv[1]))
l=importlib.machinery.SourceFileLoader("chat_graph_exact",sys.argv[1]); s=importlib.util.spec_from_loader(l.name,l)
cg=importlib.util.module_from_spec(s); l.exec_module(cg)
con=cg.connect(); cg.touch_session(con,"DUP43",provider="claude")
cg._upsert_open_end(con,"DUP43","chat_open_end","same text",source_key="first")
cg._upsert_open_end(con,"DUP43","chat_open_end","same text",source_key="second")
key=con.execute("SELECT item_key FROM open_ends WHERE session_id='DUP43' ORDER BY id LIMIT 1").fetchone()[0]
assert cg._resolve_open_end_key(con,"DUP43",key,"same_session_explicit","DUP43")==1
assert con.execute("SELECT COUNT(*) FROM open_ends WHERE session_id='DUP43' AND resolved_at IS NULL").fetchone()[0]==1
PYEOF
then pass "exact item-key resolution never fans out through duplicate text"
else fail "exact item-key resolution fanout"; fi

# --- 44. same-session exact Resolved marker resolves; near-match does not --
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/SAME44.jsonl" <<'JSONL'
{"id":"s44","role":"assistant","type":"assistant","content":"Re: explicit\n\nAnswer\nWorking.\n\nDone\n- Added one test.\n\nNext\n- Run the exact check."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ITEM44="$(q "SELECT item_key FROM open_ends WHERE session_id='SAME44' AND kind='chat_open_end' LIMIT 1")"
cat > "$(cl_root)/SAME44.jsonl" <<JSONL
{"id":"s44b","role":"assistant","type":"assistant","content":"Resolved: ${ITEM44}x"}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='SAME44' AND item_key='$ITEM44' AND resolved_at IS NULL")" \
   "near-match resolution marker is rejected"
cat > "$(cl_root)/SAME44.jsonl" <<JSONL
{"id":"s44a","role":"assistant","type":"assistant","content":"Re: exact\n\nAnswer\nWorking.\n\nDone\n- Asked.\n\nNext\n- Keep this item open."}
{"id":"s44c","role":"assistant","type":"assistant","content":"Resolved: $ITEM44"}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok same_session_explicit "$(q "SELECT resolution_evidence_type FROM open_ends WHERE session_id='SAME44' AND item_key='$ITEM44'")" \
   "same-session exact key stores explicit resolution evidence"

# A structured closeout may carry its own explicit marker in Details. Equality
# with the selected message is valid; only an older message is stale.
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/SAMEMSG44.jsonl" <<'JSONL'
{"id":"sm44a","role":"assistant","type":"assistant","content":"Re: same message\n\nAnswer\nWorking.\n\nDone\n- Asked.\n\nNext\n- Keep this item open."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
SAME_MSG_KEY="$(q "SELECT item_key FROM open_ends WHERE session_id='SAMEMSG44' AND kind='chat_open_end' LIMIT 1")"
cat > "$(cl_root)/SAMEMSG44.jsonl" <<JSONL
{"id":"sm44b","role":"assistant","type":"assistant","content":"Re: same message\n\nAnswer\nCompleted.\n\nDone\n- Closed it.\n\nDetails\nResolved: $SAME_MSG_KEY"}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok same_session_explicit "$(q "SELECT resolution_evidence_type FROM open_ends WHERE session_id='SAMEMSG44' AND item_key='$SAME_MSG_KEY'")" \
   "same-message exact marker resolves its existing item"

new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/CONTRADICT44.jsonl" <<'JSONL'
{"id":"co44a","role":"assistant","type":"assistant","content":"Re: contradiction\n\nAnswer\nWorking.\n\nDone\n- Asked.\n\nNext\n- Keep this item open."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
CONTRADICT_KEY="$(q "SELECT item_key FROM open_ends WHERE session_id='CONTRADICT44' AND kind='chat_open_end' LIMIT 1")"
cat > "$(cl_root)/CONTRADICT44.jsonl" <<JSONL
{"id":"co44b","role":"assistant","type":"assistant","content":"Re: contradiction\n\nAnswer\nConflicting evidence.\n\nDone\n- Reopened.\n\nNext\n- Keep this item open.\n\nDetails\nResolved: $CONTRADICT_KEY"}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='CONTRADICT44' AND item_key='$CONTRADICT_KEY' AND resolved_at IS NULL")" \
   "contradictory same-message reopen and resolve fails closed"

# --- 45. appended chatter preserves card without reopening resolved work ----
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/CHATTER45.jsonl" <<'JSONL'
{"id":"ch45a","role":"assistant","type":"assistant","content":"Re: explicit\n\nAnswer\nWorking.\n\nDone\n- Added one test.\n\nNext\n- Run the exact check."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ITEM45="$(q "SELECT item_key FROM open_ends WHERE session_id='CHATTER45' AND kind='chat_open_end' LIMIT 1")"
cat >> "$(cl_root)/CHATTER45.jsonl" <<JSONL
{"id":"ch45b","role":"assistant","type":"assistant","content":"Resolved: $ITEM45"}
JSONL
cat >> "$(cl_root)/CHATTER45.jsonl" <<'JSONL'
{"id":"ch45c","role":"assistant","type":"assistant","content":"Thanks — I will keep that context in mind."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 0 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='CHATTER45' AND item_key='$ITEM45' AND resolved_at IS NULL")" \
   "later chatter does not reopen explicitly resolved work from an older closeout"
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
EXP45="$CHAT_GRAPH_HOME/export/graph.json"
if python3 - "$EXP45" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))["data"]
cards = [c for c in d["outcomes"] if c["session_id"] == "CHATTER45"]
updates = [u for u in d["outcome_updates"] if u["session_id"] == "CHATTER45"]
assert len(cards) == 1 and cards[0]["grammar"] == "reply_v5"
assert updates == []
PYEOF
then pass "newer chatter preserves newest structured card without false late update"
else fail "appended chatter outcome stability"; fi
cat >> "$(cl_root)/CHATTER45.jsonl" <<'JSONL'
{"id":"ch45d","role":"assistant","type":"assistant","content":"Re: explicit\n\nAnswer\nNew evidence.\n\nDone\n- Added another test.\n\nNext\n- Run the exact check."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='CHATTER45' AND item_key='$ITEM45' AND resolved_at IS NULL")" \
   "old marker does not re-resolve a newly reopened item"

# Marker and newer reopening closeout can arrive in one collector interval; the
# older marker must not close the newer source occurrence.
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/ORDER45.jsonl" <<'JSONL'
{"id":"order-open","role":"assistant","type":"assistant","content":"Re: order\n\nAnswer\nWorking.\n\nDone\n- Asked.\n\nNext\n- Keep this item open."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ORDER_KEY="$(q "SELECT item_key FROM open_ends WHERE session_id='ORDER45' AND kind='chat_open_end' LIMIT 1")"
cat > "$(cl_root)/ORDER45.jsonl" <<JSONL
{"id":"order-marker","role":"assistant","type":"assistant","content":"Resolved: $ORDER_KEY"}
{"id":"order-new","role":"assistant","type":"assistant","content":"Re: order\n\nAnswer\nNew evidence.\n\nDone\n- Reopened.\n\nNext\n- Keep this item open."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='ORDER45' AND item_key='$ORDER_KEY' AND resolved_at IS NULL")" \
   "older marker cannot resolve newer closeout in one ingest"

# A new structured closeout followed by chatter is still persisted.
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/NEWCHATTER45.jsonl" <<'JSONL'
{"id":"nc-old","role":"assistant","type":"assistant","content":"Earlier unstructured message."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
cat >> "$(cl_root)/NEWCHATTER45.jsonl" <<'JSONL'
{"id":"nc-close","role":"assistant","type":"assistant","content":"Re: new closeout\n\nAnswer\nWorking.\n\nDone\n- New closeout.\n\nNext\n- Preserve this item."}
{"id":"nc-chat","role":"assistant","type":"assistant","content":"Thanks."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='NEWCHATTER45' AND kind='chat_open_end' AND resolved_at IS NULL")" \
   "new structured closeout persists open work despite later chatter"

# An exact user Answers marker produces graph-backed answering-turn evidence.
new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/ANSWER45.jsonl" <<'JSONL'
{"id":"answer-open","role":"assistant","type":"assistant","content":"Re: answer\n\nAnswer\nWaiting.\n\nDone\n- Asked.\n\nNeeds you\n- Choose the window."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ANSWER_KEY="$(q "SELECT item_key FROM open_ends WHERE session_id='ANSWER45' AND kind='chat_open_end' LIMIT 1")"
cat >> "$(cl_root)/ANSWER45.jsonl" <<JSONL
{"id":"answer-user","role":"user","type":"user","content":"Answers: $ANSWER_KEY"}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok answering_user_turn "$(q "SELECT resolution_evidence_type FROM open_ends WHERE session_id='ANSWER45' AND item_key='$ANSWER_KEY'")" \
   "exact user answer marker produces graph-backed resolution evidence"

new_env
mkdir -p "$(cl_root)"
cat > "$(cl_root)/ANSWERORDER45.jsonl" <<'JSONL'
{"id":"ao-open","role":"assistant","type":"assistant","content":"Re: answer order\n\nAnswer\nWaiting.\n\nDone\n- Asked.\n\nNeeds you\n- Choose the window."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ANSWER_ORDER_KEY="$(q "SELECT item_key FROM open_ends WHERE session_id='ANSWERORDER45' AND kind='chat_open_end' LIMIT 1")"
cat > "$(cl_root)/ANSWERORDER45.jsonl" <<JSONL
{"id":"ao-user","role":"user","type":"user","content":"Answers: $ANSWER_ORDER_KEY"}
{"id":"ao-new","role":"assistant","type":"assistant","content":"Re: answer order\n\nAnswer\nNew evidence.\n\nDone\n- Reopened.\n\nNeeds you\n- Choose the window."}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE session_id='ANSWERORDER45' AND item_key='$ANSWER_ORDER_KEY' AND resolved_at IS NULL")" \
   "older user answer cannot resolve newer decision occurrence"

# --- 46. outcome storage/export fail closed on sensitive tail fields -------
if python3 - "$HERE/chat-graph" <<'PYEOF'
import importlib.machinery, importlib.util, json, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
loader = importlib.machinery.SourceFileLoader("chat_graph_privacy", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
cg = importlib.util.module_from_spec(spec); loader.exec_module(cg)
secret = "sk-abcdefghijklmnopqrstuvwxyz123456"
email = "private.person@example.com"
card = cg.tier1_parse_outcome("PRIVATE46", "claude", [{"role":"assistant", "content":
    "Outcome\nSafe statement.\nVerification: `bash run --token %s`\nContact %s\nStatus: complete" % (secret, email)}])
blob = json.dumps(card)
assert secret not in blob and email not in blob
assert card["anchors"]["commands"] == []
assert card["grammar"] == "unstructured" and card["source_span"]["bytes"] < 64
PYEOF
then pass "Tier 1 drops secret/PII fields before card storage or anchor extraction"
else fail "Tier 1 privacy boundary"; fi

# --- 47. validate-export requires additive outcomes/update arrays ----------
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
EXP47="$CHAT_GRAPH_HOME/export/graph.json"
"$CG" validate-export "$EXP47" >/dev/null 2>&1
ok 0 "$?" "validate-export accepts outcome arrays"
if python3 - "$EXP47" <<'PYEOF'
import json,sys
cards=json.load(open(sys.argv[1]))["data"]["outcomes"]
assert cards and all(isinstance(card.get("session_title"),str) and
                     isinstance(card.get("repo"),str) for card in cards)
PYEOF
then pass "outcome export carries deterministic session title and repo context"
else fail "outcome export deterministic context"; fi
BAD47="$CHAT_GRAPH_HOME/export/bad-outcomes.json"
python3 - "$EXP47" "$BAD47" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["data"].pop("outcomes", None)
json.dump(d, open(sys.argv[2], "w"))
PYEOF
"$CG" validate-export "$BAD47" >/dev/null 2>&1; RC47=$?
if [ "$RC47" -ne 0 ]; then pass "validate-export rejects snapshot missing outcomes"
else fail "validate-export accepted snapshot missing outcomes"; fi
BAD47H="$CHAT_GRAPH_HOME/export/bad-outcome-health.json"
python3 - "$EXP47" "$BAD47H" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["data"].pop("outcome_extraction_health", None)
json.dump(d, open(sys.argv[2], "w"))
PYEOF
"$CG" validate-export "$BAD47H" >/dev/null 2>&1; RC47H=$?
if [ "$RC47H" -ne 0 ]; then pass "validate-export rejects missing extraction health"
else fail "validate-export accepted missing extraction health"; fi

# --- 47b. newer Claude subagent file cannot replace parent transcript -------
new_env
PARENT47="77777777-7777-4777-8777-777777777777"
mkdir -p "$CHAT_GRAPH_CLAUDE_ROOT/project/$PARENT47/subagents"
printf '%s\n' '{"id":"parent","role":"assistant","content":"parent"}' > \
  "$CHAT_GRAPH_CLAUDE_ROOT/project/$PARENT47.jsonl"
printf '%s\n' '{"id":"child","role":"assistant","content":"child"}' > \
  "$CHAT_GRAPH_CLAUDE_ROOT/project/$PARENT47/subagents/agent-child.jsonl"
touch "$CHAT_GRAPH_CLAUDE_ROOT/project/$PARENT47/subagents/agent-child.jsonl"
if python3 - "$HERE/chat-graph" "$CHAT_GRAPH_CLAUDE_ROOT/project/$PARENT47.jsonl" <<'PYEOF'
import importlib.machinery,importlib.util,os,sys
sys.path.insert(0,os.path.dirname(sys.argv[1]))
l=importlib.machinery.SourceFileLoader("chat_graph_enum",sys.argv[1]); s=importlib.util.spec_from_loader(l.name,l)
cg=importlib.util.module_from_spec(s); l.exec_module(cg)
rows=[r for r in cg._enumerate_files() if r[1]=="claude" and r[2].startswith("77777777")]
assert len(rows)==1 and rows[0][0]==sys.argv[2], rows
PYEOF
then pass "Claude subagent transcript cannot replace parent session source"
else fail "Claude parent/subagent enumeration"; fi

CURSOR_PARENT47="79797979-7979-4797-8797-797979797979"
mkdir -p "$CHAT_GRAPH_CURSOR_ROOT/project/$CURSOR_PARENT47/subagents"
printf '%s\n' '{"id":"cursor-parent","role":"assistant","content":"parent"}' > \
  "$CHAT_GRAPH_CURSOR_ROOT/project/$CURSOR_PARENT47.jsonl"
printf '%s\n' '{"id":"cursor-child","role":"assistant","content":"child"}' > \
  "$CHAT_GRAPH_CURSOR_ROOT/project/$CURSOR_PARENT47/subagents/agent-child.jsonl"
touch "$CHAT_GRAPH_CURSOR_ROOT/project/$CURSOR_PARENT47/subagents/agent-child.jsonl"
if python3 - "$HERE/chat-graph" "$CHAT_GRAPH_CURSOR_ROOT/project/$CURSOR_PARENT47.jsonl" <<'PYEOF'
import importlib.machinery,importlib.util,os,sys
sys.path.insert(0,os.path.dirname(sys.argv[1]))
l=importlib.machinery.SourceFileLoader("chat_graph_cursor_enum",sys.argv[1])
s=importlib.util.spec_from_loader(l.name,l); cg=importlib.util.module_from_spec(s); l.exec_module(cg)
rows=[r for r in cg._enumerate_files() if r[1]=="cursor" and r[2].startswith("79797979")]
assert len(rows)==1 and rows[0][0]==sys.argv[2], rows
PYEOF
then pass "Cursor subagent transcript cannot replace parent session source"
else fail "Cursor parent/subagent enumeration"; fi

# --- 48. provider-native transcript stores persist allowlisted cards --------
new_env
mkdir -p "$CHAT_GRAPH_CURSOR_ROOT/project" "$CHAT_GRAPH_HERMES_ROOT" \
         "$CHAT_GRAPH_COPILOT_ROOT/88888888-8888-4888-8888-888888888888"
cat > "$CHAT_GRAPH_CURSOR_ROOT/project/99999999-9999-4999-8999-999999999999.jsonl" <<'JSONL'
{"id":"cursor48","role":"assistant","type":"assistant","content":"Outcome\nCursor closeout parsed.\nStatus: complete"}
JSONL
python3 - "$CHAT_GRAPH_HERMES_STATE_DB" <<'PYEOF'
import sqlite3,sys,time
c=sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE sessions(id TEXT PRIMARY KEY,title TEXT,cwd TEXT,started_at REAL)")
c.execute("""CREATE TABLE messages(id INTEGER PRIMARY KEY,session_id TEXT,role TEXT,
 content TEXT,timestamp REAL,active INTEGER)""")
c.execute("INSERT INTO sessions VALUES(?,?,?,?)",
          ("20260709_123456_abcdef","Hermes fixture","/tmp",time.time()))
c.execute("INSERT INTO messages VALUES(?,?,?,?,?,1)",
          (1,"20260709_123456_abcdef","assistant",
           "Outcome\nHermes closeout parsed.\nStatus: complete",time.time()))
c.commit()
PYEOF
cat > "$CHAT_GRAPH_COPILOT_ROOT/88888888-8888-4888-8888-888888888888/events.jsonl" <<'JSONL'
{"type":"assistant.message","data":{"content":"Outcome\nCopilot closeout parsed.\nStatus: complete"}}
JSONL
"$CG" ingest --full >/dev/null 2>&1
ok 1 "$(q "SELECT COUNT(*) FROM session_outcomes WHERE provider='cursor'")" \
   "Cursor transcript store persists Tier 1 card"
ok 1 "$(q "SELECT COUNT(*) FROM session_outcomes WHERE provider='hermes'")" \
   "Hermes state.db store persists Tier 1 card"
ok 1 "$(q "SELECT COUNT(*) FROM session_outcomes WHERE provider='copilot'")" \
   "Copilot assistant.message store persists Tier 1 card"

# A message committed after the pinned Hermes high-water belongs to the next
# ingest; the first ingest must not advance its cursor past that unseen row.
if python3 - "$HERE/chat-graph" "$CHAT_GRAPH_HERMES_STATE_DB" <<'PYEOF'
import importlib.machinery,importlib.util,os,sqlite3,sys,time
tool,db=sys.argv[1:]
writer=sqlite3.connect(db); writer.execute("PRAGMA journal_mode=WAL"); writer.close()
sys.path.insert(0,os.path.dirname(tool))
l=importlib.machinery.SourceFileLoader("chat_graph_hermes_race",tool)
s=importlib.util.spec_from_loader(l.name,l); cg=importlib.util.module_from_spec(s); l.exec_module(cg)
con=cg.connect()
con.execute("DELETE FROM session_outcomes WHERE provider='hermes'")
con.execute("DELETE FROM session_outcome_observations WHERE session_id LIKE 'hermes-race-%'")
con.execute("DELETE FROM sessions WHERE id LIKE 'hermes-race-%'")
con.execute("DELETE FROM meta WHERE key='hermes_message_cursor'"); con.commit()
source=sqlite3.connect(db)
source.execute("DELETE FROM messages"); source.execute("DELETE FROM sessions")
source.execute("INSERT INTO sessions VALUES(?,?,?,?)",("hermes-race-1","One","/tmp",time.time()))
source.execute("INSERT INTO messages VALUES(?,?,?,?,?,1)",(1,"hermes-race-1","assistant",
 "Outcome\nFirst snapshot.\nStatus: complete",time.time()))
source.commit(); source.close()
real_connect=cg.sqlite3.connect; injected=[False]
def hooked_connect(*args,**kwargs):
    c=real_connect(*args,**kwargs)
    if args and str(args[0]).startswith("file:"):
        def trace(sql):
            if not injected[0] and "SELECT DISTINCT session_id" in sql:
                injected[0]=True
                w=real_connect(db)
                w.execute("INSERT INTO sessions VALUES(?,?,?,?)",("hermes-race-2","Two","/tmp",time.time()))
                w.execute("INSERT INTO messages VALUES(?,?,?,?,?,1)",(2,"hermes-race-2","assistant",
                 "Outcome\nSecond snapshot.\nStatus: complete",time.time()))
                w.commit(); w.close()
        c.set_trace_callback(trace)
    return c
cg.sqlite3.connect=hooked_connect
try:
    assert cg._scan_hermes_state(con,full=True)==1
finally:
    cg.sqlite3.connect=real_connect
con.commit()
assert cg._get_meta(con,"hermes_message_cursor")=="1"
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id='hermes-race-2'").fetchone()[0]==0
assert cg._scan_hermes_state(con,full=False)==1
con.commit()
assert cg._get_meta(con,"hermes_message_cursor")=="2"
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id='hermes-race-2'").fetchone()[0]==1
# Replace the source corpus with lower/reused IDs. The stored cursor anchor must
# force a rebuild and ingest the restored session instead of skipping it.
w=real_connect(db)
w.execute("DELETE FROM messages"); w.execute("DELETE FROM sessions")
w.execute("INSERT INTO sessions VALUES(?,?,?,?)",("hermes-restored","Restored","/tmp",time.time()))
w.execute("INSERT INTO messages VALUES(?,?,?,?,?,1)",(1,"hermes-restored","assistant",
 "Outcome\nRestored snapshot.\nStatus: complete",time.time()))
w.commit(); w.close()
assert cg._scan_hermes_state(con,full=False)==1
con.commit()
assert cg._get_meta(con,"hermes_message_cursor")=="1"
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id='hermes-restored'").fetchone()[0]==1
con.close()
PYEOF
then pass "Hermes pinned high-water handles concurrency and source reset"
else fail "Hermes incremental high-water race"; fi

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
