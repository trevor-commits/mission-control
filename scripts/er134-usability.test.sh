#!/usr/bin/env bash
# Hermetic tests for ER-134 decide answer + compose-decision-prompt + panel install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE="$ROOT/scripts/compose-decision-prompt.py"
PASS=0; FAIL=0
pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export MISSION_CONTROL_HOME="$tmp/mc"
export DASHBOARD_NO_OPEN=1
export REPO_ROOT="$ROOT"
mkdir -p "$MISSION_CONTROL_HOME/data" "$MISSION_CONTROL_HOME/bin"
chmod 700 "$MISSION_CONTROL_HOME"

python3 - <<'PY'
import json, os, time
home=os.environ["MISSION_CONTROL_HOME"]
root=os.environ["REPO_ROOT"]
fix=json.load(open(os.path.join(root,"dashboard/fixtures/decisions.json")))
now=int(time.time())
fix["generated_epoch"]=now
json.dump(fix, open(os.path.join(home,"data/decisions.json"),"w"))
open(os.path.join(home,"data/decisions.js"),"w").write(
  "window.MC=window.MC||{feeds:{}};window.MC.feeds.decisions="+json.dumps(fix)+";")
auto={"schema":1,"feed":"automation","generated_at":"t","generated_epoch":now,"cadence_s":300,"ok":True,"error":None,
      "data":{"jobs":[{"label":"Nightly Review","state":"green"}]}}
json.dump(auto, open(os.path.join(home,"data/automation.json"),"w"))
open(os.path.join(home,"data/automation.js"),"w").write(
  "window.MC=window.MC||{feeds:{}};window.MC.feeds.automation="+json.dumps(auto)+";")
PY

cp "$ROOT/scripts/decision-alert" "$MISSION_CONTROL_HOME/bin/decision-alert"
cp "$ROOT/scripts/mission_control_common.py" "$MISSION_CONTROL_HOME/bin/mission_control_common.py"
cp "$ROOT/scripts/dashboard" "$MISSION_CONTROL_HOME/bin/dashboard"
cp "$COMPOSE" "$MISSION_CONTROL_HOME/bin/compose-decision-prompt.py"
chmod +x "$MISSION_CONTROL_HOME/bin/"*

python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ["MISSION_CONTROL_HOME"])/"bin/dashboard"
t=p.read_text()
t=t.replace('REPO_ROOT_DEFAULT=""', f'REPO_ROOT_DEFAULT="{os.environ["REPO_ROOT"]}"', 1)
p.write_text(t)
PY

out="$tmp/prompt.md"
python3 "$COMPOSE" --decision-id "decision:test" --choice 1 \
  --text '**DECISION NEEDED:** X. **`Ship today`**. **`Wait`**. I recommend the first option.' \
  --out "$out" > "$tmp/compose.json"
grep -q 'Goal:' "$out" && pass "compose writes Goal prompt" || fail "compose Goal"
grep -q 'Ship today' "$out" && pass "compose includes chosen label" || fail "compose label"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp/compose.json" && pass "compose json" || fail "compose json"

if DASHBOARD_NO_OPEN=1 "$ROOT/scripts/dashboard" panel --install-only | grep -q 'installed panel'; then
  pass "panel --install-only"
else
  fail "panel --install-only"
fi
test -f "$MISSION_CONTROL_HOME/panel.html" && pass "panel.html installed" || fail "panel.html missing"
if grep -q 'innerHTML' "$MISSION_CONTROL_HOME/panel.html"; then fail "panel uses innerHTML"; else pass "panel textContent-safe"; fi
grep -q '#f4f5f7' "$MISSION_CONTROL_HOME/panel.html" && pass "panel light default" || fail "panel light default"
grep -q -- '--mc-bg:        #f4f5f7' "$ROOT/dashboard/index.html" && pass "index light default" || fail "index light default"
grep -q 'data-theme="dark"' "$ROOT/dashboard/index.html" && pass "dark theme tokens present" || fail "dark theme tokens"
if [ ! -x "$ROOT/scripts/mc-panel" ] && [ -f "$ROOT/scripts/mc-panel.swift" ] && command -v swiftc >/dev/null 2>&1; then
  swiftc -O -o "$ROOT/scripts/mc-panel" "$ROOT/scripts/mc-panel.swift"     -framework AppKit -framework WebKit >/dev/null 2>&1 || true
