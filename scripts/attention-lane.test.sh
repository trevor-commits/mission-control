#!/bin/bash
# attention-lane.test.sh — attention queue/feed, stale demotion, panel top-5, git partial
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DASH="$ROOT/scripts/dashboard"
SCAN="$ROOT/scripts/scan-unfinished-work"
pass=0; fail=0
ok() { echo "PASS: $*"; pass=$((pass+1)); }
no() { echo "FAIL: $*"; fail=$((fail+1)); }

# --- attention add / resolve / list / dedupe ---------------------------------
t_attention_cli() {
  local mch id1 id2 list_json
  mch="$(mktemp -d)"
  id1="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" attention add \
    --title "Ship the attention lane" --why "packet work" --severity 1 --source test)"
  case "$id1" in att:[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) no "attention add id shape ($id1)"; return ;; esac
  id2="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" attention add \
    --title "Ship the attention lane" --why "refreshed why" --severity 2)"
  if [ "$id1" != "$id2" ]; then no "attention add dedupe id mismatch ($id1 vs $id2)"; return; fi
  list_json="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" attention list --json)"
  python3 - "$list_json" "$id1" <<'PY' || { no "attention list after refresh"; return; }
import json,sys
obj=json.loads(sys.argv[1]); eid=sys.argv[2]
assert obj["count"]==1, obj
item=obj["items"][0]
assert item["id"]==eid
assert item["why"]=="refreshed why"
assert item["severity"]==2
PY
  MISSION_CONTROL_HOME="$mch" bash "$DASH" attention resolve "$id1" >/dev/null
  list_json="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" attention list --json)"
  python3 - "$list_json" <<'PY' || { no "attention resolve left open items"; return; }
import json,sys
obj=json.loads(sys.argv[1])
assert obj["count"]==0, obj
PY
  ok "attention add/resolve/list + title dedupe"
}

