#!/bin/bash
# Delivery receipt/idempotence tests. Synthetic feeds and stub sender only.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIEF="$ROOT/scripts/morning-brief"
FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" MISSION_CONTROL_HOME="$T/state" MORNING_BRIEF_NOW_EPOCH=1783674000
export MORNING_BRIEF_CHUNK_BYTES=240
mkdir -p "$MISSION_CONTROL_HOME/data" "$HOME"

python3 - "$MISSION_CONTROL_HOME/data" <<'PY'
import json, os, sys, time
root=sys.argv[1]; now=1783674000
def w(name,data,cadence):
    json.dump({"schema":1,"feed":name,"generated_epoch":now,"generated_at":"2026-07-10T09:00:00Z",
               "cadence_s":cadence,"ok":True,"error":None,"data":data},
              open(os.path.join(root,name+".json"),"w"))
w("automation",{"jobs":[],"counts":{"red":0,"green":1}},300)
w("usage",{"providers":[{"provider":"codex","window":"weekly","used_pct":42,"confidence":"live"}]},1800)
w("git",{"repos":[{"repo":"mission-control","branch":"codex/morning-brief","remote":"synced",
   "dirty":False,"ahead":0,"behind":0,"recent_commits":[{"sha":"a"*40,"epoch":now-10,
   "subject":"feat: a deliberately descriptive commit subject for chunk coverage"}]}]},900)
changes=[]
for i in range(8):
    text=("Open work line %d with enough synthetic words to span bounded notification chunks"%i)
    if i == 0:
        text += " sk-abcdefghijklmnopqrstuvwxyz123456"
    changes.append({"id":"chat:item-%d"%i,"stable_id":"chat:item-%d"%i,"source_id":"chat",
      "source_node":"codex:chat","kind":"chat_open_end","item_key":"item-%d"%i,
      "text":text,
      "change_type":"new","updated_at":now-20+i,"resolved_at":None,
      "resolution_evidence_type":None,"resolution_evidence_ref":None})
w("chats",{"nodes":[],"edges":[],"topics":[],"counts":{},"loose_ends":[],
             "loose_end_changes":changes},1800)
PY

SENDER="$T/sender.py"
cat > "$SENDER" <<'PY'
#!/usr/bin/env python3
import json, os, sys, time
capture=os.environ["SEND_CAPTURE"]
rows=[]
try: rows=json.load(open(capture))
except Exception: pass
rows.append(sys.argv[1:])
json.dump(rows,open(capture,"w"))
n=len(rows)
pause=os.environ.get("MORNING_BRIEF_SEND_PAUSE_FILE")
if pause and not os.path.exists(pause+".used"):
    open(pause+".used","w").write("1")
    open(pause+".entered","w").write("1")
    deadline=time.time()+10
    while not os.path.exists(pause+".release") and time.time()<deadline:
        time.sleep(0.01)
stamp=capture+".failed"
if not os.environ.get("MORNING_BRIEF_SENDER_DISABLE_FAIL") and n==2 and not os.path.exists(stamp):
    open(stamp,"w").write("1")
    sys.exit(1)
print(os.environ.get("MORNING_BRIEF_SENDER_STATUS", "delivered"))
sys.exit(0)
PY
chmod +x "$SENDER"
export MORNING_BRIEF_SEND_BIN="$SENDER" SEND_CAPTURE="$T/send.json"

if PYTHONPATH="$ROOT/scripts" python3 - "$BRIEF" <<'PY'
import importlib.machinery, sys
mod=importlib.machinery.SourceFileLoader("morning_brief",sys.argv[1]).load_module()
secret="sk-abcdefghijklmnopqrstuvwxyz123456"
payload=("x"*150)+secret+("y"*150)
assert mod._delivery_chunks("boundary",payload) is None
PY
then pass "whole-notification screening catches a boundary-spanning secret"
else fail "whole-notification screening catches a boundary-spanning secret"; fi

"$BRIEF" --send >/dev/null 2>&1; RC1=$?
if [ "$RC1" -ne 0 ]; then pass "partial send exits nonzero"; else fail "partial send exits nonzero"; fi

RECEIPT="$(find "$MISSION_CONTROL_HOME/morning-brief/delivery" -name '*.json' 2>/dev/null | head -1)"
if [ -s "$RECEIPT" ] && python3 - "$RECEIPT" "$SEND_CAPTURE" <<'PY'
import json, sys
r=json.load(open(sys.argv[1])); calls=json.load(open(sys.argv[2]))
assert r["state"] == "failed"
assert r["confirmed_chunks"] == 1
assert r["total_chunks"] > 2
assert r["chunks"][0]["state"] == "confirmed"
assert r["chunks"][1]["state"] == "failed"
assert len(calls) == 2
PY
then pass "partial receipt confirms only chunk one and stops at failure"
else fail "partial receipt confirms only chunk one and stops at failure"; fi
if [ ! -e "$MISSION_CONTROL_HOME/morning-brief/delivery-cursor.json" ]; then
  pass "failed delivery does not advance cursor"