fi
test -x "$ROOT/scripts/mc-panel" && pass "mc-panel binary built" || fail "mc-panel binary"
grep -q 'disableAutomaticTermination' "$ROOT/scripts/mc-panel.swift" && pass "panel disables TAL" || fail "panel disables TAL"
grep -q 'beginActivity' "$ROOT/scripts/mc-panel.swift" && pass "panel RunningBoard activity" || fail "panel RunningBoard activity"
grep -q 'mcDecide' "$ROOT/dashboard/panel.html" && pass "panel one-click bridge" || fail "panel one-click bridge"
grep -q 'mcDecide' "$ROOT/scripts/mc-panel.swift" && pass "swift mcDecide handler" || fail "swift mcDecide handler"
grep -q 'mcOpenFull' "$ROOT/dashboard/panel.html" && pass "panel open-full bridge" || fail "panel open-full bridge"
grep -q 'mcOpenFull' "$ROOT/scripts/mc-panel.swift" && pass "swift mcOpenFull handler" || fail "swift mcOpenFull handler"
grep -q 'openFullMissionControl' "$ROOT/scripts/mc-panel.swift" && pass "swift openFullMissionControl" || fail "swift openFullMissionControl"
grep -q '.mission-control/index.html' "$ROOT/scripts/mc-panel.swift" && pass "swift opens index.html" || fail "swift opens index.html"
grep -q 'NSWorkspace.shared.open' "$ROOT/scripts/mc-panel.swift" && pass "swift NSWorkspace open" || fail "swift NSWorkspace open"
if grep -E 'id="open-full"[^>]*href="index\.html"' "$ROOT/dashboard/panel.html" >/dev/null; then
  fail "open-full must not use relative index.html href"
else
  pass "open-full not relative href"
fi

# Login KeepAlive template (no real launchctl bootstrap in hermetic/tmp).
TMPL="$ROOT/launchd/com.gillettes.mc-panel.plist.template"
if [ -f "$TMPL" ]; then
  pass "mc-panel launchd template exists"
else
  fail "mc-panel launchd template missing"
fi
grep -q 'KeepAlive' "$TMPL" && pass "mc-panel template KeepAlive" || fail "mc-panel template KeepAlive"
grep -q 'RunAtLoad' "$TMPL" && pass "mc-panel template RunAtLoad" || fail "mc-panel template RunAtLoad"
grep -q '__MCHOME__/Mission Control Panel.app/Contents/MacOS/mc-panel' "$TMPL" \
  && pass "mc-panel template app binary path" || fail "mc-panel template app binary path"
# Must stay out of default install selected_plists (gated stamp tests).
if grep -E 'selected_plists=.*mc-panel' "$ROOT/scripts/dashboard" >/dev/null; then
  fail "mc-panel must not be in selected_plists"
else
  pass "mc-panel not in selected_plists"
fi
rendered="$tmp/mc-panel.rendered.plist"
python3 - "$TMPL" "$rendered" "/Users/fake/.mission-control" "/Users/fake" "$ROOT" <<'PY'
import sys
source, dest, mc_home, home, repo = sys.argv[1:]
text = open(source).read()
text = text.replace("__MCHOME__", mc_home).replace("__HOME__", home).replace("__REPO__", repo)
open(dest, "w").write(text)
PY
if grep -q '__MCHOME__' "$rendered"; then
  fail "mc-panel render left __MCHOME__"
else
  pass "mc-panel render substitutes __MCHOME__"
fi
grep -q '/Users/fake/.mission-control/Mission Control Panel.app/Contents/MacOS/mc-panel' "$rendered" \
  && pass "mc-panel render app path" || fail "mc-panel render app path"
grep -q '/Users/fake/.mission-control/panel.html' "$rendered" \
  && pass "mc-panel render panel.html arg" || fail "mc-panel render panel.html arg"
if command -v plutil >/dev/null 2>&1; then
  if plutil -lint "$rendered" >/dev/null 2>&1; then
    pass "mc-panel rendered plist lints"
  else
    fail "mc-panel rendered plist lint"
  fi
else
  pass "plutil absent — skip lint"
fi
# DASHBOARD_NO_OPEN + tmp home must not write LaunchAgents (hermetic).
fake_home="$tmp/fake-home"
mkdir -p "$fake_home/Library/LaunchAgents"
HOME="$fake_home" DASHBOARD_NO_OPEN=1 "$ROOT/scripts/dashboard" panel >/dev/null 2>&1 || true
if [ -f "$fake_home/Library/LaunchAgents/com.gillettes.mc-panel.plist" ]; then
  fail "autoload wrote LaunchAgent under DASHBOARD_NO_OPEN"
else
  pass "no LaunchAgent under DASHBOARD_NO_OPEN"
fi


TEXT="$(python3 -c 'import json,os;print(json.load(open(os.environ["REPO_ROOT"]+"/dashboard/fixtures/decisions.json"))["data"]["pinned"][0]["text"])')"
"$MISSION_CONTROL_HOME/bin/decision-alert" ingest \
  --source-kind chat \
  --source-key "test:er134:1" \
  --text "$TEXT" \
  --trust structured \
  --provenance "chat-graph tier1" \
  --json > "$tmp/ingest.json"
