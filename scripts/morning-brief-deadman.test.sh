#!/bin/bash
# Deadman missing/stale/empty/partial/throttle tests. Stub sender only.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEADMAN="$ROOT/scripts/morning-brief-deadman"
FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
HOME_T="$T/home"; STATE="$T/state"; mkdir -p "$HOME_T" "$STATE/morning-brief"

# Existing delivery-health cases use a valid exact code/render stamp; dedicated
# cases below remove/malformed it to exercise the independent install gate.
PYTHONPATH="$ROOT/scripts" python3 - "$STATE" <<'PY'
import os, sys
from mission_control_common import write_install_stamp
home=sys.argv[1]; bindir=os.path.join(home,"bin"); os.makedirs(bindir)
for name in ("dashboard","morning-brief","morning-brief-deadman",
             "decision-alert","mission_control_common.py"):
    open(os.path.join(bindir,name),"w").write("runtime "+name+"\n")
    if name != "mission_control_common.py": os.chmod(os.path.join(bindir,name),0o700)
os.makedirs(os.path.join(home,"vendor"))
open(os.path.join(home,"index.html"),"w").write("<html></html>\n")
open(os.path.join(home,"vendor","cytoscape.min.js"),"w").write("//vendor\n")
write_install_stamp(bindir,"a"*40,"head",
  ["dashboard","morning-brief","morning-brief-deadman","decision-alert",
   "mission_control_common.py"],1783675000,
  assets={"index.html":os.path.join(home,"index.html"),
          "vendor/cytoscape.min.js":os.path.join(home,"vendor","cytoscape.min.js")})
PY