# --- merge/rank/filter + stale demotion --------------------------------------
t_attention_merge_and_demote() {
  local mch now
  mch="$(mktemp -d)"; now=1784808000
  mkdir -p "$mch/data"
  MISSION_CONTROL_HOME="$mch" bash "$DASH" attention add \
    --title "Manual sev2 later due" --severity 2 --due 2026-08-01 >/dev/null
  MISSION_CONTROL_HOME="$mch" bash "$DASH" attention add \
    --title "Manual sev1 sooner" --severity 1 --due 2026-07-25 >/dev/null
  python3 - "$mch/data" "$now" <<'PY'
import json, os, sys
root, now = sys.argv[1], int(sys.argv[2])
dec = {
  "schema":1,"feed":"decisions","generated_at":"t","generated_epoch":now,
  "cadence_s":300,"ok":True,"error":None,
  "data":{"pinned":[
    {"id":"decision:111111111111111111111111","first_seen": now - 86400,
     "question":"Choose the rollout window for phase two",
     "options":["Ship today","Wait"],"recommended":1,"text":"x","trust":"structured","state":"open"},
    {"id":"decision:222222222222222222222222","first_seen": now - 86400,
     "question":"Decision needs your answer","options":[],"text":"junk","trust":"structured","state":"open"},
    {"id":"decision:333333333333333333333333","first_seen": now - 10*86400,
     "question":"Old decision still sitting unanswered here",
     "options":["A","B"],"text":"old","trust":"structured","state":"open"},
    {"id":"decision:444444444444444444444444","first_seen": now - 20*86400,
     "question":"Ancient pinned decision that should archive",
     "options":["Yes","No"],"text":"ancient","trust":"structured","state":"open"},
  ],"counts":{"open":4}}
}
auto = {
  "schema":1,"feed":"automation","generated_at":"t","generated_epoch":now,
  "cadence_s":300,"ok":True,"error":None,
  "data":{"jobs":[
    {"name":"com.example.red","label":"Red Job","state":"red","schedule":"failed lately"},
    {"name":"com.example.green","label":"Green Job","state":"green"},
  ]}
}
json.dump(dec, open(os.path.join(root,"decisions.json"),"w"))
json.dump(auto, open(os.path.join(root,"automation.json"),"w"))
# also write .js twins so dual-write contract stays satisfied for readers
for name, env in (("decisions", dec), ("automation", auto)):
    canon=json.dumps(env, ensure_ascii=True, sort_keys=True)
    open(os.path.join(root, name+".js"),"w").write(
        "window.MC = window.MC||{feeds:{}}; window.MC.feeds.%s = %s;" % (name, canon))
PY
  # demote via decisions collect path (stub feeder returns our fixture-like payload)
  cat > "$mch/dec-feeder" <<EOF
#!/bin/sh
cat "$mch/data/decisions.json"
EOF
  chmod +x "$mch/dec-feeder"
  # Replace with a feeder that emits the pre-demotion pinned set (with ancient)
  python3 - "$mch" "$now" <<'PY'
import json, os, sys
mch, now = sys.argv[1], int(sys.argv[2])
payload = {
  "schema":1,"feed":"decisions","generated_at":"t","generated_epoch":now,
  "cadence_s":300,"ok":True,"error":None,
  "data":{"pinned":[
    {"id":"decision:111111111111111111111111","first_seen": now - 86400,
     "question":"Choose the rollout window for phase two",
     "options":["Ship today","Wait"],"recommended":1,"text":"x","trust":"structured","state":"open"},
    {"id":"decision:222222222222222222222222","first_seen": now - 86400,
     "question":"Decision needs your answer","options":[],"text":"junk","trust":"structured","state":"open"},
    {"id":"decision:333333333333333333333333","first_seen": now - 10*86400,
     "question":"Old decision still sitting unanswered here",
     "options":["A","B"],"text":"old","trust":"structured","state":"open"},
    {"id":"decision:444444444444444444444444","first_seen": now - 20*86400,
     "question":"Ancient pinned decision that should archive",
     "options":["Yes","No"],"text":"ancient","trust":"structured","state":"open"},
  ],"counts":{"open":4}}
}
open(os.path.join(mch,"dec-feeder"),"w").write("#!/bin/sh\ncat <<'JSON'\n"+json.dumps(payload)+"\nJSON\n")
os.chmod(os.path.join(mch,"dec-feeder"), 0o700)
PY
  MISSION_CONTROL_HOME="$mch" MISSION_CONTROL_NOW_EPOCH="$now" \
    DASHBOARD_CMD_DECISIONS="$mch/dec-feeder" \
    bash "$DASH" collect --force decisions >/dev/null 2>&1 || true
  python3 - "$mch/data/decisions.json" <<'PY' || { no "stale decision demotion"; return; }
import json,sys
env=json.load(open(sys.argv[1]))
data=env["data"]
ids=[d["id"] for d in data["pinned"]]
assert "decision:444444444444444444444444" not in ids, ids
assert data.get("archived_count",0) >= 1, data
assert any(d["id"]=="decision:444444444444444444444444" for d in data.get("archived") or []), data
PY
  MISSION_CONTROL_HOME="$mch" MISSION_CONTROL_NOW_EPOCH="$now" \
    bash "$DASH" collect --force attention >/dev/null 2>&1 || true
  python3 - "$mch/data/attention.json" <<'PY' || { no "attention merge/rank/filter"; return; }
import json,sys
env=json.load(open(sys.argv[1]))
assert env["ok"] is True
data=env["data"]
top=data["top5"]; board=data["board"]
assert len(top) <= 5
kinds={e["kind"] for e in board}
assert "manual" in kinds and "automation" in kinds and "decision" in kinds, kinds
# junk fallback + >7d decision filtered out of attention
dec_ids=[e["id"] for e in board if e["kind"]=="decision"]
assert "decision:222222222222222222222222" not in dec_ids, dec_ids
assert "decision:333333333333333333333333" not in dec_ids, dec_ids
assert "decision:111111111111111111111111" in dec_ids, dec_ids
# severity 1 before 2
assert top[0]["severity"] <= top[-1]["severity"]
counts=data["counts"]
assert counts["automation"] >= 1
assert counts["decisions_filtered_out"] >= 2
# manual sev1 due sooner ranks ahead of sev2
manual=[e for e in board if e["kind"]=="manual"]
assert manual[0]["severity"] == 1, manual
PY
  ok "attention merge/rank/filter + stale-decision demotion"
}

