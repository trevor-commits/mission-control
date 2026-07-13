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
test -x "$ROOT/scripts/mc-panel" && pass "mc-panel binary built" || fail "mc-panel binary"
grep -q 'disableAutomaticTermination' "$ROOT/scripts/mc-panel.swift" && pass "panel disables TAL" || fail "panel disables TAL"
grep -q 'beginActivity' "$ROOT/scripts/mc-panel.swift" && pass "panel RunningBoard activity" || fail "panel RunningBoard activity"
grep -q 'mcDecide' "$ROOT/dashboard/panel.html" && pass "panel one-click bridge" || fail "panel one-click bridge"
grep -q 'mcDecide' "$ROOT/scripts/mc-panel.swift" && pass "swift mcDecide handler" || fail "swift mcDecide handler"

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

echo "er134-usability: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