SENDER="$T/sender.py"
cat > "$SENDER" <<'PY'
#!/usr/bin/env python3
import json,os,sys
p=os.environ["SEND_CAPTURE"]
rows=[]
try: rows=json.load(open(p))
except Exception: pass
rows.append(sys.argv[1:]); json.dump(rows,open(p,"w"))
PY
chmod +x "$SENDER"
CAP="$T/send.json"
run_deadman(){
  env -i HOME="$HOME_T" PATH="/usr/bin:/bin" MISSION_CONTROL_HOME="$STATE" \
    MORNING_BRIEF_DEADMAN_NOW_EPOCH="$1" MORNING_BRIEF_DEADMAN_THROTTLE_S=3600 \
    MORNING_BRIEF_CHAT_ID=12345 MORNING_BRIEF_SEND_BIN="$SENDER" SEND_CAPTURE="$CAP" \
    PYTHONPATH="$ROOT/scripts" "$DEADMAN" >/dev/null 2>"$T/err"
}
calls(){ python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$CAP" 2>/dev/null || echo 0; }

run_deadman 1783675200; R1=$?
if [ "$R1" -ne 0 ] && [ "$(calls)" = 1 ]; then pass "missing brief alerts and exits nonzero"
else fail "missing brief alerts and exits nonzero"; fi
run_deadman 1783675300; R2=$?
if [ "$R2" -ne 0 ] && [ "$(calls)" = 1 ]; then pass "same failure is throttled"
else fail "same failure is throttled"; fi

# A delivered, current, non-empty brief is healthy and does not alert.
python3 - "$STATE/morning-brief" <<'PY'
import json,os,sys
p=sys.argv[1]; bid="healthy-brief"
json.dump({"schema":1,"brief_id":bid,"generated_epoch":1783675300,
 "delivery":{"state":"delivered","confirmed_chunks":2,"total_chunks":2}},open(os.path.join(p,"latest.json"),"w"))
open(os.path.join(p,"latest.md"),"w").write("# Healthy brief\n")
os.makedirs(os.path.join(p,"delivery"),exist_ok=True)
json.dump({"brief_id":bid,"state":"delivered","confirmed_chunks":2,"total_chunks":2,"delivered_at":1783675300},
          open(os.path.join(p,"delivery",bid+".json"),"w"))
PY
run_deadman 1783675400; R3=$?
if [ "$R3" -eq 0 ] && [ "$(calls)" = 1 ]; then pass "current completed delivery is healthy"
else fail "current completed delivery is healthy"; fi

# A previous-local-day brief is stale even when it is less than the 26h age cap.
python3 - "$STATE/morning-brief" <<'PY'
import json,os,sys
p=sys.argv[1]; bid="previous-day"; generated=1783675500-85800
json.dump({"schema":1,"brief_id":bid,"generated_epoch":generated,
 "delivery":{"state":"delivered","confirmed_chunks":1,"total_chunks":1}},open(os.path.join(p,"latest.json"),"w"))
open(os.path.join(p,"latest.md"),"w").write("# Yesterday\n")
json.dump({"brief_id":bid,"state":"delivered","confirmed_chunks":1,"total_chunks":1,"delivered_at":generated},
          open(os.path.join(p,"delivery",bid+".json"),"w"))
PY
run_deadman 1783675500; RS=$?
if [ "$RS" -ne 0 ] && [ "$(calls)" = 2 ]; then pass "previous-day delivered brief alerts as stale"
else fail "previous-day delivered brief alerts as stale"; fi

# Empty and unsent are separate failure fingerprints.
python3 - "$STATE/morning-brief" <<'PY'
import json,os,sys
p=sys.argv[1]; bid="empty-brief"; now=1783675600
json.dump({"schema":1,"brief_id":bid,"generated_epoch":now,
 "delivery":{"state":"delivered","confirmed_chunks":1,"total_chunks":1}},open(os.path.join(p,"latest.json"),"w"))
open(os.path.join(p,"latest.md"),"w").close()
json.dump({"brief_id":bid,"state":"delivered","confirmed_chunks":1,"total_chunks":1,"delivered_at":now},
          open(os.path.join(p,"delivery",bid+".json"),"w"))
PY
run_deadman 1783675600; RE=$?
if [ "$RE" -ne 0 ] && [ "$(calls)" = 3 ]; then pass "empty brief alerts"
else fail "empty brief alerts"; fi
python3 - "$STATE/morning-brief" <<'PY'
import json,os,sys
p=sys.argv[1]; bid="unsent-brief"; now=1783675700
json.dump({"schema":1,"brief_id":bid,"generated_epoch":now,
 "delivery":{"state":"not_sent","confirmed_chunks":0,"total_chunks":0}},open(os.path.join(p,"latest.json"),"w"))
open(os.path.join(p,"latest.md"),"w").write("# Unsent\n")
PY
run_deadman 1783675700; RU=$?
if [ "$RU" -ne 0 ] && [ "$(calls)" = 4 ]; then pass "unsent brief alerts"
else fail "unsent brief alerts"; fi

# Partial delivery has a different fingerprint and alerts immediately.
python3 - "$STATE/morning-brief/latest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["brief_id"]="partial-brief"; d["delivery"]={"state":"failed","confirmed_chunks":1,"total_chunks":3}; json.dump(d,open(p,"w"))
PY
run_deadman 1783675800; R4=$?
if [ "$R4" -ne 0 ] && [ "$(calls)" = 5 ]; then pass "partial delivery alerts independently"
else fail "partial delivery alerts independently"; fi

# Malformed typed counts fail safely rather than crashing the scheduled check.
python3 - "$STATE/morning-brief/latest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["brief_id"]="malformed-brief"; d["generated_epoch"]=1783675900; d["delivery"]={"state":"delivered","confirmed_chunks":[],"total_chunks":{}}; json.dump(d,open(p,"w"))
PY
printf '# malformed state\n' > "$STATE/morning-brief/latest.md"
run_deadman 1783675900; RM=$?
if [ "$RM" -ne 0 ] && [ "$(calls)" = 6 ]; then pass "malformed delivery state fails safely"
else fail "malformed delivery state fails safely"; fi

# Every persisted-JSON shape fails to a category instead of crashing the
# scheduled check. Keep this in-process and stub all outward effects.
if PYTHONPATH="$ROOT/scripts" python3 - "$DEADMAN" <<'PY'
import importlib.machinery, json, os, sys, tempfile
m=importlib.machinery.SourceFileLoader("deadman_shapes", sys.argv[1]).load_module()
now=1783676000
def state(latest=None, previous=None):
    root=tempfile.mkdtemp(); home=os.path.join(root,"morning-brief")
    os.makedirs(os.path.join(home,"delivery"))
    os.environ["MISSION_CONTROL_HOME"]=root
    if latest is not None:
        json.dump(latest,open(os.path.join(home,"latest.json"),"w"))
        open(os.path.join(home,"latest.md"),"w").write("# fixture\n")
    if previous is not None:
        json.dump(previous,open(os.path.join(home,"deadman-alert-state.json"),"w"))
    return root

root=state({"brief_id":"bad-container","generated_epoch":now,
            "delivery":"not-a-map"})
assert m._problem(now)[0] == "unsent"
root=state({"brief_id":"bad-count","generated_epoch":now,
            "delivery":{"state":"delivered","confirmed_chunks":float("inf"),
                        "total_chunks":1}})
assert m._problem(now)[0] == "unsent"
root=state(None,{"fingerprint":"x","alerted_at":"not-an-int"})
m._send=lambda category: False
m.verify_install_stamp=lambda path: {"present":False,"ok":False,
  "head_sha":None,"provenance":None}
assert m._main_locked() == 1

# Future persisted throttle state is invalid, never permission to suppress the
# current real failure. Keep the sender in-process and capture category only.
fingerprint=m.hashlib.sha256(b"missing:none").hexdigest()
root=state(None,{"fingerprint":fingerprint,"alerted_at":now+3600})
os.environ["MORNING_BRIEF_DEADMAN_NOW_EPOCH"]=str(now)
sent=[]
m._send=lambda category: sent.append(category) or True
m.verify_install_stamp=lambda path: {"present":True,"ok":True,"reason":"verified",
  "head_sha":"a"*40,"provenance":"head"}
assert m._main_locked() == 1 and sent == ["missing"]
marker=json.load(open(os.path.join(root,"morning-brief","deadman-last-check.json")))
assert marker["alerted"] is True and marker["throttled"] is False, marker

# Delivery timestamps must be monotonic and not future-dated. Same-local-day is
# necessary but not sufficient proof of a completed current delivery.
def delivered_problem(delivered_at):
    root=state({"brief_id":"time-order","generated_epoch":now-60,
                "delivery":{"state":"delivered","confirmed_chunks":1,"total_chunks":1}})
    home=os.path.join(root,"morning-brief"); os.makedirs(os.path.join(home,"delivery"),exist_ok=True)
    json.dump({"brief_id":"time-order","state":"delivered","confirmed_chunks":1,
               "total_chunks":1,"delivered_at":delivered_at},
              open(os.path.join(home,"delivery","time-order.json"),"w"))
    return m._problem(now)[0]
assert delivered_problem(now+3600) == "unsent"
assert delivered_problem(now-120) == "unsent"
PY
then pass "malformed deadman containers, counts, and throttle state fail safely"
else fail "malformed deadman containers, counts, and throttle state fail safely"; fi

# Sensitive source content is never copied into the direct failure message.
if python3 - "$CAP" <<'PY'
import json,sys
rows=json.load(open(sys.argv[1]));
assert all(len(a)==3 and a[0]=="send" and a[1]=="12345" for a in rows)
blob="\n".join(a[2] for a in rows)
assert "sk-" not in blob and "@" not in blob
assert all(word in blob.lower() for word in ("missing","stale","empty","unsent","partial"))
PY
then pass "deadman uses fixed argv and category-only redacted alerts"
else fail "deadman uses fixed argv and category-only redacted alerts"; fi

MARKER="$STATE/morning-brief/deadman-last-check.json"
MODE="$(stat -f '%Lp' "$MARKER" 2>/dev/null || stat -c '%a' "$MARKER" 2>/dev/null)"
if [ -s "$MARKER" ] && [ "$MODE" = 600 ]; then pass "deadman writes atomic mode-600 check marker"
else fail "deadman check marker missing or wrong mode"; fi

# The marker carries an independent install-provenance read every run so a drifted
# runtime is observable from the deadman record, not only the dashboard.
if python3 - "$MARKER" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
s=m["install_stamp"]
assert set(s)=={"present","ok","head_sha","provenance","reason"}, s
assert isinstance(s["present"],bool) and isinstance(s["ok"],bool)
PY
then pass "deadman marker records install_stamp provenance fields"
else fail "deadman marker missing install_stamp provenance fields"; fi

# Install integrity is an independent local health gate. It must return nonzero
# and record a reason, but must never create a Telegram delivery category.
STAMP_STATE="$T/stamp-state"; STAMP_CAP="$T/stamp-send.json"; mkdir -p "$STAMP_STATE/morning-brief/delivery" "$STAMP_STATE/bin"
python3 - "$STAMP_STATE/morning-brief" <<'PY'
import json, os, sys
p=sys.argv[1]; bid="stamp-health"; now=1783676000
json.dump({"schema":1,"brief_id":bid,"generated_epoch":now,
 "delivery":{"state":"delivered","confirmed_chunks":1,"total_chunks":1}},
 open(os.path.join(p,"latest.json"),"w"))
open(os.path.join(p,"latest.md"),"w").write("# healthy\n")
json.dump({"brief_id":bid,"state":"delivered","confirmed_chunks":1,
 "total_chunks":1,"delivered_at":now},open(os.path.join(p,"delivery",bid+".json"),"w"))
PY
run_stamp_deadman(){
  env -i HOME="$HOME_T" PATH="/usr/bin:/bin" MISSION_CONTROL_HOME="$STAMP_STATE" \
    MORNING_BRIEF_DEADMAN_NOW_EPOCH=1783676000 MORNING_BRIEF_CHAT_ID=12345 \
    MORNING_BRIEF_SEND_BIN="$SENDER" SEND_CAPTURE="$STAMP_CAP" PYTHONPATH="$ROOT/scripts" \
    "$DEADMAN" >/dev/null 2>"$T/stamp-err"
}
run_stamp_deadman; SM=$?
if [ "$SM" -ne 0 ] && [ ! -e "$STAMP_CAP" ] && \
   python3 - "$STAMP_STATE/morning-brief/deadman-last-check.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); assert m["result"]=="install-unverified",m
assert m["install_stamp"]["reason"]=="missing",m
PY
then pass "deadman: missing install stamp fails locally without Telegram alert"
else fail "deadman: missing install stamp was green or sent an alert"; fi
printf '[]\n' > "$STAMP_STATE/bin/install-stamp.json"; rm -f "$STAMP_STATE/morning-brief/deadman-alert-state.json" "$STAMP_CAP"
run_stamp_deadman; SX=$?
if [ "$SX" -ne 0 ] && [ ! -e "$STAMP_CAP" ] && \
   python3 - "$STAMP_STATE/morning-brief/deadman-last-check.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); assert m["result"]=="install-unverified",m
assert m["install_stamp"]["reason"]=="malformed",m
PY
then pass "deadman: malformed install stamp fails locally without traceback or alert"
else fail "deadman: malformed install stamp did not fail closed"; fi

# Concurrent checks serialize; only the first alert crosses the external boundary.
STATE_C="$T/concurrent-state"; CAP_C="$T/concurrent-send.json"; mkdir -p "$STATE_C/morning-brief"
env -i HOME="$HOME_T" PATH="/usr/bin:/bin" MISSION_CONTROL_HOME="$STATE_C" \
  MORNING_BRIEF_DEADMAN_NOW_EPOCH=1783676000 MORNING_BRIEF_DEADMAN_THROTTLE_S=3600 \
  MORNING_BRIEF_CHAT_ID=12345 MORNING_BRIEF_SEND_BIN="$SENDER" SEND_CAPTURE="$CAP_C" \
  PYTHONPATH="$ROOT/scripts" "$DEADMAN" >/dev/null 2>&1 & D1=$!
env -i HOME="$HOME_T" PATH="/usr/bin:/bin" MISSION_CONTROL_HOME="$STATE_C" \
  MORNING_BRIEF_DEADMAN_NOW_EPOCH=1783676000 MORNING_BRIEF_DEADMAN_THROTTLE_S=3600 \
  MORNING_BRIEF_CHAT_ID=12345 MORNING_BRIEF_SEND_BIN="$SENDER" SEND_CAPTURE="$CAP_C" \
  PYTHONPATH="$ROOT/scripts" "$DEADMAN" >/dev/null 2>&1 & D2=$!
wait "$D1"; DR1=$?; wait "$D2"; DR2=$?
if [ "$DR1" -ne 0 ] && [ "$DR2" -ne 0 ] && [ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$CAP_C")" = 1 ]; then
  pass "concurrent deadman checks emit one throttled alert"
else fail "concurrent deadman checks emit one throttled alert"; fi

for tmpl in "$ROOT/launchd/com.gillettes.morning-brief.plist.template" \
            "$ROOT/launchd/com.gillettes.morning-brief-deadman.plist.template" \
            "$ROOT/launchd/com.gillettes.outcome-extractor.plist.template"; do
  if plutil -lint "$tmpl" >/dev/null 2>&1 && ! grep -q -- '-lc' "$tmpl"; then pass "$(basename "$tmpl") is direct-argv plist"
  else fail "$(basename "$tmpl") plist contract"; fi
done

if python3 - "$ROOT/launchd/com.gillettes.outcome-extractor.plist.template" <<'PY'
import plistlib,sys
with open(sys.argv[1],"rb") as handle:
    data=plistlib.load(handle)
slots=data["StartCalendarInterval"]
assert [(slot["Hour"],slot["Minute"]) for slot in slots] == [(6,40),(6,47),(6,54)]
PY
then pass "outcome extractor has bounded pre-brief retry slots"
else fail "outcome extractor retry schedule"; fi

if PYTHONPATH="$ROOT/scripts" python3 "$ROOT/scripts/morning-brief-deadman-sender.test.py"; then
  pass "direct deadman sender security and transport suite"
else
  fail "direct deadman sender security and transport suite"
fi

printf '%s\n' "----"
if [ "$FAIL" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$FAIL FAILED"; exit 1
