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

if DASHBOARD_NO_OPEN=1 DASHBOARD_INSTALL_ALLOW_WORKTREE=1 \
    "$ROOT/scripts/dashboard" panel --install-only | grep -q 'installed panel'; then
  pass "panel --install-only"
else
  fail "panel --install-only"
fi
test -f "$MISSION_CONTROL_HOME/panel.html" && pass "panel.html installed" || fail "panel.html missing"
if grep -q 'innerHTML' "$MISSION_CONTROL_HOME/panel.html"; then fail "panel uses innerHTML"; else pass "panel textContent-safe"; fi
grep -q '#f4f5f7' "$MISSION_CONTROL_HOME/panel.html" && pass "panel light default" || fail "panel light default"
grep -q -- '--mc-bg:        #f4f5f7' "$ROOT/dashboard/index.html" && pass "index light default" || fail "index light default"
grep -q 'data-theme="dark"' "$ROOT/dashboard/index.html" && pass "dark theme tokens present" || fail "dark theme tokens"
PANEL_TEST_BIN="$tmp/mc-panel"
if [ -f "$ROOT/scripts/mc-panel.swift" ] && command -v swiftc >/dev/null 2>&1; then
  swiftc -O -o "$PANEL_TEST_BIN" "$ROOT/scripts/mc-panel.swift" \
    -framework AppKit -framework WebKit >/dev/null 2>&1 || true
fi
test -x "$PANEL_TEST_BIN" && pass "mc-panel binary built in isolated test state" || fail "mc-panel binary"
grep -q 'disableAutomaticTermination' "$ROOT/scripts/mc-panel.swift" && pass "panel disables TAL" || fail "panel disables TAL"
grep -q 'beginActivity' "$ROOT/scripts/mc-panel.swift" && pass "panel RunningBoard activity" || fail "panel RunningBoard activity"
grep -q 'mcDecide' "$ROOT/dashboard/panel.html" && pass "panel one-click bridge" || fail "panel one-click bridge"
grep -q 'mcDecide' "$ROOT/scripts/mc-panel.swift" && pass "swift mcDecide handler" || fail "swift mcDecide handler"
grep -q '\^decision:\[0-9a-f\].*24' "$ROOT/scripts/mc-panel.swift" && pass "swift exact decision id contract" || fail "swift exact decision id contract"
grep -q 'terminationHandler' "$ROOT/scripts/mc-panel.swift" && pass "swift decision bridge is asynchronous" || fail "swift decision bridge async"
if grep -q 'waitUntilExit' "$ROOT/scripts/mc-panel.swift"; then fail "swift blocks main thread"; else pass "swift does not block main thread"; fi
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
if node - "$ROOT/dashboard/panel.html" <<'JS'
const fs=require('fs'),vm=require('vm');
const src=fs.readFileSync(process.argv[2],'utf8');
const m=src.match(/function parseOptions\(text\) \{[\s\S]*?\n  \}\n\n  function feeds/);
if(!m)throw new Error('parseOptions not found');
const code=m[0].replace(/\n\n  function feeds[\s\S]*$/,'');
const box={};vm.runInNewContext(code+';result=parseOptions('+JSON.stringify('**DECISION NEEDED:** Choose the rollout window. **`Ship today`** — merge now. **`Wait`** — hold. I recommend the first option.')+');',box);
if(box.result.q!=='Choose the rollout window.')throw new Error(JSON.stringify(box.result));
JS
then pass "panel question omits duplicated option prose"; else fail "panel question duplicates option prose"; fi

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
if [ -x "$MISSION_CONTROL_HOME/bin/mc-panel" ] && \
   [ -f "$MISSION_CONTROL_HOME/bin/mc-panel-build.json" ]; then
  pass "panel build carries source/binary attestation"
else
  fail "panel build attestation missing"
fi

# The app bundle is an executable deployment surface. A pre-seeded symlink at
# any staged file or directory must fail without changing its external target.
APP="$MISSION_CONTROL_HOME/Mission Control Panel.app"
APP_BIN="$APP/Contents/MacOS/mc-panel"
APP_PLIST="$APP/Contents/Info.plist"
if DASHBOARD_NO_OPEN=1 "$ROOT/scripts/dashboard" panel >/dev/null 2>&1 && [ -x "$APP_BIN" ]; then
  pass "panel stages an attested app bundle"
else
  fail "panel app bundle staging"
