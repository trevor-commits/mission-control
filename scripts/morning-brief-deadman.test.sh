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
assert set(s)=={"present","ok","head_sha","provenance"}, s
assert isinstance(s["present"],bool) and isinstance(s["ok"],bool)
PY
then pass "deadman marker records install_stamp provenance fields"
else fail "deadman marker missing install_stamp provenance fields"; fi

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

printf '%s\n' "----"
if [ "$FAIL" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$FAIL FAILED"; exit 1