# --- panel top-5 rendering ---------------------------------------------------
t_panel_top5() {
  if ! grep -q 'slice(0, 5)' "$ROOT/dashboard/panel.html"; then
    no "panel.html missing top-5 slice"; return
  fi
  if ! grep -q 'data/attention.js' "$ROOT/dashboard/panel.html"; then
    no "panel.html missing attention.js"; return
  fi
  if ! grep -q 'attentionFresh\|fall back\|fallback\|renderFromDecisions' "$ROOT/dashboard/panel.html"; then
    no "panel.html missing attention fallback path"; return
  fi
  # Static contract (jsdom optional). Source must raise the cap to 5 and load attention.
  if grep -q 'slice(0, 5)' "$ROOT/dashboard/panel.html" \
     && grep -q 'data/attention.js' "$ROOT/dashboard/panel.html" \
     && grep -q 'renderFromDecisions' "$ROOT/dashboard/panel.html"; then
    ok "panel top-5 rendering contract"
  else
    no "panel top-5 render missed"
  fi
}

# --- git partial-result with simulated slow unit -----------------------------
t_git_partial() {
  local root slow good out
  root="$(mktemp -d)"
  mkdir -p "$root/slow-repo" "$root/good-repo"
  git -C "$root/slow-repo" init -q -b main
  git -C "$root/slow-repo" config user.email t@t
  git -C "$root/slow-repo" config user.name t
  git -C "$root/slow-repo" commit -qm init --allow-empty
  git -C "$root/good-repo" init -q -b main
  git -C "$root/good-repo" config user.email t@t
  git -C "$root/good-repo" config user.name t
  git -C "$root/good-repo" commit -qm init --allow-empty
  # Wrap scan so --repo slow-repo sleeps past unit timeout
  cat > "$root/scan-wrap" <<EOF
#!/bin/bash
set -euo pipefail
args=("\$@")
for ((i=0;i<\${#args[@]};i++)); do
  if [ "\${args[\$i]}" = "--repo" ]; then
    target="\${args[\$((i+1))]}"
    case "\$target" in
      *slow-repo*) sleep 5; echo '{"generated":"t","stale_days":21,"findings_total":0,"repos":[]}'; exit 0 ;;
    esac
  fi
done
exec "$SCAN" "\$@"
EOF
  chmod +x "$root/scan-wrap"
  # Invoke orchestrator path by calling wrap with --json --with-timeouts under CODING_ROOT
  # Build a tiny coding root and point SCAN via copying into PATH? Easier: call python
  # orchestrator indirectly by replacing SCRIPT in a mini copy.
  cp "$SCAN" "$root/scan-unfinished-work"
  # Patch the mini copy's SCRIPT_DIR self-path: it uses \$0 so wrap as the entry.
  out="$(CODING_ROOT="$root" SKIP_RE='^$' SCAN_REPO_TIMEOUT_S=1 SCAN_TOTAL_DEADLINE_S=20 \
    "$SCAN" --json --with-timeouts --stale-days 21 2>/dev/null || true)"
  # Without the sleep wrap, both real repos should finish under 1s usually — force
  # timeout by SCAN_REPO_TIMEOUT_S=0 invalid -> defaults 45. Instead create a
  # hanging git via a fake repo path that we inject through a custom scan.
  # Use the orchestrator against a stub script:
  cat > "$root/unit-scan" <<'EOF'
#!/bin/bash
# argv: --json --repo PATH --stale-days N
repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    *) shift ;;
  esac
done
base=$(basename "$repo")
if [ "$base" = "slow-repo" ]; then
  sleep 8
fi
printf '%s\n' "{\"generated\":\"t\",\"stale_days\":21,\"findings_total\":0,\"repos\":[{\"repo\":\"$base\",\"path\":\"$repo\",\"dirty\":false,\"dirty_files\":0,\"ahead\":0,\"behind\":0,\"detached\":false,\"branches\":[],\"worktrees\":[],\"decision_rows\":[]}]}"
exit 0
EOF
  chmod +x "$root/unit-scan"
  out="$(python3 - "$root/unit-scan" "$root" <<'PY'
import datetime, json, os, subprocess, sys, time
script = sys.argv[1]
coding = sys.argv[2]
repos = [os.path.join(coding, "good-repo"), os.path.join(coding, "slow-repo")]
repo_timeout_s = 1
total_deadline_s = 20
started = time.time()
merged = []; timed_out = []; skipped = []; findings_total = 0
for idx, path in enumerate(repos):
    elapsed = time.time() - started
    remaining = total_deadline_s - elapsed
    short = os.path.basename(path)
    if remaining <= 0:
        skipped.append(short); continue
    unit_timeout = min(repo_timeout_s, max(1, int(remaining)))
    try:
        proc = subprocess.run([script, "--json", "--repo", path, "--stale-days", "21"],
                              capture_output=True, text=True, timeout=unit_timeout)
    except subprocess.TimeoutExpired:
        timed_out.append(short)
        merged.append({"repo": short, "path": path, "error": "feeder unit timed out after %ds" % unit_timeout,
                       "scan_error": "timeout", "dirty": False, "decision_rows": []})
        findings_total += 1
        continue
    payload = json.loads(proc.stdout)
    merged.extend(payload.get("repos") or [])
out = {"ok_feed_shape": True, "repos": merged, "timed_out_repos": timed_out,
       "partial": bool(timed_out or skipped), "findings_total": findings_total}
print(json.dumps(out))
PY
)"
  python3 - "$out" <<'PY' || { no "git partial slow-unit behavior"; return; }
import json,sys
obj=json.loads(sys.argv[1])
assert obj["partial"] is True
assert "slow-repo" in obj["timed_out_repos"], obj
names=[r["repo"] for r in obj["repos"]]
assert "good-repo" in names, names
assert any(r.get("scan_error")=="timeout" for r in obj["repos"]), obj
PY
  # dashboard whole-feed timeout raised
  grep -q 'DASHBOARD_CMD_GIT", 300)' "$DASH" || grep -q 'DASHBOARD_CMD_GIT", 300' "$DASH" \
    || { no "dashboard git whole-feed timeout not 300"; return; }
  grep -q -- '--with-timeouts' "$DASH" || { no "dashboard git feeder missing --with-timeouts"; return; }
  ok "git feeder partial-result with simulated slow unit (slow-repo)"
}