fi
victim_bin="$tmp/panel-binary-victim"; printf 'binary-victim\n' > "$victim_bin"
rm -f "$APP_BIN"; ln -s "$victim_bin" "$APP_BIN"
if DASHBOARD_NO_OPEN=1 "$ROOT/scripts/dashboard" panel >/dev/null 2>&1; then
  fail "panel followed a symlinked app binary"
elif [ "$(cat "$victim_bin")" = binary-victim ] && [ -L "$APP_BIN" ]; then
  pass "panel rejects symlinked app binary without target mutation"
else
  fail "panel binary symlink target changed"
fi
rm -rf "$APP"
DASHBOARD_NO_OPEN=1 "$ROOT/scripts/dashboard" panel >/dev/null 2>&1 || true
victim_plist="$tmp/panel-plist-victim"; printf 'plist-victim\n' > "$victim_plist"
rm -f "$APP_PLIST"; ln -s "$victim_plist" "$APP_PLIST"
if DASHBOARD_NO_OPEN=1 "$ROOT/scripts/dashboard" panel >/dev/null 2>&1; then
  fail "panel followed a symlinked Info.plist"
elif [ "$(cat "$victim_plist")" = plist-victim ] && [ -L "$APP_PLIST" ]; then
  pass "panel rejects symlinked Info.plist without target mutation"
else
  fail "panel plist symlink target changed"
fi
rm -rf "$APP"
outside_app="$tmp/outside-panel-app"; mkdir -p "$outside_app"; printf 'directory-victim\n' > "$outside_app/sentinel"
ln -s "$outside_app" "$APP"
if DASHBOARD_NO_OPEN=1 "$ROOT/scripts/dashboard" panel >/dev/null 2>&1; then
  fail "panel followed a symlinked app directory"
elif [ "$(cat "$outside_app/sentinel")" = directory-victim ] && [ -L "$APP" ]; then
  pass "panel rejects symlinked app directory without target mutation"
else
  fail "panel directory symlink target changed"
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
  outside="$tmp/symlink-target.md"
  printf 'unchanged\n' > "$outside"
  rm -f "$MISSION_CONTROL_HOME/prompts/${INGEST_ID}.md"
  ln -s "$outside" "$MISSION_CONTROL_HOME/prompts/${INGEST_ID}.md"
  if DASHBOARD_NO_OPEN=1 MISSION_CONTROL_HOME="$MISSION_CONTROL_HOME" REPO_ROOT="$ROOT" \
      "$MISSION_CONTROL_HOME/bin/dashboard" decide answer "$INGEST_ID" 1 >/dev/null 2>&1; then
    fail "decide answer followed a symlink prompt destination"
  elif [ "$(cat "$outside")" = unchanged ]; then
    pass "decide answer rejects symlink prompt destinations without target mutation"
  else
    fail "decide answer mutated symlink target"
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



# Desktop-first Morning Brief / operator CTA (ER-134)
CTA='Glance: menu-bar MC (dashboard panel) or light Home (dashboard open).'
grep -Fq "$CTA" "$ROOT/scripts/mission_control_common.py" && pass "DESKTOP_GLANCE_CTA constant" || fail "DESKTOP_GLANCE_CTA constant"
grep -Fq 'DESKTOP_GLANCE_CTA' "$ROOT/scripts/morning-brief" && pass "brief uses DESKTOP_GLANCE_CTA" || fail "brief uses DESKTOP_GLANCE_CTA"
grep -Fq 'DESKTOP_GLANCE_CTA' "$ROOT/scripts/morning-brief-deadman" && pass "deadman uses DESKTOP_GLANCE_CTA" || fail "deadman uses DESKTOP_GLANCE_CTA"
grep -Fq 'DESKTOP_GLANCE_CTA' "$ROOT/scripts/decision-alert" && pass "decision-alert uses DESKTOP_GLANCE_CTA" || fail "decision-alert uses DESKTOP_GLANCE_CTA"
grep -Fq "$CTA" "$ROOT/dashboard/index.html" && pass "Home empty-state CTA" || fail "Home empty-state CTA"
# Telegram stays optional transport; Slack must not be primary operator where-to-look copy
if ! grep -qi slack "$ROOT/scripts/morning-brief" "$ROOT/scripts/morning-brief-deadman" "$ROOT/scripts/decision-alert" 2>/dev/null; then
  pass "no Slack primary in brief/deadman/alert"
else
  fail "Slack appears in brief/deadman/alert operator path"
fi


echo "er134-usability: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
