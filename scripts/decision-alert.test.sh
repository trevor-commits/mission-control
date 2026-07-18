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

# Dashboard sync preserves deterministic Tier-1 NEEDS-YOU items through a
# Tier-2 wrapper and stores fixed-taxonomy Tier-2 needs as non-actionable
# inferred decisions. Omission resolves neither class.
mkdir -p "$MISSION_CONTROL_HOME/data"
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
item={"item_key":"a"*40,"section":"needs_you","text":"Choose the rollout window",
      "trust":"structured","source_method":"tier1"}
inferred={"item_key":"d"*40,"section":"needs_you","text":"Invented model decision"}
card={"card_id":"b"*40,"session_id":"session-safe","tail_hash":"c"*40,
      "method":"tier2","open_work":[item,inferred],"session_title":"Audit: cache safety",
      "repo":"mission-control",
      "inferred_needs_trevor_codes":["review_evidence"],
      "inferred_needs_trevor":["Trevor needs to review the evidence."]}
json.dump({"schema":1,"data":{"outcomes":[card]}},open(sys.argv[1],"w"))
PY
SYNCED="$(run_json sync-snapshot)" || SYNCED=""
rm -f "$MISSION_CONTROL_HOME/data/chats.json"
MISSING="$(run_json sync-snapshot)" || MISSING=""
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
item={"item_key":"a"*40,"section":"needs_you","text":"Choose the rollout window",
      "trust":"structured","source_method":"tier1"}
card={"card_id":"b"*40,"session_id":"session-safe","tail_hash":"e"*40,
      "method":"tier1","open_work":[item]}
json.dump({"schema":1,"data":{"outcomes":[card]}},open(sys.argv[1],"w"))
PY
ROLLED="$(run_json sync-snapshot)" || ROLLED=""
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
if python3 - "$SYNCED" "$MISSING" "$ROLLED" "$PROVEN" <<'PY'
import json,sys
a,m,b,c=map(json.loads,sys.argv[1:])
match=[d for d in a["data"]["pinned"] if d["source_key"].startswith("outcome:session-safe:")]
match_missing=[d for d in m["data"]["pinned"] if d["source_key"].startswith("outcome:session-safe:")]
match2=[d for d in b["data"]["pinned"] if d["source_key"].startswith("outcome:session-safe:")]
match3=[d for d in c["data"]["pinned"] if d["source_key"].startswith("outcome:session-safe:")]
inferred=[d for d in a["data"]["inferred"] if d["source_key"].startswith("outcome-inferred:session-safe:")]
inferred_missing=[d for d in m["data"]["inferred"] if d["source_key"].startswith("outcome-inferred:session-safe:")]
inferred2=[d for d in b["data"]["inferred"] if d["source_key"].startswith("outcome-inferred:session-safe:")]
assert len(match)==1 and len(match_missing)==1 and len(match2)==1
assert len(inferred)==1 and inferred[0]["action_argv"] is None
assert inferred[0]["text"].startswith("Audit: cache safety [mission-control] — ")
assert len(inferred_missing)==1 and inferred_missing[0]["state"]=="open"
assert len(inferred2)==1 and inferred2[0]["state"]=="resolved"
assert inferred2[0]["resolution"]["evidence_type"]=="tier2_supersession"
assert a["data"]["sync"]["stored"]==2 and m["data"]["sync"]["resolved"]==0, (a["data"]["sync"],m["data"]["sync"])
assert b["data"]["sync"]["stored"]==1
assert b["data"]["sync"]["resolved"]==1
assert b["data"]["sync"]["omission_resolves"] is False
assert b["data"]["sync"]["structured_omission_resolves"] is False
assert b["data"]["sync"]["inferred_exact_supersession_resolves"] is True
assert match3==[] and c["data"]["sync"]["resolved"]==1
PY
then pass "Tier-1 evidence persists while stale inferred Tier-2 needs supersede safely"
else fail "Tier-1 evidence in Tier-2 sync contract"; fi

# Provider/session rollback is local: one surviving Tier-2 provider cannot keep
# another provider's stale inferred decision open.
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
def card(sid,provider,tail,method="tier2",need=True):
    row={"card_id":sid+"-card","session_id":sid,"provider":provider,
         "tail_hash":tail,"method":method,"open_work":[],
         "session_title":"Audit: "+sid,"repo":"mission-control"}
    if method=="tier2":
        row["inferred_needs_trevor_codes"]=["review_evidence"] if need else []
        row["inferred_needs_trevor"]=["Trevor needs to review the evidence."] if need else []
    return row