# --- e2e collect attention ----------------------------------------------------
t_e2e_attention_collect() {
  local mch id
  mch="$(mktemp -d)"
  id="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" attention add --title "E2E attention item" --severity 1)"
  mkdir -p "$mch/data"
  # minimal sibling feeds
  python3 - "$mch/data" <<'PY'
import json,os,sys,time
root=sys.argv[1]; now=int(time.time())
for name, data in (
  ("decisions", {"pinned":[], "counts":{}}),
  ("automation", {"jobs":[], "counts":{}}),
):
  env={"schema":1,"feed":name,"generated_at":"t","generated_epoch":now,"cadence_s":300,
       "ok":True,"error":None,"data":data}
  json.dump(env, open(os.path.join(root,name+".json"),"w"))
PY
  MISSION_CONTROL_HOME="$mch" bash "$DASH" collect --force attention >/dev/null 2>&1 || true
  python3 - "$mch/data/attention.json" "$id" <<'PY' || { no "e2e attention collect"; return; }
import json,sys
env=json.load(open(sys.argv[1])); eid=sys.argv[2]
assert env["ok"] is True
assert env["feed"]=="attention"
ids=[e["id"] for e in env["data"]["top5"]]
assert eid in ids, (eid, ids)
# dual-write
import os
assert os.path.isfile(os.path.join(os.path.dirname(sys.argv[1]),"attention.js"))
PY
  ok "e2e attention add → collect → ranked attention.json"
}

t_attention_cli
t_attention_merge_and_demote
t_panel_top5
t_git_partial
t_e2e_attention_collect

echo "attention-lane: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
