#!/bin/bash
# Transactional decision queue tests. Synthetic state and stub sender only.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/scripts/decision-alert"
FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export MISSION_CONTROL_HOME="$T/state"
export DECISION_ALERT_NOW_EPOCH=1783674000
mkdir -p "$MISSION_CONTROL_HOME"

run_json(){ "$TOOL" "$@" --json; }

# Privacy is field-aware and fail-closed before any decision data is stored.
if ! run_json ingest --source-kind chat --source-key unsafe --text \
  'email owner@example.com' --trust structured --provenance synthetic >"$T/unsafe.out" 2>"$T/unsafe.err"; then
  pass "sensitive decision text fails closed"
else fail "sensitive decision text fails closed"; fi
if ! run_json ingest --source-kind chat --source-key bad-trust --text safe \
  --trust owner@example.com --provenance synthetic >"$T/parser.out" 2>"$T/parser.err" &&
   ! grep -Fq 'owner@example.com' "$T/parser.out" "$T/parser.err"; then
  pass "parser errors do not echo rejected argument content"
else fail "parser errors do not echo rejected argument content"; fi

# Stable identity, duplicate-ingest idempotence, trust split, and action policy.
ONE="$(run_json ingest --source-kind git --source-key repo-a:branch-a \
  --text 'Choose whether to merge branch A' --evidence 'branch-a head 111' \
  --trust structured --provenance git-facts --resolution-key merge:branch-a \
  --action-json '["git","merge","branch-a"]')" || ONE=""
ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$ONE" 2>/dev/null || true)"
TWO="$(run_json ingest --source-kind git --source-key repo-a:branch-a \
  --text 'Choose whether to merge branch A' --evidence 'branch-a head 111' \
  --trust structured --provenance git-facts --resolution-key merge:branch-a \
  --action-json '["git","merge","branch-a"]')" || TWO=""
if [ -n "$ID" ] && python3 - "$ONE" "$TWO" <<'PY'
import json,sys
a,b=map(json.loads,sys.argv[1:])
assert a["decision"]["id"] == b["decision"]["id"]
assert a["event_created"] is True and b["event_created"] is False
assert b["decision"]["state"] == "open"
assert b["decision"]["action_argv"] == ["git","merge","branch-a"]
PY
then pass "stable identity and duplicate ingest are idempotent"
else fail "stable identity and duplicate ingest are idempotent"; fi

INF="$(run_json ingest --source-kind model --source-key maybe-1 \
  --text 'Maybe choose a deployment region' --evidence 'model only' \
  --trust inferred --provenance tier2)" || INF=""
if python3 - "$INF" <<'PY'
import json,sys
d=json.loads(sys.argv[1])["decision"]
assert d["trust"] == "inferred" and d["action_argv"] is None
PY
then pass "inferred decisions are stored without actions"
else fail "inferred decisions are stored without actions"; fi
if ! run_json ingest --source-kind model --source-key maybe-bad \
  --text 'Maybe deploy' --trust inferred --provenance tier2 \
  --action-json '["deploy"]' >"$T/inferred-action.out" 2>"$T/inferred-action.err"; then
  pass "inferred decisions reject action commands"
else fail "inferred decisions reject action commands"; fi
if ! run_json ingest --source-kind manual --source-key unsafe-action \
  --text 'Choose safe command' --trust structured --provenance manual \
  --action-json '["deploy","sk-abcdefghijklmnopqrstuvwxyz123456"]' \
  >"$T/unsafe-action.out" 2>"$T/unsafe-action.err"; then
  pass "sensitive action argv fails closed"
else fail "sensitive action argv fails closed"; fi
if ! run_json ingest --source-kind model --source-key unanchored \
  --text 'Choose model recommendation' --trust structured \
  --provenance tier2 >"$T/unanchored.out" 2>"$T/unanchored.err"; then
  pass "model-derived confirmed decision requires deterministic anchor"