json.dump({"schema":1,"data":{"outcomes":[
  card("provider-a","claude","1"*40),card("provider-b","codex","2"*40)]}},
  open(sys.argv[1],"w"))
PY
run_json sync-snapshot >/dev/null
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
a={"card_id":"a-card","session_id":"provider-a","provider":"claude",
   "tail_hash":"1"*40,"method":"tier2","open_work":[],
   "session_title":"Audit: provider-a","repo":"mission-control",
   "inferred_needs_trevor_codes":["review_evidence"],
   "inferred_needs_trevor":["Trevor needs to review the evidence."]}
b={"card_id":"b-card","session_id":"provider-b","provider":"codex",
   "tail_hash":"3"*40,"method":"tier1","open_work":[]}
json.dump({"schema":1,"data":{"outcomes":[a,b]}},open(sys.argv[1],"w"))
PY
MIXED="$(run_json sync-snapshot)" || MIXED=""
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
def card(sid,provider,tail):
    return {"card_id":sid+"-card","session_id":sid,"provider":provider,
      "tail_hash":tail,"method":"tier2","open_work":[],
      "session_title":"Audit: "+sid,"repo":"mission-control",
      "inferred_needs_trevor_codes":["review_evidence"],
      "inferred_needs_trevor":["Trevor needs to review the evidence."]}
json.dump({"schema":1,"data":{"outcomes":[
  card("provider-a","claude","1"*40),card("provider-b","codex","2"*40)]}},
  open(sys.argv[1],"w"))
PY
REENABLED="$(run_json sync-snapshot)" || REENABLED=""
if python3 - "$MIXED" "$REENABLED" <<'PY'
import json,sys
d=json.loads(sys.argv[1])["data"]["inferred"]
r=json.loads(sys.argv[2])["data"]["inferred"]
a=[r for r in d if r["source_key"].startswith("outcome-inferred:provider-a:")]
b=[r for r in d if r["source_key"].startswith("outcome-inferred:provider-b:")]
reopened=[row for row in r if row["source_key"].startswith("outcome-inferred:provider-b:")]
assert len(a)==1 and a[0]["state"]=="open"
assert len(b)==1 and b[0]["state"]=="resolved"
assert len(reopened)==1 and reopened[0]["state"]=="open"
assert reopened[0]["recurrence_count"]==1
PY
then pass "mixed-provider rollback and unchanged-cache re-enable are reversible"
else fail "mixed-provider inferred rollback"; fi

# Deterministic title/repo enrichment changes display text without changing the
# model evidence. It must not reopen a dismissal or manual resolution.
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
def card(sid,title):
    return {"card_id":sid+"-card","session_id":sid,"provider":"claude",
      "tail_hash":"9"*40,"method":"tier2","open_work":[],
      "session_title":title,"repo":"mission-control",
      "inferred_needs_trevor_codes":["review_evidence"],
      "inferred_needs_trevor":["Trevor needs to review the evidence."]}
json.dump({"schema":1,"data":{"outcomes":[
  card("context-dismiss","Audit: old title"),
  card("context-resolve","Audit: old title")] }},open(sys.argv[1],"w"))
PY
CONTEXT_FIRST="$(run_json sync-snapshot)" || CONTEXT_FIRST=""
python3 - "$CONTEXT_FIRST" "$T/context-ids" <<'PY'
import json,sys
rows=json.loads(sys.argv[1])["data"]["inferred"]
out=[]
for sid in ("context-dismiss","context-resolve"):
    row=next(r for r in rows if r["source_key"].startswith("outcome-inferred:%s:"%sid))
    out.append(row["id"])
open(sys.argv[2],"w").write("\n".join(out)+"\n")
PY
CONTEXT_DISMISS_ID="$(sed -n '1p' "$T/context-ids")"
CONTEXT_RESOLVE_ID="$(sed -n '2p' "$T/context-ids")"
run_json dismiss "$CONTEXT_DISMISS_ID" --reason "not needed" >/dev/null
run_json resolve "$CONTEXT_RESOLVE_ID" --evidence-type manual_resolution \
  --evidence-ref operator-reviewed >/dev/null
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
def card(sid):
    return {"card_id":sid+"-card","session_id":sid,"provider":"claude",
      "tail_hash":"a"*40,"method":"tier2","open_work":[],
      "session_title":"Audit: interim title","repo":"mission-control",
      "inferred_needs_trevor_codes":[],"inferred_needs_trevor":[]}