INGEST_ID="$(python3 -c 'import json;d=json.load(open("'"$tmp"/ingest.json'"));print((d.get("decision") or d).get("id") or "")')"
echo "INGEST_ID=$INGEST_ID"
if [ -n "$INGEST_ID" ]; then
  export INGEST_ID
  python3 - <<'PY'
import json, os
home=os.environ["MISSION_CONTROL_HOME"]
path=os.path.join(home,"data/decisions.json")
d=json.load(open(path))
d["data"]["pinned"][0]["id"]=os.environ["INGEST_ID"]
d["data"]["pinned"][0]["text"]=json.load(open(os.environ["REPO_ROOT"]+"/dashboard/fixtures/decisions.json"))["data"]["pinned"][0]["text"]
json.dump(d, open(path,"w"))
open(os.path.join(home,"data/decisions.js"),"w").write(
  "window.MC=window.MC||{feeds:{}};window.MC.feeds.decisions="+json.dumps(d)+";")
PY
  if DASHBOARD_NO_OPEN=1 MISSION_CONTROL_HOME="$MISSION_CONTROL_HOME" REPO_ROOT="$ROOT" \
      "$MISSION_CONTROL_HOME/bin/dashboard" decide answer "$INGEST_ID" 1 > "$tmp/answer.out" 2>"$tmp/answer.err"; then
    pass "decide answer exits 0"
    test -f "$MISSION_CONTROL_HOME/prompts/${INGEST_ID}.md" && pass "prompt file written" || fail "prompt file"
    grep -q 'Goal:' "$MISSION_CONTROL_HOME/prompts/${INGEST_ID}.md" && pass "prompt has Goal" || fail "prompt Goal"
  else
    fail "decide answer"
    head -40 "$tmp/answer.err" || true
    head -40 "$tmp/answer.out" || true
  fi
else
  fail "could not ingest decision id"
  head -c 500 "$tmp/ingest.json" || true
fi


# Decisions collect best-effort auto-alerts (capped, newest-first, fresh window).
ALERT_TMP="$(mktemp -d)"
mkdir -p "$ALERT_TMP/state/data" "$ALERT_TMP/repo/scripts"
cp "$ROOT/scripts/decision-alert" "$ALERT_TMP/repo/scripts/decision-alert"
cp "$ROOT/scripts/mission_control_common.py" "$ALERT_TMP/repo/scripts/mission_control_common.py"
cat > "$ALERT_TMP/sender" <<'SEND'
#!/usr/bin/env python3
import json,os,sys
p=os.environ["ALERT_CAPTURE"]
rows=[]
if os.path.exists(p):
  try: rows=json.load(open(p))
  except Exception: rows=[]
rows.append(sys.argv[1:])
json.dump(rows, open(p,"w"))
SEND
chmod +x "$ALERT_TMP/sender"
export ALERT_CAPTURE="$ALERT_TMP/capture.json"
export DECISION_ALERT_SEND_BIN="$ALERT_TMP/sender"
export DECISION_ALERT_CHAT_ID=4242
export DECISION_ALERT_MAX=1
export DECISION_ALERT_FRESH_WITHIN_S=100000000
MISSION_CONTROL_HOME="$ALERT_TMP/state" "$ALERT_TMP/repo/scripts/decision-alert" ingest \
  --source-kind git --source-key auto-wire --text 'Choose auto-wire path' \
  --trust structured --provenance git-facts --json >/dev/null
MISSION_CONTROL_HOME="$ALERT_TMP/state" REPO_ROOT="$ALERT_TMP/repo" \
  "$ROOT/scripts/dashboard" collect --force decisions >/dev/null
if python3 - "$ALERT_TMP/state/data/decisions.json" "$ALERT_CAPTURE" <<'CHECK'
import json,sys
feed=json.load(open(sys.argv[1]))
calls=json.load(open(sys.argv[2]))
alert=(feed.get("data") or {}).get("alert") or {}
assert alert.get("sent_count") == 1, alert
assert len(calls) == 1 and calls[0][0] == "send"
pinned=feed["data"]["pinned"]
assert any(d.get("alert_receipt") for d in pinned), pinned[0] if pinned else None
CHECK
then pass "decisions collect auto-alerts and stamps receipts"
else fail "decisions collect auto-alerts and stamps receipts"; fi
unset ALERT_CAPTURE DECISION_ALERT_SEND_BIN DECISION_ALERT_CHAT_ID DECISION_ALERT_MAX DECISION_ALERT_FRESH_WITHIN_S
rm -rf "$ALERT_TMP"


echo "er134-usability: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