else fail "model-derived confirmed decision requires deterministic anchor"; fi
if ! run_json ingest --source-kind outcome-tier2 --source-key disguised-model \
  --text 'Choose disguised model recommendation' --trust structured \
  --provenance tier2 >"$T/disguised-model.out" 2>"$T/disguised-model.err"; then
  pass "model-derived confirmation cannot bypass anchor with a compound origin"
else fail "model-derived confirmation cannot bypass anchor with a compound origin"; fi
if ! run_json ingest --source-kind chat --source-key spaced-model-origin \
  --text 'Choose spaced model recommendation' --trust structured \
  --provenance 'assistant model output' >"$T/spaced-model.out" 2>"$T/spaced-model.err"; then
  pass "model provenance cannot bypass anchor with whitespace boundaries"
else fail "model provenance cannot bypass anchor with whitespace boundaries"; fi
if ! run_json ingest --source-kind chat --source-key unlisted-model-origin \
  --text 'Maybe choose deployment' --trust structured \
  --provenance 'claude inference' >"$T/unlisted-model.out" 2>"$T/unlisted-model.err"; then
  pass "unlisted structured provenance fails closed without an anchor"
else fail "unlisted structured provenance bypassed the closed origin contract"; fi
ANCHORED="$(run_json ingest --source-kind model --source-key anchored \
  --text 'Choose anchored recommendation' --trust structured \
  --provenance tier2 --anchor git-fact:repo-a:111)" || ANCHORED=""
if python3 - "$ANCHORED" <<'PY'
import json,sys
d=json.loads(sys.argv[1])["decision"]
assert d["trust"] == "structured" and d["anchor_ref"] == "git-fact:repo-a:111"
PY
then pass "deterministically anchored model decision may be confirmed"
else fail "deterministically anchored model decision may be confirmed"; fi

# Absence/generic completion cannot resolve; exact evidence or manual resolution can.
if ! run_json resolve "$ID" --evidence-type downstream_resolution_key \
  --evidence-ref child:turn-9 --resolution-key wrong:key >"$T/wrong.out" 2>"$T/wrong.err"; then
  pass "wrong downstream key cannot resolve"
else fail "wrong downstream key cannot resolve"; fi
OPEN="$(run_json list --state open)" || OPEN=""
if python3 - "$OPEN" "$ID" <<'PY'
import json,sys
assert sys.argv[2] in [d["id"] for d in json.loads(sys.argv[1])["decisions"]]
PY
then pass "decision remains open after non-exact evidence"
else fail "decision remains open after non-exact evidence"; fi
if ! run_json resolve "$ID" --evidence-type downstream_resolution_key \
  --evidence-ref unverified-random-string --resolution-key merge:branch-a \
  >"$T/unverified.out" 2>"$T/unverified.err"; then
  pass "matching caller-supplied key without graph evidence cannot resolve"