json.dump({"schema":1,"data":{"outcomes":[card("context-dismiss"),
  card("context-resolve")] }},open(sys.argv[1],"w"))
PY
run_json sync-snapshot >/dev/null
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json,sys
def card(sid):
    return {"card_id":sid+"-card","session_id":sid,"provider":"claude",
      "tail_hash":"9"*40,"method":"tier2","open_work":[],
      "session_title":"Audit: enriched title","repo":"global-implementations",
      "inferred_needs_trevor_codes":["review_evidence"],
      "inferred_needs_trevor":["Trevor needs to review the evidence."]}
json.dump({"schema":1,"data":{"outcomes":[card("context-dismiss"),
  card("context-resolve")] }},open(sys.argv[1],"w"))
PY
CONTEXT_SECOND="$(run_json sync-snapshot)" || CONTEXT_SECOND=""
if python3 - "$CONTEXT_SECOND" <<'PY'
import json,sys
rows=json.loads(sys.argv[1])["data"]["inferred"]
d=next(r for r in rows if r["source_key"].startswith("outcome-inferred:context-dismiss:"))
r=next(r for r in rows if r["source_key"].startswith("outcome-inferred:context-resolve:"))
assert d["state"]=="dismissed" and d["recurrence_count"]==0
assert r["state"]=="resolved" and r["recurrence_count"]==0
assert r["resolution"]["evidence_type"]=="manual_resolution"
assert "Audit: enriched title [global-implementations]" in d["text"]
assert "Audit: enriched title [global-implementations]" in r["text"]
PY
then pass "context enrichment preserves human inferred-decision dispositions"
else fail "context-only inferred decision recurrence"; fi

# Feed/status shape pins confirmed open above inferred; presentation is structured
# once at the producer boundary; DB uses WAL and private modes.
run_json ingest --source-kind manual --source-key presentation-contract \
  --text '**DECISION NEEDED:** Pick a release lane. **`Ship now`** (Recommended). **`Wait`**. **`Cancel`**.' \
  --trust structured --provenance manual >/dev/null
STATUS="$(run_json status)" || STATUS=""
if python3 - "$STATUS" "$MISSION_CONTROL_HOME/decisions/decisions.db" <<'PY'
import json,os,sqlite3,stat,sys
x=json.loads(sys.argv[1]); db=sys.argv[2]
assert x["schema"] == 1 and x["feed"] == "decisions"
assert x["ok"] is True and x["error"] is None and x["cadence_s"] == 300
assert all(d["trust"] == "structured" and d["state"] == "open" for d in x["data"]["pinned"])
assert all(d["trust"] == "inferred" for d in x["data"]["inferred"])
p=next(d for d in x["data"]["pinned"] if d["source_key"]=="presentation-contract")
assert p["question"] == "Pick a release lane."
assert p["options"] == ["Ship now", "Wait", "Cancel"]
assert p["recommended"] == 1
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


# Cap + newest-first + fresh-within keep ticker alerts bounded.
export DECISION_ALERT_NOW_EPOCH=1784019604
CAP_OLD="$(run_json ingest --source-kind git --source-key cap-old \
  --text 'Choose old capped decision' --evidence 'old' \
  --trust structured --provenance git-facts)" || CAP_OLD=""
export DECISION_ALERT_NOW_EPOCH=1784106005
CAP_NEW="$(run_json ingest --source-kind git --source-key cap-new \
  --text 'Choose new capped decision' --evidence 'new' \
  --trust structured --provenance git-facts)" || CAP_NEW=""
OLD_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$CAP_OLD")"
NEW_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$CAP_NEW")"
# Reset capture for a clean count.
: > "$CAPTURE"
CAP_SENT="$(run_json alert --send --newest-first --max 1)" || CAP_SENT=""
if python3 - "$CAP_SENT" "$NEW_ID" "$OLD_ID" "$CAPTURE" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); calls=json.load(open(sys.argv[4]))
assert x["sent_count"] == 1 and sys.argv[2] in x["sent"] and sys.argv[3] not in x["sent"]
assert x.get("attempted_count") == 1
assert any(sys.argv[2] in row[2] for row in calls)
PY
then pass "alert --max --newest-first sends only the newest eligible"
else fail "alert --max --newest-first sends only the newest eligible"; fi
FRESH="$(run_json alert --fresh-within 1)" || FRESH=""
if python3 - "$FRESH" "$OLD_ID" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
ids=[d["id"] for d in x.get("decisions") or []]
assert sys.argv[2] not in ids
assert x["eligible_count"] == len(ids)
PY
then pass "alert --fresh-within excludes older first_seen decisions"
else fail "alert --fresh-within excludes older first_seen decisions"; fi