else fail "failed delivery does not advance cursor"; fi
MARKER="$MISSION_CONTROL_HOME/morning-brief/last-compose.json"
MARKER_BEFORE="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$MARKER")"

"$BRIEF" --send >/dev/null 2>&1; RC2=$?
if [ "$RC2" -eq 0 ] && python3 - "$RECEIPT" "$SEND_CAPTURE" "$MISSION_CONTROL_HOME/morning-brief/delivery-cursor.json" "$MISSION_CONTROL_HOME/morning-brief/latest.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1])); calls=json.load(open(sys.argv[2])); cursor=json.load(open(sys.argv[3])); side=json.load(open(sys.argv[4]))
assert r["state"] == "delivered" and r["confirmed_chunks"] == r["total_chunks"]
assert len(calls) == r["total_chunks"] + 1, (len(calls),r["total_chunks"])
assert cursor["loose_end_changes"] == side["selection_high_water"]["loose_end_changes"]
assert side["delivery"]["state"] == "delivered"
assert set(side["egress_counters"]["delivery"]) >= {"dropped_fields","reason_secret","reason_email","reason_phone"}
PY
then pass "retry sends only unconfirmed chunks and advances cursor on completion"
else fail "retry sends only unconfirmed chunks and advances cursor on completion"; fi
MARKER_AFTER="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$MARKER")"
if [ "$MARKER_BEFORE" = "$MARKER_AFTER" ]; then pass "delivery retry does not create a second compose-run marker"
else fail "delivery retry does not create a second compose-run marker"; fi

BEFORE="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$SEND_CAPTURE" 2>/dev/null || echo 0)"
"$BRIEF" --send >/dev/null 2>&1; RC3=$?
AFTER="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$SEND_CAPTURE" 2>/dev/null || echo 0)"
if [ "$RC3" -eq 0 ] && [ "$BEFORE" = "$AFTER" ]; then pass "completed brief resend is a no-op"
else fail "completed brief resend is a no-op"; fi

if python3 - "$SEND_CAPTURE" <<'PY'
import json,re,sys
calls=json.load(open(sys.argv[1]))
assert calls
for args in calls:
    assert args[:10]==["emit","--route","briefs","--source",
        "mission-control-morning-brief","--event","delivery-chunk",
        "--severity","info","--batch"], args
    assert args[11]=="--part" and args[13]=="--text", args
    assert re.fullmatch(r"\d+/\d+",args[12]),args
    assert len(args)==15
    assert re.search(r"Morning Brief .* chunk \d+/\d+ · [0-9a-f]{12}",args[14]),args[14][:100]
    assert "sk-abcdefghijklmnopqrstuvwxyz123456" not in args[14]
PY
then pass "sender receives bounded Briefs batch argv plus identified, hashed, scrubbed chunks"
else fail "sender receives bounded Briefs batch argv plus identified, hashed, scrubbed chunks"; fi

# A zero exit with a burst-suppressed status is not a delivery confirmation.
export MORNING_BRIEF_SENDER_DISABLE_FAIL=1 MORNING_BRIEF_SENDER_STATUS=suppressed
rm -f "$RECEIPT" "$MISSION_CONTROL_HOME/morning-brief/delivery-cursor.json"
"$BRIEF" --send >/dev/null 2>&1; SUPPRESSED_RC=$?
if [ "$SUPPRESSED_RC" -ne 0 ] && python3 - "$RECEIPT" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r["state"] == "failed"
assert r["confirmed_chunks"] == 0
assert r["chunks"][0]["state"] == "failed"
PY
then pass "burst-suppressed chunk never becomes a confirmed delivery"
else fail "burst-suppressed chunk became a confirmed delivery"; fi
unset MORNING_BRIEF_SENDER_STATUS

if ! grep -Eq 'MORNING_BRIEF_CHAT_ID|ALLOWED_USER_ID' "$BRIEF"; then
  pass "Morning Brief source has no destination-ID fallback"
else fail "Morning Brief source has destination-ID fallback"; fi

MODE="$(stat -f '%Lp' "$RECEIPT" 2>/dev/null || stat -c '%a' "$RECEIPT" 2>/dev/null)"
if [ "$MODE" = 600 ]; then pass "delivery receipt is mode 600"; else fail "delivery receipt mode is $MODE"; fi

# Durable identity fails closed if Markdown changes without a new sidecar/hash.
rm -f "$RECEIPT" "$MISSION_CONTROL_HOME/morning-brief/delivery-cursor.json"
printf '\ntampered\n' >> "$MISSION_CONTROL_HOME/morning-brief/latest.md"
BEFORE_TAMPER="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$SEND_CAPTURE")"
"$BRIEF" --send >/dev/null 2>&1; RC4=$?
AFTER_TAMPER="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$SEND_CAPTURE")"
if [ "$RC4" -ne 0 ] && [ "$BEFORE_TAMPER" = "$AFTER_TAMPER" ]; then
  pass "Markdown/sidecar content mismatch fails closed before send"
