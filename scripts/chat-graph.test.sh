#!/usr/bin/env bash
# chat-graph.test.sh — acceptance suite for scripts/chat-graph (ER-087 Part A core).
# bash-3.2 compatible; python3 stdlib only; mktemp fixtures only; no network; no real $HOME.
# One PASS:/FAIL: line per case; exit 0 only when all pass.
set -u

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
  export CHAT_GRAPH_CODING_ROOT="$(mktemp -d)"
  export CHAT_GRAPH_REPO_ROOTS="$(mktemp -d)"
  export CHAT_GRAPH_NIGHTLY_REPORT_GLOB="$(mktemp -d)/*.md"
  export CHAT_GRAPH_SCAN_CMD="/bin/echo []"
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
ok 5 "$(q "SELECT value FROM meta WHERE key='schema_version'")" \
   "v1 DB open migrates meta.schema_version to 5"
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
   "branches":[{"name":"old-work","age_days":12}]}
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

# --- 35. v4 -> v5 outcome/open-work migration is additive + idempotent -----
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
ok 5 "$(q "SELECT value FROM meta WHERE key='schema_version'")" \
   "v4 DB migrates to schema 5 exactly once"
ok 1 "$(q "SELECT COUNT(*) FROM open_ends WHERE text_hash='legacy-hash' AND text='finish it'")" \
   "v5 migration preserves the legacy open-end row"
ok repo "$(q "SELECT node_kind FROM sessions WHERE id='repo:alpha'")" \
   "migration backfills repo node_kind"
ok chat "$(q "SELECT node_kind FROM sessions WHERE id='CHAT35'")" \
   "migration backfills allowlisted chat node_kind"
ok 5 "$(q "SELECT COUNT(*) FROM pragma_table_info('open_ends') WHERE name IN ('item_key','updated_at','resolution_evidence_type','resolution_evidence_ref','last_change_type')")" \
   "v5 adds stable item/update/resolution fields"
ok 1 "$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='session_outcomes'")" \
   "v5 creates additive session_outcomes storage"

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

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