# Mobile-connect config supplies chat id when env is unset.
unset DECISION_ALERT_CHAT_ID
cat > "$T/mc-config" <<'CFG'
ALLOWED_USER_ID=999888777
CFG
export MOBILE_CONNECT_CONFIG="$T/mc-config"
CFG_DEC="$(run_json ingest --source-kind git --source-key cfg-chat \
  --text 'Choose config-backed alert' --evidence 'cfg' \
  --trust structured --provenance git-facts)" || CFG_DEC=""
CFG_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$CFG_DEC")"
: > "$CAPTURE"
CFG_SENT="$(run_json alert --send --max 1 --newest-first)" || CFG_SENT=""
if python3 - "$CFG_SENT" "$CAPTURE" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); calls=json.load(open(sys.argv[2]))
assert x["sent_count"] == 1
assert any(args[1]=="999888777" for args in calls)
PY
then pass "alert chat id falls back to mobile-connect ALLOWED_USER_ID"
else fail "alert chat id falls back to mobile-connect ALLOWED_USER_ID"; fi
export DECISION_ALERT_CHAT_ID=12345
unset MOBILE_CONNECT_CONFIG



# Explicit alert-backfill: capped, newest-first, always sends, stamps receipts.
export DECISION_ALERT_NOW_EPOCH=1784192400
BF1="$(run_json ingest --source-kind git --source-key bf-old \
  --text 'Choose backfill old decision' --evidence 'bf-old' \
  --trust structured --provenance git-facts)" || BF1=""
export DECISION_ALERT_NOW_EPOCH=1784278800
BF2="$(run_json ingest --source-kind git --source-key bf-new \
  --text 'Choose backfill new decision' --evidence 'bf-new' \
  --trust structured --provenance git-facts)" || BF2=""
BF_OLD="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$BF1")"
BF_NEW="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$BF2")"
: > "$CAPTURE"
BF_SENT="$(run_json alert-backfill --max 1)" || BF_SENT=""
if python3 - "$BF_SENT" "$BF_NEW" "$BF_OLD" "$CAPTURE" <<'PY'
import json,sys,os,sqlite3
x=json.loads(sys.argv[1]); calls=json.load(open(sys.argv[4]))
assert x["mode"] == "backfill"
assert x["sent_count"] == 1 and sys.argv[2] in x["sent"] and sys.argv[3] not in x["sent"]
assert x.get("max") == 1
assert x.get("backfill_ceiling") == 25
assert x.get("fresh_within_s") is None
assert any(sys.argv[2] in row[2] for row in calls)
db=os.path.join(os.environ["MISSION_CONTROL_HOME"], "decisions", "decisions.db")
con=sqlite3.connect(db)
row=con.execute("SELECT 1 FROM alert_receipts WHERE decision_id=?", (sys.argv[2],)).fetchone()
assert row is not None
PY
then pass "alert-backfill --max sends newest-first and stamps receipt"
else fail "alert-backfill --max sends newest-first and stamps receipt"; fi
if ! run_json alert-backfill --max 26 >"$T/bf-ceiling.out" 2>"$T/bf-ceiling.err"; then
  if python3 - "$T/bf-ceiling.err" <<'PY'
import json,sys
err=json.loads(open(sys.argv[1]).read())
assert err.get("ok") is False and "ceiling" in str(err.get("error","")).lower()
PY
  then pass "alert-backfill refuses --max above hard ceiling"
  else fail "alert-backfill refuses --max above hard ceiling"; fi
else fail "alert-backfill refuses --max above hard ceiling"; fi
: > "$CAPTURE"
BF_DEF="$(run_json alert-backfill)" || BF_DEF=""
if python3 - "$BF_DEF" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
assert x["mode"] == "backfill"
assert x.get("max") == 10
assert x.get("backfill_default_max") == 10
assert x["sent_count"] >= 1
assert x["sent_count"] <= 10
PY
then pass "alert-backfill defaults to max 10 and sends"
else fail "alert-backfill defaults to max 10 and sends"; fi