else fail "matching caller-supplied key without graph evidence cannot resolve"; fi
export CHAT_GRAPH_DB="$T/graph.db"
python3 - "$CHAT_GRAPH_DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute('''CREATE TABLE open_ends(
  item_key TEXT, resolved_at INTEGER, resolution_evidence_type TEXT,
  resolution_evidence_ref TEXT)''')
c.execute("INSERT INTO open_ends VALUES(?,?,?,?)",
          ("merge:branch-a",1783673999,"answering_user_turn","parent:turn-10"))
c.commit()
PY
RES="$(run_json resolve "$ID" --evidence-type answering_user_turn \
  --evidence-ref parent:turn-10 --resolution-key merge:branch-a)" || RES=""
if python3 - "$RES" <<'PY'
import json,sys
d=json.loads(sys.argv[1])["decision"]
assert d["state"] == "resolved"
assert d["resolution"]["evidence_type"] == "answering_user_turn"
PY
then pass "exact answering-turn evidence resolves decision"
else fail "exact answering-turn evidence resolves decision"; fi

# New evidence after resolution is recurrence; duplicate recurrence is idempotent.
REC="$(run_json ingest --source-kind git --source-key repo-a:branch-a \
  --text 'Choose whether to merge branch A' --evidence 'branch-a head 222' \
  --trust structured --provenance git-facts --resolution-key merge:branch-a \
  --action-json '["git","merge","branch-a"]')" || REC=""
REC2="$(run_json ingest --source-kind git --source-key repo-a:branch-a \
  --text 'Choose whether to merge branch A' --evidence 'branch-a head 222' \
  --trust structured --provenance git-facts --resolution-key merge:branch-a \
  --action-json '["git","merge","branch-a"]')" || REC2=""
if python3 - "$REC" "$REC2" <<'PY'
import json,sys
a,b=map(json.loads,sys.argv[1:])
assert a["decision"]["state"] == "open" and a["decision"]["recurrence_count"] == 1
assert a["event_type"] == "recurrence" and b["event_created"] is False
PY
then pass "new evidence reopens as one recurrence"
else fail "new evidence reopens as one recurrence"; fi

# Dismissal persists for the same fingerprint and recurs on changed evidence.
DIS="$(run_json dismiss "$ID" --reason 'not actionable today')" || DIS=""
SAME="$(run_json ingest --source-kind git --source-key repo-a:branch-a \
  --text 'Choose whether to merge branch A' --evidence 'branch-a head 222' \
  --trust structured --provenance git-facts --resolution-key merge:branch-a \
  --action-json '["git","merge","branch-a"]')" || SAME=""
if python3 - "$DIS" "$SAME" <<'PY'
import json,sys
a,b=map(json.loads,sys.argv[1:])
assert a["decision"]["state"] == "dismissed"
assert b["decision"]["state"] == "dismissed" and b["event_created"] is False
PY
then pass "dismissal persists for unchanged evidence"
else fail "dismissal persists for unchanged evidence"; fi
NEW="$(run_json ingest --source-kind git --source-key repo-a:branch-a \
  --text 'Choose whether to merge branch A' --evidence 'branch-a head 333' \
  --trust structured --provenance git-facts --resolution-key merge:branch-a \
  --action-json '["git","merge","branch-a"]')" || NEW=""
if python3 - "$NEW" <<'PY'
import json,sys
d=json.loads(sys.argv[1])["decision"]
assert d["state"] == "open" and d["recurrence_count"] == 2
PY
then pass "changed evidence reopens dismissed decision"
else fail "changed evidence reopens dismissed decision"; fi
PRESERVED="$(run_json history "$ID")" || PRESERVED=""
if python3 - "$PRESERVED" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
assert len(x["evidence_history"]) == 3
assert any(e["event_type"]=="resolved" and e["evidence_type"]=="answering_user_turn"
           for e in x["events"])
assert any(e["event_type"]=="dismissed" and e["detail"]=={"reason":"not actionable today"}
           for e in x["events"])
PY
then pass "recurrence preserves resolution, dismissal, and evidence history"
else fail "recurrence preserves resolution, dismissal, and evidence history"; fi

# Dismiss changes queue state only; it cannot execute the stored action argv.
NO_ACTION_MARKER="$T/action-must-not-run"
ACTION_ONLY="$(run_json ingest --source-kind manual --source-key action-only \
  --text 'Choose whether to create marker' --evidence 'manual request v1' \
  --trust structured --provenance manual \
  --action-json '["touch","'$NO_ACTION_MARKER'"]')" || ACTION_ONLY=""
ACTION_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$ACTION_ONLY")"
run_json dismiss "$ACTION_ID" --reason 'operator dismissed' >/dev/null
if [ ! -e "$NO_ACTION_MARKER" ]; then pass "dismiss never executes stored action argv"
else fail "dismiss never executes stored action argv"; fi

# Default alert is a no-side-effect preview; fixed-argv stub sends only confirmed open.
SENDER="$T/sender.py"; CAPTURE="$T/send.json"
cat > "$SENDER" <<'PY'
#!/usr/bin/env python3
import fcntl,json,os,sys,time
p=os.environ["DECISION_SEND_CAPTURE"]
with open(p,"a+") as handle:
    fcntl.flock(handle,fcntl.LOCK_EX)
    handle.seek(0)
    try: rows=json.load(handle)
    except Exception: rows=[]
    rows.append(sys.argv[1:])
    handle.seek(0); handle.truncate(); json.dump(rows,handle); handle.flush()
if os.environ.get("DECISION_SEND_FAIL") == "1": sys.exit(4)
sys.exit(0)
PY
chmod +x "$SENDER"
export DECISION_ALERT_SEND_BIN="$SENDER" DECISION_ALERT_CHAT_ID=12345 DECISION_SEND_CAPTURE="$CAPTURE"
PREVIEW="$(run_json alert)" || PREVIEW=""
if [ ! -e "$CAPTURE" ] && python3 - "$PREVIEW" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); assert x["mode"] == "preview" and x["eligible_count"] >= 1
PY
then pass "alert defaults to no external send"
else fail "alert defaults to no external send"; fi
SENT="$(run_json alert --send)" || SENT=""
AGAIN="$(run_json alert --send)" || AGAIN=""
if python3 - "$SENT" "$AGAIN" "$CAPTURE" "$ID" <<'PY'
import json,sys
a,b=map(json.loads,sys.argv[1:3]); calls=json.load(open(sys.argv[3]))
assert a["sent_count"] >= 1 and b["sent_count"] == 0
assert all(len(args)==3 and args[0]=="send" and args[1]=="12345" for args in calls)
assert all("dismiss " in args[2] for args in calls)
assert all("Maybe choose" not in args[2] for args in calls)
PY
then pass "successful alerts are fixed-argv, filtered, and deduplicated"
else fail "successful alerts are fixed-argv, filtered, and deduplicated"; fi

# A failed send is observed but never stamped as a successful receipt.
FAIL_DEC="$(run_json ingest --source-kind automation --source-key failed-job \
  --text 'Decide whether to repair failed job' --evidence 'exit 9' \
  --trust structured --provenance automation-status)" || FAIL_DEC=""
FAIL_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$FAIL_DEC")"
export DECISION_SEND_FAIL=1
if ! run_json alert --send >"$T/fail-send.out" 2>"$T/fail-send.err"; then :; fi
unset DECISION_SEND_FAIL
HISTORY="$(run_json history "$FAIL_ID")" || HISTORY=""
if python3 - "$HISTORY" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); kinds=[e["event_type"] for e in x["events"]]
assert "alert_failure" in kinds and x["decision"]["alert_receipt"] is None
PY
then pass "failed send is observable and not stamped alerted"
else fail "failed send is observable and not stamped alerted"; fi
RETRY="$(run_json alert --send)" || RETRY=""
if python3 - "$RETRY" "$FAIL_ID" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); assert sys.argv[2] in x["sent"]
PY
then pass "failed alert retries after the sender recovers"
else fail "failed alert retries after the sender recovers"; fi

# A crashed reservation is a short lease, not a 24-hour false receipt.
STALE="$(run_json ingest --source-kind automation --source-key stale-reservation \
  --text 'Decide stale reservation' --evidence 'new failure' \
  --trust structured --provenance automation-status)" || STALE=""
STALE_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$STALE")"
python3 - "$MISSION_CONTROL_HOME/decisions/decisions.db" "$STALE_ID" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1]); row=c.execute(
  "SELECT evidence_fingerprint FROM decisions WHERE decision_id=?",(sys.argv[2],)).fetchone()
c.execute("INSERT INTO alert_attempts VALUES(?,?,?,?,?,?)",
          ("alert:stale-reservation",sys.argv[2],row[0],1783673900,"reserved",None))
c.commit()
PY
STALE_RETRY="$(run_json alert --send)" || STALE_RETRY=""
if python3 - "$STALE_RETRY" "$STALE_ID" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); assert sys.argv[2] in x["sent"]
PY
then pass "stale crashed reservation becomes retryable"
else fail "stale crashed reservation becomes retryable"; fi

# Restart persistence and rolling 24-hour dedupe.
export DECISION_ALERT_NOW_EPOCH=1783760399
EARLY="$(run_json alert --send)" || EARLY=""
export DECISION_ALERT_NOW_EPOCH=1783760401
LATE="$(run_json alert --send)" || LATE=""
if python3 - "$EARLY" "$LATE" <<'PY'
import json,sys
a,b=map(json.loads,sys.argv[1:]); assert a["sent_count"] == 0 and b["sent_count"] >= 1
PY
then pass "restart preserves rolling 24-hour alert dedupe"
else fail "restart preserves rolling 24-hour alert dedupe"; fi

# Concurrent duplicate ingest is one observation and concurrent alerts emit once.
export DECISION_ALERT_NOW_EPOCH=1783846802
for i in $(seq 1 12); do
  run_json sync --source-kind chat --source-key concurrent \
    --text 'Choose concurrency option' --evidence 'same evidence' \
    --trust structured --provenance 'chat-graph tier1' >"$T/ingest.$i" 2>"$T/ingest.$i.err" &
done
wait
CID="$(python3 -c 'import json; print(json.load(open("'$T'/ingest.1"))["decision"]["id"])')"
BEFORE="$(python3 -c 'import json,sys; print(sum(sys.argv[2] in row[2] for row in json.load(open(sys.argv[1]))))' "$CAPTURE" "$CID")"
for i in $(seq 1 8); do run_json alert --send >"$T/alert.$i" 2>"$T/alert.$i.err" & done
wait
AFTER="$(python3 -c 'import json,sys; print(sum(sys.argv[2] in row[2] for row in json.load(open(sys.argv[1]))))' "$CAPTURE" "$CID")"
CH="$(run_json history "$CID")" || CH=""
if [ $((AFTER-BEFORE)) -eq 1 ] && python3 - "$CH" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); observed=[e for e in x["events"] if e["event_type"]=="observed"]
success=[e for e in x["events"] if e["event_type"]=="alert_success"]
assert len(observed)==1 and len(success)==1
PY
then pass "concurrent sync/ingest and alerts stay idempotent"
else fail "concurrent sync/ingest and alerts stay idempotent"; fi

# Concurrent dismiss/ingest/alert leaves a valid auditable state and no duplicate receipt.
export DECISION_ALERT_NOW_EPOCH=1783933203
run_json ingest --source-kind chat --source-key race \
  --text 'Choose race option' --evidence 'race-v1' \
  --trust structured --provenance 'chat-graph tier1' >"$T/race.json"
RID="$(python3 -c 'import json; print(json.load(open("'$T'/race.json"))["decision"]["id"])')"
run_json dismiss "$RID" --reason concurrent >"$T/race-dismiss" 2>"$T/race-dismiss.err" & A=$!
run_json ingest --source-kind chat --source-key race \
  --text 'Choose race option' --evidence 'race-v1' \
  --trust structured --provenance 'chat-graph tier1' >"$T/race-ingest" 2>"$T/race-ingest.err" & B=$!
run_json alert --send >"$T/race-alert" 2>"$T/race-alert.err" & C=$!
wait "$A"; wait "$B"; wait "$C" || true
RACE="$(run_json history "$RID")" || RACE=""
if python3 - "$RACE" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); d=x["decision"]
assert d["state"] == "dismissed"
assert sum(e["event_type"]=="alert_success" for e in x["events"]) <= 1
PY
then pass "concurrent dismiss, ingest, and alert preserve valid state"
else fail "concurrent dismiss, ingest, and alert preserve valid state"; fi

# Dashboard sync consumes only deterministic Tier-1 NEEDS-YOU items and omission
# never resolves them.
mkdir -p "$MISSION_CONTROL_HOME/data"
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
item={"item_key":"a"*40,"section":"needs_you","text":"Choose the rollout window"}
card={"card_id":"b"*40,"session_id":"session-safe","tail_hash":"c"*40,
      "method":"tier1","open_work":[item]}
json.dump({"schema":1,"data":{"outcomes":[card]}},open(sys.argv[1],"w"))
PY
SYNCED="$(run_json sync-snapshot)" || SYNCED=""
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
json.dump({"schema":1,"data":{"outcomes":[]}},open(sys.argv[1],"w"))
PY
OMITTED="$(run_json sync-snapshot)" || OMITTED=""
python3 - "$CHAT_GRAPH_DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute("INSERT INTO open_ends VALUES(?,?,?,?)",
          ("a"*40,1783933204,"downstream_explicit","child-session"))
c.commit()
PY
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
change={"item_key":"a"*40,"change_type":"resolved",
        "resolution_evidence_type":"downstream_explicit",
        "resolution_evidence_ref":"child-session"}
json.dump({"schema":1,"data":{"outcomes":[],"loose_end_changes":[change]}},
          open(sys.argv[1],"w"))
PY
PROVEN="$(run_json sync-snapshot)" || PROVEN=""
if python3 - "$SYNCED" "$OMITTED" "$PROVEN" <<'PY'
import json,sys
a,b,c=map(json.loads,sys.argv[1:])
match=[d for d in a["data"]["pinned"] if d["source_key"].startswith("outcome:session-safe:")]
match2=[d for d in b["data"]["pinned"] if d["source_key"].startswith("outcome:session-safe:")]
match3=[d for d in c["data"]["pinned"] if d["source_key"].startswith("outcome:session-safe:")]
assert len(match)==1 and len(match2)==1
assert a["data"]["sync"]["stored"]==1 and b["data"]["sync"]["stored"]==0
assert b["data"]["sync"]["omission_resolves"] is False
assert match3==[] and c["data"]["sync"]["resolved"]==1
PY
then pass "Tier-1 sync preserves omission but applies positive graph resolution"
else fail "Tier-1 sync omission/positive-resolution contract"; fi

# Feed/status shape pins confirmed open above inferred; DB uses WAL and private modes.
STATUS="$(run_json status)" || STATUS=""
if python3 - "$STATUS" "$MISSION_CONTROL_HOME/decisions/decisions.db" <<'PY'
import json,os,sqlite3,stat,sys
x=json.loads(sys.argv[1]); db=sys.argv[2]
assert x["schema"] == 1 and x["feed"] == "decisions"
assert x["ok"] is True and x["error"] is None and x["cadence_s"] == 300
assert all(d["trust"] == "structured" and d["state"] == "open" for d in x["data"]["pinned"])
assert all(d["trust"] == "inferred" for d in x["data"]["inferred"])
c=sqlite3.connect(db)
assert c.execute("PRAGMA journal_mode").fetchone()[0].lower()=="wal"
assert c.execute("PRAGMA integrity_check").fetchone()[0]=="ok"
assert stat.S_IMODE(os.stat(db).st_mode)==0o600
assert stat.S_IMODE(os.stat(os.path.dirname(db)).st_mode)==0o700
for path in (db,db+"-wal",db+"-shm"):
    if os.path.exists(path):
        assert stat.S_IMODE(os.stat(path).st_mode)==0o600
        raw=open(path,"rb").read()
        assert b"owner@example.com" not in raw
        assert b"sk-abcdefghijklmnopqrstuvwxyz123456" not in raw
PY
then pass "status feed, WAL, privacy, integrity, and private modes are valid"
else fail "status feed, WAL, privacy, integrity, and private modes are valid"; fi

printf '%s\n' '----'
if [ "$FAIL" -eq 0 ]; then echo 'ALL PASS'; exit 0; fi
echo "$FAIL FAILED"; exit 1