else fail "Markdown/sidecar content mismatch fails closed before send"; fi

# Two simultaneous senders serialize around one receipt and emit every chunk once.
rm -f "$MISSION_CONTROL_HOME/morning-brief/latest.json" "$MISSION_CONTROL_HOME/morning-brief/latest.md"
BEFORE_CONCURRENT="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$SEND_CAPTURE")"
MORNING_BRIEF_NOW_EPOCH=1783760400 "$BRIEF" --send >/dev/null 2>&1 & P1=$!
MORNING_BRIEF_NOW_EPOCH=1783760400 "$BRIEF" --send >/dev/null 2>&1 & P2=$!
wait "$P1"; C1=$?; wait "$P2"; C2=$?
NEW_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["brief_id"])' "$MISSION_CONTROL_HOME/morning-brief/latest.json")"
NEW_RECEIPT="$MISSION_CONTROL_HOME/morning-brief/delivery/$NEW_ID.json"
if python3 - "$SEND_CAPTURE" "$NEW_RECEIPT" "$BEFORE_CONCURRENT" "$C1" "$C2" <<'PY'
import json,sys
calls=json.load(open(sys.argv[1])); receipt=json.load(open(sys.argv[2])); before=int(sys.argv[3])
assert int(sys.argv[4])==0 and int(sys.argv[5])==0
assert receipt["state"]=="delivered"
assert len(calls)-before==receipt["total_chunks"],(len(calls)-before,receipt["total_chunks"])
PY
then pass "concurrent senders emit one external send per chunk"
else fail "concurrent senders emit one external send per chunk"; fi
if [ ! -d "$MISSION_CONTROL_HOME/morning-brief/delivery.lock" ]; then pass "delivery lock is released"
else fail "delivery lock was left behind"; fi

# Standalone compose shares the same state lock. If it arrives while send is
# paused, it must wait and then preserve the completed brief/receipt identity.
rm -f "$MISSION_CONTROL_HOME/morning-brief/latest.json" "$MISSION_CONTROL_HOME/morning-brief/latest.md" \
      "$MISSION_CONTROL_HOME/morning-brief/delivery-cursor.json"
PAUSE_FILE="$T/compose-send-pause"
export MORNING_BRIEF_SEND_PAUSE_FILE="$PAUSE_FILE"
export MORNING_BRIEF_SENDER_DISABLE_FAIL=1
MORNING_BRIEF_NOW_EPOCH=1783846800 "$BRIEF" --send >"$T/compose-send.out" 2>"$T/compose-send.err" & PSEND=$!
for _ in $(seq 1 200); do [ -f "$PAUSE_FILE.entered" ] && break; sleep 0.02; done
MORNING_BRIEF_NOW_EPOCH=1783846800 "$BRIEF" >/dev/null 2>&1 & PCOMPOSE=$!
sleep 0.1
: > "$PAUSE_FILE.release"
wait "$PSEND"; RCSEND=$?; wait "$PCOMPOSE"; RCCOMPOSE=$?
unset MORNING_BRIEF_SEND_PAUSE_FILE
unset MORNING_BRIEF_SENDER_DISABLE_FAIL
if python3 - "$MISSION_CONTROL_HOME/morning-brief" "$RCSEND" "$RCCOMPOSE" <<'PY'
import glob,json,os,sys
root=sys.argv[1]
latest=json.load(open(os.path.join(root,"latest.json")))
marker=json.load(open(os.path.join(root,"last-compose.json")))
cursor=json.load(open(os.path.join(root,"delivery-cursor.json")))
receipt=json.load(open(os.path.join(root,"delivery",latest["brief_id"]+".json")))
assert int(sys.argv[2])==0 and int(sys.argv[3])==0
assert latest["delivery"]["state"]=="delivered"
assert latest["brief_id"]==marker["brief_id"]==cursor["brief_id"]==receipt["brief_id"]
PY
then pass "compose and send serialize around one coherent brief identity"
else
  cat "$T/compose-send.err" >&2
  python3 - "$MISSION_CONTROL_HOME/morning-brief" "$SEND_CAPTURE" <<'PY' >&2
import glob,json,os,sys
root=sys.argv[1]
receipts=glob.glob(os.path.join(root,"delivery","*.json"))
print("diagnostic receipts",[(os.path.basename(p),json.load(open(p)).get("state"),
      json.load(open(p)).get("confirmed_chunks"),json.load(open(p)).get("total_chunks")) for p in receipts])
print("diagnostic sender calls",len(json.load(open(sys.argv[2]))))
PY
  fail "compose and send left incoherent brief state"
fi

printf '%s\n' "----"
if [ "$FAIL" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$FAIL FAILED"; exit 1