# Text-GROUP re-ask suppression (0.3(b) gate): a NEW decision whose normalized
# text matches an already-alerted group must not re-present identically within
# 7 days — it folds silently; after the window it may present again.
GRP_HOME="$T/group-state"; mkdir -p "$GRP_HOME"
export MISSION_CONTROL_HOME="$GRP_HOME"
export DECISION_ALERT_NOW_EPOCH=1784365200
G1="$(run_json ingest --source-kind git --source-key grp-first \
  --text 'Choose the identical group question' --evidence 'grp-a' \
  --trust structured --provenance git-facts)" || G1=""
G1_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$G1")"
: > "$CAPTURE"
G_FIRST="$(run_json alert --send)" || G_FIRST=""
export DECISION_ALERT_NOW_EPOCH=1784368800
G2="$(run_json ingest --source-kind git --source-key grp-second \
  --text 'Choose the identical group question' --evidence 'grp-b' \
  --trust structured --provenance git-facts)" || G2=""
G2_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$G2")"
G_SECOND="$(run_json alert --send)" || G_SECOND=""
export DECISION_ALERT_NOW_EPOCH=1784970011
G_EXPIRED="$(run_json alert --send)" || G_EXPIRED=""
if python3 - "$G_FIRST" "$G_SECOND" "$G_EXPIRED" "$G1_ID" "$G2_ID" <<'PY'
import json,sys
first,second,expired=map(json.loads,sys.argv[1:4])
g1,g2=sys.argv[4],sys.argv[5]
assert g1 in first["sent"]
# The identically-worded NEW row is suppressed, visibly and with provenance.
assert second["sent_count"] == 0 and g2 not in second["sent"]
sup={s["id"]: s for s in second.get("suppressed_group") or []}
assert g2 in sup and sup[g2]["reason"] == "group_repeat_within_7d"
assert sup[g2]["prior_alerted"] == g1
# Past the 7-day window the group may present again (fold, not permanent mute).
assert g2 in expired["sent"]
PY
then pass "group re-ask: identical new row is suppressed within 7 days, expires after"
else fail "group re-ask: identical new row is suppressed within 7 days, expires after"; fi

# Escalate path: a new group member whose stored severity outranks the alerted
# peer IS allowed through, and the escalation is recorded as an event.
ESC_HOME="$T/esc-state"; mkdir -p "$ESC_HOME"
export MISSION_CONTROL_HOME="$ESC_HOME"
export MISSION_CONTROL_ADMISSION_SCHEMA=1
export DECISION_ALERT_NOW_EPOCH=1784365200
E1="$(run_json ingest --source-kind git --source-key esc-first \
  --text 'Handle the repeated escalation question' --evidence 'esc-a' \
  --trust structured --provenance git-facts)" || E1=""
E1_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$E1")"
: > "$CAPTURE"
run_json alert --send >/dev/null 2>&1
export DECISION_ALERT_NOW_EPOCH=1784368800
E2="$(run_json ingest --source-kind git --source-key esc-second \
  --text 'Handle the repeated escalation question' --evidence 'esc-b' \
  --trust structured --provenance git-facts)" || E2=""
E2_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$E2")"
# Simulate an urgency-raising re-ask (e.g. a future channel writer stamping
# severity up without changing the text) directly on the stored column.
python3 - "$ESC_HOME/decisions/decisions.db" "$E2_ID" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute("UPDATE decisions SET severity='security' WHERE decision_id=?",(sys.argv[2],))
c.commit()
PY
E_SEND="$(run_json alert --send)" || E_SEND=""
E_HIST="$(run_json history "$E2_ID")" || E_HIST=""
if python3 - "$E_SEND" "$E_HIST" "$E1_ID" "$E2_ID" <<'PY'
import json,sys
send,hist=map(json.loads,sys.argv[1:3])
e1,e2=sys.argv[3],sys.argv[4]
assert e2 in send["sent"]
assert e2 in (send.get("escalated") or [])
events=[e for e in hist["events"] if e["event_type"]=="group_escalation"]
assert len(events) == 1
assert events[0]["evidence_type"] == "severity_increase"
assert events[0]["evidence_ref"] == e1
PY
then pass "group re-ask: severity escalation is allowed through and recorded"
else fail "group re-ask: severity escalation is allowed through and recorded"; fi
unset MISSION_CONTROL_ADMISSION_SCHEMA
export MISSION_CONTROL_HOME="$T/state"

printf '%s\n' '----'
if [ "$FAIL" -eq 0 ]; then echo 'ALL PASS'; exit 0; fi
echo "$FAIL FAILED"; exit 1
