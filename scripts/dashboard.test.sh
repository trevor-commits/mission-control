#!/usr/bin/env bash
# scripts/dashboard.test.sh — feeders stubbed via env, mktemp state dirs only.
# Never touches real $HOME. One PASS:/FAIL: line per case; exit 0 iff all pass.
# Optional flag: --require-shell makes the shell-contract checks mandatory.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

# Every nested dashboard invocation must use the same interpreter as this test
# process.  Calling bare `bash` otherwise follows PATH and silently switches a
# `/bin/bash` (macOS 3.2) gate back to Homebrew Bash 5.x.
DASHBOARD_TEST_BASH="$BASH"
bash() { command "$DASHBOARD_TEST_BASH" "$@"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
DASH="$HERE/dashboard"
REQUIRE_SHELL="${1:-}"

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mc-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
STUB="$ROOT/stubs"
mkdir -p "$STUB/bin"

# --- stub feeder payloads, written via python so unicode/hostile text is safe -
python3 - "$STUB" <<'PYEOF'
import json, os, sys, time
d = sys.argv[1]
def w(name, obj):
    json.dump(obj, open(os.path.join(d, name), "w"))
now = int(time.time())
now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))
# raw payloads -> dashboard wraps them
w("usage.json", {"providers": [{"name": "claude", "pct": 62}]})
w("git.json", {"repos": [{"name": "gi", "dirty": True}]})
w("git2.json", {"repos": [{"marker": "NEW"}]})
# chats: already a full envelope (passthrough) + hostile title
w("chats.json", {"schema": 1, "feed": "chats",
                 "generated_at": now_iso, "generated_epoch": now,
                 "cadence_s": 1800, "ok": True, "error": None,
                 "data": {"nodes": [{"id": "x:1",
                          "title": "Tre'vor \U0001F600 </script> chat"}],
                          "edges": [], "topics": [],
                          "counts": {"last_full_ingest_age_s": 0,
                                     "full_ingest_state": "fresh",
                                     "full_ingest_stale": False}}})
# automation envelopes; counts carries a "red" COUNT key on purpose (false-match trap)
def auto(jobs, red):
    return {"schema": 1, "feed": "automation", "generated_at": now_iso,
            "generated_epoch": now, "cadence_s": 300, "ok": True, "error": None,
            "data": {"jobs": jobs, "counts": {"green": len(jobs) - red, "red": red}}}
w("auto_green.json", auto([{"label": "A", "state": "green"},
                           {"label": "B", "state": "green"}], 0))
w("auto_red.json", auto([{"label": "A", "state": "green"},
                         {"label": "B", "state": "red"}], 1))
w("decisions.json", {"schema": 1, "feed": "decisions", "generated_at": now_iso,
                     "generated_epoch": now, "cadence_s": 300, "ok": True,
                     "error": None, "data": {"items": []}})
w("brief.json", {"schema": 1, "feed": "brief", "generated_at": now_iso,
                 "generated_epoch": now, "cadence_s": 3600, "ok": True,
                 "error": None, "data": {"brief_id": "test-brief",
                 "generated_epoch": now, "delivery": {"state": "not_sent"},
                 "sections": [], "inputs": {}, "stale_required_inputs": [],
                 "selection_high_water": {"loose_end_changes": [0, ""]}}})
PYEOF

# stub `open` on PATH: touches a sentinel if ever invoked
printf '#!/bin/sh\ntouch "%s/open-called"\n' "$STUB" > "$STUB/bin/open"
chmod +x "$STUB/bin/open"

export DASHBOARD_CMD_USAGE="cat '$STUB/usage.json'"
export DASHBOARD_CMD_GIT="cat '$STUB/git.json'"
export DASHBOARD_CMD_CHATS="cat '$STUB/chats.json'"
export DASHBOARD_CMD_AUTOMATION="cat '$STUB/auto_green.json'"
export DASHBOARD_CMD_DECISIONS="cat '$STUB/decisions.json'"
export DASHBOARD_CMD_BRIEF="cat '$STUB/brief.json'"

newhome() { mktemp -d "$ROOT/home.XXXXXX"; }
make_valid_stamp() {
  PYTHONPATH="$REPO/scripts" python3 - "$1" <<'PY'
import os,sys
from mission_control_common import write_install_stamp
home=sys.argv[1]; bindir=os.path.join(home,"bin"); os.makedirs(bindir,exist_ok=True)
for name in ("dashboard","morning-brief","morning-brief-deadman","decision-alert","mission_control_common.py"):
    open(os.path.join(bindir,name),"w").write("runtime "+name+"\n")
    if name != "mission_control_common.py": os.chmod(os.path.join(bindir,name),0o700)
os.makedirs(os.path.join(home,"vendor"),exist_ok=True)
open(os.path.join(home,"index.html"),"w").write("<html></html>\n")
open(os.path.join(home,"vendor","cytoscape.min.js"),"w").write("//vendor\n")
write_install_stamp(bindir,"a"*40,"head",
  ["dashboard","morning-brief","morning-brief-deadman","decision-alert","mission_control_common.py"],
  1783674000,assets={"index.html":os.path.join(home,"index.html"),
  "vendor/cytoscape.min.js":os.path.join(home,"vendor","cytoscape.min.js")})
PY
}

# --- case 1: collect --force writes 12 files, every .json envelope-valid -------
c1() {
  local H; H="$(newhome)"
  MISSION_CONTROL_HOME="$H" bash "$DASH" collect --force >/dev/null 2>&1
  local f miss=0
  for f in usage git chats automation decisions brief; do
    [ -f "$H/data/$f.json" ] || miss=1
    [ -f "$H/data/$f.js" ] || miss=1
  done
  if [ "$miss" != 0 ]; then no "collect --force writes 12 files (some missing)"; return; fi
  if python3 - "$H/data" <<'PYEOF'
import json, os, sys
d = sys.argv[1]
keys = {"schema", "feed", "generated_at", "generated_epoch", "cadence_s", "ok", "error", "data"}
for f in ("usage", "git", "chats", "automation", "decisions", "brief"):
    e = json.load(open(os.path.join(d, f + ".json")))
    assert keys <= set(e), (f, keys - set(e))
    assert e["schema"] == 1 and e["feed"] == f, f
    assert isinstance(e["generated_epoch"], int), f
PYEOF
  then ok "collect --force writes 12 files, all .json envelope-valid"
  else no "collect --force .json not envelope-valid"; fi
}

# --- case 2: .js transport byte-equals .json canonical (incl hostile title) ----
c2() {
  local H; H="$(newhome)"
  MISSION_CONTROL_HOME="$H" bash "$DASH" collect --force >/dev/null 2>&1
  if python3 - "$H/data" <<'PYEOF'
import json, os, sys
d = sys.argv[1]
for f in ("usage", "git", "chats", "automation", "decisions", "brief"):
    jc = open(os.path.join(d, f + ".json")).read()
    js = open(os.path.join(d, f + ".js")).read()
    marker = "window.MC.feeds.%s = " % f
    payload = js[js.index(marker) + len(marker):]
    assert payload.endswith(";"), f
    payload = payload[:-1]
    assert payload == jc, ("byte mismatch", f)          # strip wrapper, byte-equal
    assert json.loads(payload) == json.loads(jc), f     # and deep-equal
# hostile title survives roundtrip; .js is pure ASCII (emoji escaped by ensure_ascii)
raw = open(os.path.join(d, "chats.js"), "rb").read()
assert all(b < 128 for b in raw), "non-ascii bytes in .js"
title = json.loads(open(os.path.join(d, "chats.json")).read())["data"]["nodes"][0]["title"]
assert "\U0001F600" in title and "</script>" in title and "'" in title, title
PYEOF
  then ok ".js == .json canonical incl hostile title (apostrophe+emoji+</script>)"
  else no ".js/.json roundtrip failed"; fi
}

# --- case 3: failing feeder -> that feed ok:false, others written, prior kept --
c3() {
  local H; H="$(newhome)"
  MISSION_CONTROL_HOME="$H" bash "$DASH" collect --force >/dev/null 2>&1
  local before; before="$(cat "$H/data/git.json")"
  sleep 1  # ensure a rewrite would change generated_epoch
  MISSION_CONTROL_HOME="$H" DASHBOARD_CMD_GIT="false" \
    bash "$DASH" collect --force >/dev/null 2>&1
  local after; after="$(cat "$H/data/git.json")"
  if python3 - "$H/data" <<'PYEOF'
import json, os, sys
d = sys.argv[1]
err = json.load(open(os.path.join(d, "git.error.json")))
assert err["ok"] is False and err["error"], err
for f in ("usage", "chats", "automation"):
    e = json.load(open(os.path.join(d, f + ".json")))
    assert e["ok"] is True, f
PYEOF
  then
    if [ "$before" = "$after" ]; then
      ok "failing feeder: git ok:false, 3 others written, prior git.json preserved"
    else no "failing feeder clobbered prior good git.json"; fi
  else no "failing feeder: error note / sibling feeds wrong"; fi
}

# --- case 4: --due honors cadence (fresh skipped, stale re-collected) ----------
c4() {
  local H; H="$(newhome)"
  MISSION_CONTROL_HOME="$H" bash "$DASH" collect --force >/dev/null 2>&1
  local usage_before
  usage_before="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["generated_epoch"])' "$H/data/usage.json")"
  # backdate git well past 6x cadence -> stale
  python3 -c 'import json,sys;p=sys.argv[1];e=json.load(open(p));e["generated_epoch"]=1;json.dump(e,open(p,"w"))' "$H/data/git.json"
  MISSION_CONTROL_HOME="$H" DASHBOARD_CMD_GIT="cat '$STUB/git2.json'" \
    bash "$DASH" collect --due >/dev/null 2>&1
  if python3 - "$H/data" "$usage_before" <<'PYEOF'
import json, os, sys
d, ub = sys.argv[1], int(sys.argv[2])
git = json.load(open(os.path.join(d, "git.json")))
assert git["data"]["repos"][0].get("marker") == "NEW", "stale git NOT re-collected"
usage = json.load(open(os.path.join(d, "usage.json")))
assert usage["generated_epoch"] == ub, "fresh usage WAS re-collected"
PYEOF
  then ok "--due re-collects stale feed, skips fresh feed"
  else no "--due cadence gating wrong"; fi
}

# --- case 5: status exit 0 all-green; nonzero on automation red job ------------
c5() {
  local H rc
  H="$(newhome)"
  MISSION_CONTROL_HOME="$H" bash "$DASH" collect --force >/dev/null 2>&1
  make_valid_stamp "$H"
  MISSION_CONTROL_HOME="$H" bash "$DASH" status >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then ok "status exit 0 on all-green feeds"
  else no "status nonzero on all-green (rc=$rc)"; fi
  H="$(newhome)"
  MISSION_CONTROL_HOME="$H" DASHBOARD_CMD_AUTOMATION="cat '$STUB/auto_red.json'" \
    bash "$DASH" collect --force >/dev/null 2>&1
  MISSION_CONTROL_HOME="$H" bash "$DASH" status >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ]; then ok "status nonzero when automation feed has a red job"
  else no "status exit 0 despite red automation job"; fi
}

# --- case 6: demo builds from fixtures into temp dir, does NOT open ------------
c6() {
  rm -f "$STUB/open-called"
  local out dir brief_cadence
  out="$(PATH="$STUB/bin:$PATH" DASHBOARD_NO_OPEN=1 bash "$DASH" demo 2>&1)"
  dir="$(printf '%s\n' "$out" | sed -n 's/^demo state: //p')"
  brief_cadence="$(python3 - "$dir/data/brief.json" <<'PY' 2>/dev/null
import json, sys
print(json.load(open(sys.argv[1])).get("cadence_s", ""))
PY
)"
  if [ -n "$dir" ] && [ -f "$dir/data/chats.json" ]; then
    if [ ! -f "$STUB/open-called" ] && [ "$brief_cadence" = "300" ]; then
      ok "demo builds contract-valid fixtures into temp dir, no open under DASHBOARD_NO_OPEN=1"
    else no "demo opened unexpectedly or Brief fixture cadence was invalid (cadence=$brief_cadence)"; fi
  else no "demo did not build fixture feeds (dir=$dir)"; fi
  [ -n "$dir" ] && rm -rf "$dir"
}

# --- shell contract: SKIP cleanly when index.html absent; mandatory under flag -
shell_contract() {
  local idx="$REPO/dashboard/index.html"
  if [ ! -f "$idx" ]; then
    if [ "$REQUIRE_SHELL" = "--require-shell" ]; then
      no "shell: dashboard/index.html MISSING (required by --require-shell)"
    else
      echo "SKIP: dashboard/index.html absent — shell checks skipped"
    fi
  else
    if grep -q '=== TOKENS ===' "$idx" && grep -q '=== LAYOUT CSS ===' "$idx" \
       && grep -q '=== RENDERERS ===' "$idx"; then
      ok "shell: three fenced section markers present"
    else no "shell: missing fenced section markers"; fi
    if grep -q 'window.MC' "$idx"; then ok "shell: window.MC present"
    else no "shell: window.MC absent"; fi
    if grep -q 'innerHTML' "$idx"; then no "shell: innerHTML present (must be zero)"
    else ok "shell: zero innerHTML"; fi
    # external http(s) resource loads only (src=/href=/url(...) — not xmlns etc.)
    if grep -Eq '(src|href)[[:space:]]*=[[:space:]]*["'"'"']?https?://|url\([[:space:]]*["'"'"']?https?://' "$idx"; then
      no "shell: external http(s) resource load found"
    else ok "shell: no external http(s) resource loads"; fi
  fi
  # fixtures parse against the envelope — always (independent of index.html)
  if python3 - "$REPO/dashboard/fixtures" <<'PYEOF'
import glob, json, os, sys
d = sys.argv[1]
keys = {"schema", "feed", "generated_at", "generated_epoch", "cadence_s", "ok", "data"}
n = 0
for p in sorted(glob.glob(os.path.join(d, "*.json"))):
    e = json.load(open(p))
    assert keys <= set(e), (p, keys - set(e))
    assert e["schema"] == 1, p
    n += 1
assert n >= 1, "no fixtures found"
PYEOF
  then ok "shell: every dashboard/fixtures/*.json parses against envelope"
  else no "shell: a fixture failed envelope validation"; fi
}


c7() { # defaults must resolve repo-sibling feeders WITHOUT env overrides (live 127 regression)
  local fr; fr="$(mktemp -d)/fixrepo"
  mkdir -p "$fr/scripts" "$fr/dashboard"
  for n in usage-snapshot scan-unfinished-work automation-status; do
    printf '#!/bin/sh\necho "{\\"stub\\": \\"%s\\"}"\n' "$n" > "$fr/scripts/$n"
    chmod +x "$fr/scripts/$n"
  done
  for n in dashboard mission_control_common.py morning-brief morning-brief-deadman; do
    cp "$REPO/scripts/$n" "$fr/scripts/$n"
  done
  mkdir -p "$fr/dashboard/vendor"
  cp "$REPO/dashboard/index.html" "$fr/dashboard/index.html"
  cp "$REPO/dashboard/vendor/cytoscape.min.js" "$fr/dashboard/vendor/cytoscape.min.js"
  # chat-graph stub: honors the run-then-cat compound default
  cgh="$(mktemp -d)"
  printf '#!/bin/sh\nmkdir -p "${CHAT_GRAPH_HOME}/export"\necho "{\\"stub\\": \\"chats\\"}" > "${CHAT_GRAPH_HOME}/export/graph.json"\n' > "$fr/scripts/chat-graph"
  chmod +x "$fr/scripts/chat-graph"
  cat > "$fr/scripts/morning-brief" <<'EOF'
#!/bin/sh
mkdir -p "$MISSION_CONTROL_HOME/morning-brief"
printf '%s\n' '{"schema":1,"brief_id":"stub","generated_epoch":1,"delivery":{"state":"not_sent"},"sections":[],"inputs":{},"stale_required_inputs":[],"selection_high_water":{"loose_end_changes":[0,""]}}' > "$MISSION_CONTROL_HOME/morning-brief/latest.json"
printf '# stub\n' > "$MISSION_CONTROL_HOME/morning-brief/latest.md"
EOF
  chmod +x "$fr/scripts/morning-brief"
  cat > "$fr/scripts/decision-alert" <<'EOF'
#!/bin/sh
cat "$FIXTURE_DECISIONS"
EOF
  chmod +x "$fr/scripts/decision-alert"
  echo '{}' > "$fr/dashboard/jobs.json"
  local mch; mch="$(mktemp -d)"
  if env -u DASHBOARD_CMD_USAGE -u DASHBOARD_CMD_GIT -u DASHBOARD_CMD_CHATS -u DASHBOARD_CMD_AUTOMATION \
       REPO_ROOT="$fr" MISSION_CONTROL_HOME="$mch" CHAT_GRAPH_HOME="$cgh" \
       bash "$DASH" collect --force >/dev/null 2>&1 \
     && [ -f "$mch/data/usage.json" ] && [ -f "$mch/data/git.json" ] \
     && [ -f "$mch/data/chats.json" ] && [ -f "$mch/data/automation.json" ] \
     && [ ! -f "$mch/data/usage.error.json" ]; then
    ok "defaults: repo-sibling feeders resolve without env overrides"
  else
    no "defaults: bare-name regression — a default feeder did not resolve"
  fi
}


c8() { # git feeder exit-1-with-findings is a VALID result (scan-unfinished-work contract)
  local mch stub; mch="$(mktemp -d)"
  stub="$ROOT/git-exit1-stub"
  cat > "$stub" <<'EOF'
#!/bin/sh
printf '%s\n' '{"findings": 3}'
exit 1
EOF
  chmod +x "$stub"
  if DASHBOARD_CMD_GIT="$stub" \
     DASHBOARD_CMD_USAGE='echo {}' DASHBOARD_CMD_CHATS='echo {}' DASHBOARD_CMD_AUTOMATION='echo {}' \
     MISSION_CONTROL_HOME="$mch" bash "$DASH" collect --force >/dev/null 2>&1 \
     && [ -f "$mch/data/git.json" ] && [ ! -f "$mch/data/git.error.json" ]; then
    ok "git feeder exit 1 (findings) accepted as valid"
  else
    no "git feeder exit 1 wrongly treated as failure"
fi
}

c8a() { # env feeder overrides are argv-only; shell metacharacters are rejected
  local mch marker; mch="$(mktemp -d)"; marker="$ROOT/override-pwned"
  DASHBOARD_CMD_USAGE="echo {}; touch $marker" \
    MISSION_CONTROL_HOME="$mch" bash "$DASH" collect --force usage >/dev/null 2>&1
  if [ ! -e "$marker" ] \
     && [ -f "$mch/data/usage.error.json" ] \
     && grep -q "forbidden shell characters" "$mch/data/usage.error.json"; then
    ok "feeder override shell metacharacters are rejected"
  else
    no "feeder override shell metacharacters were not rejected"
  fi
}

c8b() { # chats feed can be fresh while the full graph scan is stale
  local mch; mch="$(mktemp -d)"
  mkdir -p "$mch/data"
  python3 - "$mch/data/chats.json" <<'PYEOF'
import json, sys, time
now = int(time.time())
env = {"schema": 1, "feed": "chats", "generated_at": "now", "generated_epoch": now,
       "cadence_s": 1800, "ok": True, "error": None,
       "data": {"nodes": [], "edges": [], "topics": [],
                "counts": {"last_full_ingest_epoch": None,
                           "last_full_ingest_age_s": None}}}
json.dump(env, open(sys.argv[1], "w"))
PYEOF
  local out; out="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" status 2>/dev/null || true)"
  if printf '%s\n' "$out" | grep -q "unknown full ingest"; then
    ok "status: fresh chats feed still surfaces unknown full graph ingest"
  else
    no "status: unknown full graph ingest hidden behind fresh chats feed"
  fi
}

c9() { # install copies a RUNNABLE runtime with REPO_ROOT baked in (headless plist path)
  local fr; fr="$(mktemp -d)/fixrepo"
  mkdir -p "$fr/scripts" "$fr/dashboard/vendor"
  cp "$REPO/scripts/dashboard" "$fr/scripts/dashboard"
  cp "$REPO/scripts/mission_control_common.py" "$fr/scripts/mission_control_common.py"
  cp "$REPO/scripts/morning-brief" "$fr/scripts/morning-brief"
  cp "$REPO/scripts/morning-brief-deadman" "$fr/scripts/morning-brief-deadman"
  for n in usage-snapshot scan-unfinished-work automation-status; do
    printf '#!/bin/sh\necho "{\\"stub\\": \\"%s\\"}"\n' "$n" > "$fr/scripts/$n"
    chmod +x "$fr/scripts/$n"
  done
  local cgh; cgh="$(mktemp -d)"
  printf '#!/bin/sh\nmkdir -p "${CHAT_GRAPH_HOME}/export"\necho "{\\"stub\\": \\"chats\\"}" > "${CHAT_GRAPH_HOME}/export/graph.json"\n' > "$fr/scripts/chat-graph"
  chmod +x "$fr/scripts/chat-graph"
  cat > "$fr/scripts/decision-alert" <<'EOF'
#!/bin/sh
cat "$FIXTURE_DECISIONS"
EOF
  chmod +x "$fr/scripts/decision-alert"
  echo '{}' > "$fr/dashboard/jobs.json"
  cp "$REPO/dashboard/index.html" "$fr/dashboard/index.html"
  cp "$REPO/dashboard/vendor/cytoscape.min.js" "$fr/dashboard/vendor/cytoscape.min.js"
  ( cd "$fr" && git init -q && git add -A && \
    git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
  # stub launchctl on PATH so any bootstrap no-ops (fixture has no plist template)
  local sbin; sbin="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "$sbin/launchctl"; chmod +x "$sbin/launchctl"
  local mch; mch="$(mktemp -d)"
  PATH="$sbin:$PATH" REPO_ROOT="$fr" MISSION_CONTROL_HOME="$mch" DASHBOARD_INSTALL_NO_LAUNCHD=1 \
    bash "$DASH" install >/dev/null 2>&1
  if [ ! -x "$mch/bin/dashboard" ]; then
    no "install: bin/dashboard missing or not executable"; return; fi
  # baked default must be the REAL repo root, never the mission-control home
  local baked; baked="$(sed -n 's/^REPO_ROOT_DEFAULT="\(.*\)"$/\1/p' "$mch/bin/dashboard")"
  if [ "$baked" != "$fr" ]; then
    no "install: REPO_ROOT_DEFAULT not baked into copy (got '$baked')"; return; fi
  # the copy runs headless — no DASHBOARD_CMD_* overrides, REPO_ROOT unset — and
  # resolves the baked repo's sibling feeders to write every feed.
  if env -u DASHBOARD_CMD_USAGE -u DASHBOARD_CMD_GIT -u DASHBOARD_CMD_CHATS \
         -u DASHBOARD_CMD_AUTOMATION -u DASHBOARD_CMD_DECISIONS -u REPO_ROOT \
         FIXTURE_DECISIONS="$REPO/dashboard/fixtures/decisions.json" \
         MISSION_CONTROL_HOME="$mch" CHAT_GRAPH_HOME="$cgh" \
         bash "$mch/bin/dashboard" collect --force >/dev/null 2>&1 \
     && [ -f "$mch/data/usage.json" ] && [ -f "$mch/data/git.json" ] \
     && [ -f "$mch/data/chats.json" ] && [ -f "$mch/data/automation.json" ] \
     && [ -f "$mch/data/decisions.json" ] \
     && [ -f "$mch/data/brief.json" ]; then
    ok "install: baked bin/dashboard resolves feeders headless + writes all feeds"
  else
    no "install: baked copy did not write feeds headless"
  fi
  # The installed engine must import its adjacent stamped common module, not a
  # later dirty checkout copy at the baked feeder root.
  printf 'raise RuntimeError("POISONED_REPO_COMMON")\n' > "$fr/scripts/mission_control_common.py"
  local status_out; status_out="$(env -u REPO_ROOT MISSION_CONTROL_HOME="$mch" \
    MISSION_CONTROL_NOW_EPOCH="$(date +%s)" bash "$mch/bin/dashboard" status 2>&1 || true)"
  if printf '%s\n' "$status_out" | grep -q '^install' && \
     ! printf '%s\n' "$status_out" | grep -q 'POISONED_REPO_COMMON\|Traceback'; then
    ok "install: dashboard imports adjacent stamped common despite repo drift"
  else
    no "install: dashboard loaded the dirty repo common instead of adjacent bin"
  fi
}

c10() { # the REAL plist template, substituted as install does, must point at an
        # exec path INSIDE the mission-control home — not a double-prefixed dead path
        # (fresh-eyes audit 2026-07-03: __HOME__/.mission-control + __HOME__->$MCHOME).
  local tmpl="$REPO/launchd/com.gillettes.mission-control.plist.template"
  if [ ! -f "$tmpl" ]; then no "plist: real template missing at $tmpl"; return; fi
  local mch; mch="$(mktemp -d)/.mission-control"
  local out; out="$(mktemp)"
  # mirror do_install's substitution EXACTLY
  sed -e "s|__MCHOME__|$mch|g" -e "s|__HOME__|$HOME|g" -e "s|__REPO__|$REPO|g" "$tmpl" > "$out"
  # extract the exec path = the ProgramArguments <string> ending in /dashboard
  local execpath; execpath="$(grep -oE '<string>[^<]*/bin/dashboard</string>' "$out" | head -1 | sed -E 's|</?string>||g')"
  if printf '%s' "$execpath" | grep -q '\.mission-control/\.mission-control'; then
    no "plist: DOUBLE-PREFIX in exec path ($execpath)"; return; fi
  if [ "$execpath" != "$mch/bin/dashboard" ]; then
    no "plist: exec path '$execpath' != installed runtime '$mch/bin/dashboard'"; return; fi
  # and it lints
  if command -v plutil >/dev/null 2>&1 && ! plutil -lint "$out" >/dev/null 2>&1; then
    no "plist: substituted template fails plutil -lint"; return; fi
  ok "plist: real template substitutes to the runtime path, no double-prefix"
}

c11() { # render layer EXECUTION coverage — runs the real renderers over fixtures
        # under a node DOM shim (ER-087 FIX 1: greps alone let a broken renderer ship).
  if ! command -v node >/dev/null 2>&1; then ok "render: node absent — smoke skipped (CI installs node)"; return; fi
  if node "$HERE/dashboard-render-smoke.js" "$REPO" >/dev/null 2>&1; then
    ok "render: all tabs execute over fixtures (node smoke)"
  else
    no "render: a tab failed to render — $(node "$HERE/dashboard-render-smoke.js" "$REPO" 2>&1 | grep -m1 FAIL)"
  fi
  # negative control: a throwing renderer MUST be caught (proves the smoke isn't inert)
  local scratch; scratch="$(mktemp -d)"; cp -r "$REPO/dashboard" "$scratch/"; cp -r "$REPO/scripts" "$scratch/"
  perl -pi -e 's/(function renderGit\(main\) \{)/$1 throw new Error("x");/' "$scratch/dashboard/index.html"
  if node "$scratch/scripts/dashboard-render-smoke.js" "$scratch" >/dev/null 2>&1; then
    no "render: negative control FAILED — smoke did not catch a throwing renderer"
  else
    ok "render: smoke catches a throwing renderer (negative control)"
  fi
  rm -rf "$scratch"
}

c12() { # chats is slow; decisions and brief consume it and must follow in order
  local order; order="$(grep -oE '\("(usage|git|chats|automation|decisions)"' "$DASH" | sed -E 's/[("]//g' | tr '\n' ' ')"
  local full; full="$(grep -oE '\("(usage|git|chats|automation|decisions|brief)"' "$DASH" | sed -E 's/[("]//g' | tr '\n' ' ')"
  case "$full" in
    *chats\ decisions\ brief\ ) ok "feed order: chats, decisions, then brief are last ($full)" ;;
    *) no "feed order: dependent decisions/brief do not follow slow chats ($full)" ;;
  esac
}
c13() { # FIX 6: the data/ dir must be 0700, not world-readable
  local mch; mch="$(mktemp -d)/mc"
  DASHBOARD_CMD_USAGE='echo {}' DASHBOARD_CMD_GIT='echo {}' DASHBOARD_CMD_CHATS='echo {}' DASHBOARD_CMD_AUTOMATION='echo {}' DASHBOARD_CMD_DECISIONS='echo {}' DASHBOARD_CMD_BRIEF='echo {}' \
    MISSION_CONTROL_HOME="$mch" bash "$DASH" collect --force >/dev/null 2>&1
  local p; p="$(stat -f '%Lp' "$mch/data" 2>/dev/null || stat -c '%a' "$mch/data" 2>/dev/null)"
  [ "$p" = "700" ] && ok "data dir perms 700 (got $p)" || no "data dir world-readable (got $p, want 700)"
}

c14() { # isolated install wires composer/deadman/common + all three plists
  local h mch sbin; h="$(mktemp -d)"; mch="$h/state"; sbin="$(mktemp -d)"
  cat > "$sbin/launchctl" <<'EOF'
#!/bin/sh
case "$1" in
  print) case "$2" in *morning-brief-deadman) exit 0;; *) exit 1;; esac ;;
  bootstrap) basename "$3" >> "$LAUNCH_CAPTURE"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$sbin/launchctl"
  HOME="$h" PATH="$sbin:$PATH" REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" LAUNCH_CAPTURE="$h/bootstrapped" \
    DASHBOARD_INSTALL_ACTIVATE_GATED=1 \
    bash "$DASH" install >/dev/null 2>&1
  local miss=0 p
  [ -x "$mch/bin/morning-brief" ] || miss=1
  [ -x "$mch/bin/morning-brief-deadman" ] || miss=1
  [ -x "$mch/bin/decision-alert" ] || miss=1
  [ -f "$mch/bin/mission_control_common.py" ] || miss=1
  for p in com.gillettes.mission-control.plist com.gillettes.outcome-extractor.plist com.gillettes.morning-brief.plist com.gillettes.morning-brief-deadman.plist; do
    [ -f "$h/Library/LaunchAgents/$p" ] || miss=1
    plutil -lint "$h/Library/LaunchAgents/$p" >/dev/null 2>&1 || miss=1
    grep -q '__MCHOME__\|__HOME__' "$h/Library/LaunchAgents/$p" && miss=1
  done
  grep -qx 'com.gillettes.morning-brief.plist' "$h/bootstrapped" || miss=1
  grep -qx 'com.gillettes.outcome-extractor.plist' "$h/bootstrapped" || miss=1
  grep -q '<string>extract-outcomes</string>' \
    "$h/Library/LaunchAgents/com.gillettes.outcome-extractor.plist" || miss=1
  if [ "$miss" = 0 ]; then ok "install: composer, decisions, deadman, common policy, and plists wire in isolation"
  else no "install: Morning Brief runtime/plist wiring incomplete"; fi
}

c14a() { # default install must not write/bootstrap activation-gated jobs
  local h mch sbin p miss=0; h="$(mktemp -d)"; mch="$h/state"; sbin="$(mktemp -d)"
  cat > "$sbin/launchctl" <<'EOF'
#!/bin/sh
case "$1" in
  print) exit 1 ;;
  bootstrap) basename "$3" >> "$LAUNCH_CAPTURE"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$sbin/launchctl"
  HOME="$h" PATH="$sbin:$PATH" REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" \
    LAUNCH_CAPTURE="$h/bootstrapped" bash "$DASH" install >/dev/null 2>&1
  [ -f "$h/Library/LaunchAgents/com.gillettes.mission-control.plist" ] || miss=1
  for p in com.gillettes.outcome-extractor.plist com.gillettes.morning-brief.plist \
           com.gillettes.morning-brief-deadman.plist; do
    [ ! -e "$h/Library/LaunchAgents/$p" ] || miss=1
    grep -qx "$p" "$h/bootstrapped" 2>/dev/null && miss=1
  done
  if [ "$miss" = 0 ]; then ok "default install leaves activation-gated jobs uninstalled"
  else no "default install wrote or bootstrapped an activation-gated job"; fi
}

c15() { # reading an old sidecar must preserve compose age instead of refreshing it
  local mch old_epoch out; mch="$(mktemp -d)"; old_epoch="$(( $(date +%s) - 172800 ))"
  mkdir -p "$mch/morning-brief"
  python3 - "$mch/morning-brief/latest.json" "$old_epoch" <<'PY'
import json, sys
path, epoch = sys.argv[1], int(sys.argv[2])
json.dump({"brief_id": "stale-fixture", "generated_epoch": epoch,
           "generated_at": "2000-01-01T00:00:00Z", "sections": {}}, open(path, "w"))
PY
  env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$mch" \
    bash "$DASH" collect --force brief >/dev/null 2>&1
  out="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" status 2>/dev/null || true)"
  if [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["generated_epoch"])' "$mch/data/brief.json")" = "$old_epoch" ] \
     && printf '%s\n' "$out" | grep -Eqi 'brief.*(stale|red|aging)'; then
    ok "brief freshness preserves the sidecar compose age"
  else
    no "brief freshness relabeled a stale sidecar as current"
  fi
}

c16() { # malformed Brief compose timestamps fail one feed without replacing last-good
  local mch before value out miss=0; mch="$(mktemp -d)"; mkdir -p "$mch/morning-brief"
  python3 - "$mch/morning-brief/latest.json" <<'PY'
import json, sys, time
now = int(time.time())
json.dump({"brief_id": "valid-fixture", "generated_epoch": now,
           "generated_at": "2026-07-10T09:00:00Z", "sections": {}}, open(sys.argv[1], "w"))
PY
  env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$mch" \
    bash "$DASH" collect --force brief >/dev/null 2>&1
  before="$(shasum -a 256 "$mch/data/brief.json" | awk '{print $1}')"
  for value in '"oops"' '["oops"]' '[]' '{}' 'null' '0' 'true'; do
    python3 - "$mch/morning-brief/latest.json" "$value" <<'PY'
import json, sys
json.dump({"brief_id": "bad-fixture", "generated_epoch": json.loads(sys.argv[2]),
           "sections": {}}, open(sys.argv[1], "w"))
PY
    env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$mch" \
      bash "$DASH" collect --force brief >/dev/null 2>&1
    [ -f "$mch/data/brief.error.json" ] || miss=1
    [ -f "$mch/data/brief.error.js" ] && grep -q 'feedErrors.brief' "$mch/data/brief.error.js" || miss=1
    [ "$(shasum -a 256 "$mch/data/brief.json" | awk '{print $1}')" = "$before" ] || miss=1
    out="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" status 2>/dev/null || true)"
    printf '%s\n' "$out" | grep -Eqi 'brief.*error' || miss=1
  done
  grep -q 'data/brief.error.js' "$REPO/dashboard/index.html" || miss=1
  grep -q 'MC.feedErrors' "$REPO/dashboard/index.html" || miss=1
  if [ "$miss" = 0 ]; then ok "brief rejects malformed timestamps and surfaces last-good refresh errors"
  else no "brief accepted malformed compose timestamps or replaced last-good"; fi
}

c17() { # feeder stderr is sanitized before JSON/JS error persistence
  local mch stub status miss=0; mch="$(mktemp -d)"; stub="$ROOT/sensitive-error-stub"
  cat > "$stub" <<'EOF'
#!/bin/sh
printf '%s\n' 'failed sk-abcdefghijklmnopqrstuvwxyz123456 operator@example.com 415-555-1212 forbidden-term' >&2
exit 2
EOF
  chmod +x "$stub"
  MISSION_CONTROL_EGRESS_DENYLIST='forbidden-term' DASHBOARD_CMD_USAGE="$stub" \
    MISSION_CONTROL_HOME="$mch" bash "$DASH" collect --force usage >/dev/null 2>&1
  for artifact in "$mch/data/usage.error.json" "$mch/data/usage.error.js"; do
    [ -f "$artifact" ] || miss=1
    grep -Eq 'sk-abcdefghijklmnopqrstuvwxyz123456|operator@example.com|415-555-1212|forbidden-term' "$artifact" && miss=1
  done
  python3 - "$mch/data/usage.error.json" <<'PY' || miss=1
import json,sys
d=json.load(open(sys.argv[1])); c=d["egress_counters"]
assert d["ok"] is False
assert c["dropped_fields"] == 1
assert c["reason_secret"] == c["reason_email"] == c["reason_phone"] == c["reason_denylist"] == 1
PY
  status="$(MISSION_CONTROL_HOME="$mch" bash "$DASH" status 2>/dev/null || true)"
  printf '%s\n' "$status" | grep -Eqi 'usage.*error' || miss=1
  printf '%s\n' "$status" | grep -Eq 'sk-abcdefghijklmnopqrstuvwxyz123456|operator@example.com|415-555-1212|forbidden-term' && miss=1
  if [ "$miss" = 0 ]; then ok "error persistence sanitizes secrets, PII, and denylisted terms"
  else no "error persistence leaked sensitive feeder stderr"; fi
}

c18() { # dashboard dismiss routes to the transactional queue and executes no action
  local mch created id state marker; mch="$(mktemp -d)"; marker="$mch/must-not-run"
  created="$(MISSION_CONTROL_HOME="$mch" "$REPO/scripts/decision-alert" ingest \
    --source-kind manual --source-key dashboard-dismiss --text 'Choose dashboard test' \
    --trust structured --provenance manual \
    --action-json '["touch","'$marker'"]' --json)" || { no "dashboard decide fixture ingest failed"; return; }
  id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$created")"
  env -u DASHBOARD_CMD_DECISIONS REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" \
    bash "$DASH" collect --force decisions >/dev/null 2>&1
  python3 - "$mch/data/decisions.json" "$id" <<'PY' || { no "dashboard decision fixture was not pinned"; return; }
import json,sys
d=json.load(open(sys.argv[1]))["data"]
assert sys.argv[2] in [x["id"] for x in d["pinned"]]
PY
  env -u DASHBOARD_CMD_DECISIONS REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" \
    bash "$DASH" decide dismiss "$id" >/dev/null 2>&1
  state="$(MISSION_CONTROL_HOME="$mch" "$REPO/scripts/decision-alert" list --state dismissed --json)"
  if [ ! -e "$marker" ] && printf '%s' "$state" | grep -Fq "$id" &&
     python3 - "$mch/data/decisions.json" "$id" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))["data"]
assert sys.argv[2] not in [x["id"] for x in d["pinned"]]
PY
  then
    ok "dashboard dismiss refreshes pinned feed without executing action"
  else
    no "dashboard dismiss failed, left stale pinned data, or executed stored action"
  fi

  # A concurrent decisions collector must not let dismiss claim a refreshed UI.
  local locked_id locked_created
  locked_created="$(MISSION_CONTROL_HOME="$mch" "$REPO/scripts/decision-alert" ingest \
    --source-kind manual --source-key dashboard-lock --text 'Choose locked test' \
    --trust structured --provenance manual --json)" || { no "dashboard lock fixture ingest failed"; return; }
  locked_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$locked_created")"
  env -u DASHBOARD_CMD_DECISIONS REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" \
    bash "$DASH" collect --force decisions >/dev/null 2>&1
  mkdir -p "$mch/data/.decisions.lock"
  if env -u DASHBOARD_CMD_DECISIONS REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" \
       bash "$DASH" decide dismiss "$locked_id" >/dev/null 2>&1; then
    no "dashboard dismiss claimed refresh while decisions feed was locked"
  else
    ok "dashboard dismiss fails visibly when pinned feed refresh is locked"
  fi
  rmdir "$mch/data/.decisions.lock"
}

c19() { # code-only install cannot write or bootstrap launchd jobs
  local mch fakehome; mch="$(mktemp -d)"; fakehome="$(mktemp -d)"
  if HOME="$fakehome" MISSION_CONTROL_HOME="$mch" REPO_ROOT="$REPO" \
       DASHBOARD_INSTALL_NO_LAUNCHD=1 bash "$DASH" install >/dev/null 2>&1 &&
     [ -x "$mch/bin/dashboard" ] && [ -x "$mch/bin/decision-alert" ] &&
     [ ! -d "$fakehome/Library/LaunchAgents" ]; then
    ok "code-only install updates runtime without launchd side effects"
  else
    no "code-only install wrote launchd state or missed runtime files"
  fi
}

c20() { # daily brief validity: a same-day brief past 6x cadence is NOT stale in status
  local mch out NOW
  # Anchor to local noon today (like c23) so same-local-day + valid_until are
  # TZ/date-proof — a naive `now-7200` flakes stale in the ~2h after local midnight.
  NOW="$(python3 -c 'import time;lt=time.localtime();print(int(time.mktime((lt.tm_year,lt.tm_mon,lt.tm_mday,12,0,0,0,0,-1))))')"
  mch="$(mktemp -d)"; mkdir -p "$mch/data"
  python3 - "$mch/data/brief.json" "$REPO/scripts" "$NOW" <<'PY'
import json, sys, time
sys.path.insert(0, sys.argv[2])
from mission_control_common import next_local_midnight
now = int(sys.argv[3]); gen = now - 7200      # 10:00 local: same day, > 6x cadence old
env = {"schema": 1, "feed": "brief", "generated_at": "t", "generated_epoch": gen,
       "cadence_s": 300, "ok": True, "error": None,
       "valid_until": next_local_midnight(gen),
       "data": {"brief_id": "today", "generated_epoch": gen}}
json.dump(env, open(sys.argv[1], "w"))
PY
  out="$(MISSION_CONTROL_HOME="$mch" MISSION_CONTROL_NOW_EPOCH="$NOW" bash "$DASH" status 2>/dev/null || true)"
  if printf '%s\n' "$out" | grep -E '^brief' | grep -Eqi 'stale|aging'; then
    no "status flags a same-day brief stale on poll cadence (validity ignored)"
  else
    ok "status honors daily brief validity: same-day brief past 6x cadence not stale"
  fi
}

c21() { # install stamps provenance from committed HEAD; verify detects runtime drift
  command -v git >/dev/null 2>&1 || { ok "install-stamp: git absent — provenance test skipped"; return; }
  local gr mch head; gr="$(mktemp -d)/repo"; mkdir -p "$gr/scripts" "$gr/dashboard/vendor"
  local n
  for n in dashboard mission_control_common.py morning-brief morning-brief-deadman decision-alert; do
    cp "$REPO/scripts/$n" "$gr/scripts/$n"
  done
  # Deployment assets are part of the shipped surface: install must stamp them from
  # the SAME committed HEAD as the runtimes, and verify must catch their drift.
  printf '<html>shell %s</html>\n' "render-js" > "$gr/dashboard/index.html"
  printf '// vendored graph engine\n' > "$gr/dashboard/vendor/cytoscape.min.js"
  ( cd "$gr" && git init -q && git add -A && \
    git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
  head="$(git -C "$gr" rev-parse HEAD)"; mch="$(mktemp -d)"
  mkdir -p "$mch/vendor"; printf 'stale\n' > "$mch/vendor/removed-upstream.js"
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1
  if [ ! -f "$mch/bin/install-stamp.json" ]; then no "install-stamp: no stamp written"; return; fi
  if python3 - "$mch/bin" "$head" "$REPO/scripts" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[3])
from mission_control_common import verify_install_stamp
bindir, head = sys.argv[1], sys.argv[2]
stamp = json.load(open(os.path.join(bindir, "install-stamp.json")))
assert stamp["provenance"] == "head", stamp
assert stamp["head_sha"] == head, stamp
# assets stamped from HEAD alongside the bin runtimes
assert "index.html" in (stamp.get("assets") or {}), stamp
assert "vendor/cytoscape.min.js" in (stamp.get("assets") or {}), stamp
assert not os.path.exists(os.path.join(os.path.dirname(bindir), "vendor", "removed-upstream.js")), \
       "install must remove stale vendor assets not present in HEAD"
assert verify_install_stamp(bindir)["ok"], "clean install must verify"
# mode drift is operational drift even when bytes still hash-match.
os.chmod(os.path.join(bindir, "morning-brief"), 0o600)
v = verify_install_stamp(bindir)
assert not v["ok"] and "morning-brief" in v["mismatches"], v
os.chmod(os.path.join(bindir, "morning-brief"), 0o700)
assert verify_install_stamp(bindir)["ok"], "restored executable mode must verify"
# drift: mutate an installed runtime — verify must catch it
with open(os.path.join(bindir, "morning-brief"), "a") as fh:
    fh.write("\n# drift\n")
v = verify_install_stamp(bindir)
assert not v["ok"] and "morning-brief" in v["mismatches"], v
# drift: mutate the render shell (an asset) — verify must catch it too
home = os.path.dirname(bindir)
with open(os.path.join(home, "index.html"), "a") as fh:
    fh.write("<!-- drift -->\n")
v = verify_install_stamp(bindir)
assert "index.html" in v["mismatches"], v
PY
  then ok "install-stamp: committed HEAD provenance + runtime AND asset drift are detected"
  else no "install-stamp: provenance or drift verification failed"; fi
}

c22() { # _wrap copies the brief sidecar's valid_until into the collected envelope
  local mch; mch="$(mktemp -d)"; mkdir -p "$mch/morning-brief"
  python3 - "$mch/morning-brief/latest.json" <<'PY'
import json, sys, time
now = int(time.time())
json.dump({"brief_id": "valid-fixture", "generated_epoch": now,
           "generated_at": "2026-07-10T09:00:00Z", "valid_until": now + 50000,
           "sections": {}}, open(sys.argv[1], "w"))
PY
  env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$mch" \
    bash "$DASH" collect --force brief >/dev/null 2>&1
  if python3 - "$mch/data/brief.json" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))
assert e.get("valid_until") and int(e["valid_until"]) > int(e["generated_epoch"]), e
PY
  then ok "collect copies the brief sidecar valid_until into the envelope (_wrap)"
  else no "collect dropped the brief valid_until on the way through _wrap"; fi
}

c23() { # a same-day delivered brief composed before valid_until existed is
  # migrated on the next compose, and the dashboard then reports it fresh (rc=0)
  # instead of stale — regression for the "brief stale all day" trust defect.
  local H rc BRIEF NOW GEN RAWCHATS EXPECTED AFTER out send_out
  H="$(newhome)"; BRIEF="$REPO/scripts/morning-brief"
  make_valid_stamp "$H"
  # Anchor to local noon today so same-local-day + valid_until are TZ/date-proof.
  NOW="$(python3 -c 'import time;lt=time.localtime();print(int(time.mktime((lt.tm_year,lt.tm_mon,lt.tm_mday,12,0,0,0,0,-1))))')"
  GEN=$((NOW - 7200))   # 10:00 local: same day, but > 6x brief cadence (1800s) old
  RAWCHATS="$H/chats_raw.json"
  printf '{"nodes":[],"edges":[],"topics":[],"counts":{"last_full_ingest_age_s":0,"full_ingest_state":"fresh","full_ingest_stale":false}}\n' > "$RAWCHATS"
  mkdir -p "$H/morning-brief/delivery"
  python3 - "$H/morning-brief" "$GEN" <<'PYEOF'
import json, os, sys
home, gen = sys.argv[1], int(sys.argv[2])
bid = "legacy-brief"
# Legacy sidecar: delivered, same local day, NO valid_until (pre-field brief).
json.dump({"schema": 1, "brief_id": bid, "generated_epoch": gen,
           "generated_at": "2026-01-01T00:00:00Z", "sections": [], "inputs": {},
           "stale_required_inputs": [],
           "selection_high_water": {"loose_end_changes": [0, ""]},
           "delivery": {"state": "delivered", "confirmed_chunks": 1, "total_chunks": 1}},
          open(os.path.join(home, "latest.json"), "w"), indent=2, sort_keys=True)
open(os.path.join(home, "latest.md"), "w").write("# Legacy brief\n")
json.dump({"schema": 1, "brief_id": bid, "state": "delivered",
           "confirmed_chunks": 1, "total_chunks": 1, "delivered_at": gen},
          open(os.path.join(home, "delivery", bid + ".json"), "w"))
PYEOF
  # PRE: builtin reads the legacy sidecar (no valid_until) -> brief stale -> rc!=0.
  env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$H" MISSION_CONTROL_NOW_EPOCH="$NOW" \
    DASHBOARD_CMD_CHATS="cat '$RAWCHATS'" bash "$DASH" collect --force >/dev/null 2>&1
  env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$H" MISSION_CONTROL_NOW_EPOCH="$NOW" \
    bash "$DASH" status >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then no "brief-migrate setup: legacy brief was not stale pre-migration"; return; fi
  # A no-arg compose defers (no re-send) and migrates valid_until in place.
  MISSION_CONTROL_HOME="$H" MORNING_BRIEF_NOW_EPOCH="$NOW" "$BRIEF" >/dev/null 2>&1
  cp "$H/morning-brief/latest.json" "$H/latest.after-first.json"
  cp "$H/morning-brief/latest.md" "$H/latest.after-first.md"
  cp "$H/morning-brief/delivery/legacy-brief.json" "$H/receipt.after-first.json"
  # A second compose must be byte-idempotent: no sidecar, Markdown, or receipt rewrite.
  MISSION_CONTROL_HOME="$H" MORNING_BRIEF_NOW_EPOCH="$NOW" "$BRIEF" >/dev/null 2>&1
  if ! cmp -s "$H/latest.after-first.json" "$H/morning-brief/latest.json" ||
     ! cmp -s "$H/latest.after-first.md" "$H/morning-brief/latest.md" ||
     ! cmp -s "$H/receipt.after-first.json" "$H/morning-brief/delivery/legacy-brief.json"; then
    no "brief-migrate: second compose was not byte-idempotent"; return
  fi
  # POST: collect re-derives brief.json from the migrated sidecar; status reads fresh.
  env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$H" MISSION_CONTROL_NOW_EPOCH="$NOW" \
    DASHBOARD_CMD_CHATS="cat '$RAWCHATS'" bash "$DASH" collect --force >/dev/null 2>&1
  env -u DASHBOARD_CMD_BRIEF MISSION_CONTROL_HOME="$H" MISSION_CONTROL_NOW_EPOCH="$NOW" \
    bash "$DASH" status >/dev/null 2>&1; rc=$?
  if ! python3 - "$H" "$GEN" <<'PYEOF'
import json, os, sys, time
home, gen = sys.argv[1], int(sys.argv[2])
latest = json.load(open(os.path.join(home, "morning-brief", "latest.json")))
brief = json.load(open(os.path.join(home, "data", "brief.json")))
local = time.localtime(gen)
expected = int(time.mktime((local.tm_year, local.tm_mon, local.tm_mday + 1,
                            0, 0, 0, 0, 0, -1)))
assert latest.get("valid_until") == expected, (latest.get("valid_until"), expected)
assert brief.get("valid_until") == expected, (brief.get("valid_until"), expected)
assert latest["delivery"]["state"] == "delivered", "delivery must be untouched"
PYEOF
  then no "brief-migrate: both sidecars not stamped with valid_until (or delivery mutated)"; return; fi
  if [ "$rc" -eq 0 ]; then ok "same-day delivered brief migrated -> dashboard status rc=0 (was stale)"
  else no "brief-migrate: status still nonzero after migration (rc=$rc)"; fi
  EXPECTED="$(python3 - "$GEN" <<'PY'
import sys, time
local = time.localtime(int(sys.argv[1]))
print(int(time.mktime((local.tm_year, local.tm_mon, local.tm_mday + 1,
                       0, 0, 0, 0, 0, -1))))
PY
)"
  AFTER=$((EXPECTED + 1))
  out="$(MISSION_CONTROL_HOME="$H" MISSION_CONTROL_NOW_EPOCH="$AFTER" bash "$DASH" status 2>/dev/null || true)"
  if printf '%s\n' "$out" | grep -E '^brief' | grep -qi 'stale'; then
    ok "brief-migrate validity expires exactly after next local midnight"
  else
    no "brief-migrate: exact validity horizon did not become stale"
  fi
  send_out="$(MISSION_CONTROL_HOME="$H" MORNING_BRIEF_NOW_EPOCH="$NOW" \
    MORNING_BRIEF_CHAT_ID=1 MORNING_BRIEF_SEND_BIN=/usr/bin/false \
    "$BRIEF" --send 2>&1)" || { no "brief-migrate: delivered no-resend check failed"; return; }
  if printf '%s\n' "$send_out" | grep -q 'delivery already complete'; then
    ok "brief-migrate delivered receipt prevents re-send"
  else
    no "brief-migrate: delivered brief did not take no-resend path"
  fi
}

c24() { # ER-109 round 6: installer honesty + safety. Each pathological input must
  # FAIL LOUD (nonzero rc + no false "head" stamp), never silently succeed.
  command -v git >/dev/null 2>&1 || { ok "install-safety: git absent — skipped"; return; }
  _mkrepo() { # -> committed repo path with all runtimes + index.html + vendor at HEAD
    local gr; gr="$(mktemp -d)/repo"; mkdir -p "$gr/scripts" "$gr/dashboard/vendor"; local n
    for n in dashboard mission_control_common.py morning-brief morning-brief-deadman decision-alert; do
      cp "$REPO/scripts/$n" "$gr/scripts/$n"
    done
    printf '<html>shell HEAD</html>\n' > "$gr/dashboard/index.html"
    printf '// vendor HEAD\n' > "$gr/dashboard/vendor/cytoscape.min.js"
    ( cd "$gr" && git init -q && git add -A && \
      git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
    echo "$gr"
  }
  local gr mch rc prov fails=0

  # (a) asset missing at HEAD but present in the worktree must NOT be installed and
  # stamped "head" — that fallback is a provenance lie. Expect: rc!=0, no stamp.
  gr="$(_mkrepo)"; mch="$(mktemp -d)"
  ( cd "$gr" && git rm -q --cached dashboard/index.html && \
    git -c user.email=t@t -c user.name=t commit -qm drop-index-from-head ) >/dev/null 2>&1
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { no "install-safety(a): worktree-fallback of a not-at-HEAD asset returned rc=0"; fails=1; }
  [ ! -f "$mch/bin/install-stamp.json" ] || { no "install-safety(a): stamped a head install despite a worktree fallback"; fails=1; }

  # (b) an asset deleted from the repo (absent at HEAD AND worktree) must not remain
  # installed and get stamped under the new HEAD. Expect: rc!=0, stale shell removed.
  gr="$(_mkrepo)"; mch="$(mktemp -d)"; mkdir -p "$mch/vendor"
  printf 'OLD-INDEX\n' > "$mch/index.html"; printf 'OLD\n' > "$mch/vendor/removed.js"
  ( cd "$gr" && git rm -q dashboard/index.html && \
    git -c user.email=t@t -c user.name=t commit -qm drop-index-everywhere ) >/dev/null 2>&1
  rm -f "$gr/dashboard/index.html"
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { no "install-safety(b): a deleted-upstream asset install returned rc=0"; fails=1; }
  [ ! -f "$mch/bin/install-stamp.json" ] || { no "install-safety(b): stamped a deleted-asset install as valid"; fails=1; }
  [ "$(cat "$mch/index.html" 2>/dev/null)" != "OLD-INDEX" ] || { no "install-safety(b): stale shell lingered"; fails=1; }

  # (c) a blocked/unwritable destination must not return rc=0 while silently omitting
  # the file. A directory at the dest path makes the write fail. Expect: rc!=0.
  gr="$(_mkrepo)"; mch="$(mktemp -d)"; mkdir -p "$mch/bin/decision-alert"
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { no "install-safety(c): unwritable destination returned rc=0"; fails=1; }
  [ ! -f "$mch/bin/install-stamp.json" ] || { no "install-safety(c): stamped despite a failed write"; fails=1; }

  # (e) a required runtime source missing at HEAD must be a hard failure, not a
  # silent skip that stamps only the remaining runtimes.
  gr="$(_mkrepo)"; mch="$(mktemp -d)"
  ( cd "$gr" && git rm -q scripts/decision-alert && \
    git -c user.email=t@t -c user.name=t commit -qm drop-required-runtime ) >/dev/null 2>&1
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { no "install-safety(e): missing required runtime at HEAD returned rc=0"; fails=1; }
  [ ! -f "$mch/bin/install-stamp.json" ] || { no "install-safety(e): stamped despite missing required runtime"; fails=1; }

  # (f) a required vendor asset missing at HEAD must be a hard failure. The old
  # vendor loop swallowed the failed copy and stamped only index.html.
  gr="$(_mkrepo)"; mch="$(mktemp -d)"
  ( cd "$gr" && git rm -q dashboard/vendor/cytoscape.min.js && \
    git -c user.email=t@t -c user.name=t commit -qm drop-required-vendor ) >/dev/null 2>&1
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { no "install-safety(f): missing required vendor asset at HEAD returned rc=0"; fails=1; }
  [ ! -f "$mch/bin/install-stamp.json" ] || { no "install-safety(f): stamped despite missing required vendor asset"; fails=1; }

  # (g) a stamp destination that cannot be replaced must fail the whole install.
  gr="$(_mkrepo)"; mch="$(mktemp -d)"; mkdir -p "$mch/bin/install-stamp.json"
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { no "install-safety(g): unwritable install-stamp destination returned rc=0"; fails=1; }

  # (d) a symlinked destination must NOT be followed (writing OUTSIDE the target dir).
  # Expect: the outside file is untouched and rc!=0.
  gr="$(_mkrepo)"; mch="$(mktemp -d)"; local outside; outside="$(mktemp -d)/secret"
  printf 'DO-NOT-TOUCH\n' > "$outside"; mkdir -p "$mch/bin"; ln -s "$outside" "$mch/bin/morning-brief"
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$(cat "$outside" 2>/dev/null)" = "DO-NOT-TOUCH" ] || { no "install-safety(d): install wrote THROUGH a symlink, escaping the target dir"; fails=1; }
  [ "$rc" -ne 0 ] || { no "install-safety(d): symlinked destination returned rc=0"; fails=1; }

  # sanity: a clean committed repo still installs green (fail-loud only fires on the
  # pathological inputs above, never on a normal reinstall).
  gr="$(_mkrepo)"; mch="$(mktemp -d)"
  DASHBOARD_INSTALL_NO_LAUNCHD=1 REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  prov="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["provenance"])' "$mch/bin/install-stamp.json" 2>/dev/null)"
  { [ "$rc" -eq 0 ] && [ "$prov" = head ]; } || { no "install-safety: a clean committed install regressed (rc=$rc prov=$prov)"; fails=1; }

  [ "$fails" = 0 ] && ok "install-safety: missing required runtime/asset, deleted asset, unwritable file/stamp, and symlink dests all fail loud; clean install still green"
}

c25() { # install integrity is always visible and fail-closed in status
  local mch now out rc; mch="$(mktemp -d)"; now=1783674000
  mkdir -p "$mch/data"
  python3 - "$mch/data" "$now" <<'PY'
import json, os, sys
root, now = sys.argv[1], int(sys.argv[2])
cadences={"automation":300,"usage":1800,"git":900,"chats":1800,"decisions":300,"brief":300}
for name,cadence in cadences.items():
    data={"counts":{}} if name != "automation" else {"jobs":[],"counts":{}}
    if name == "chats":
        data={"nodes":[],"counts":{"last_full_ingest_age_s":0,
              "full_ingest_state":"fresh","full_ingest_stale":False}}
    env={"schema":1,"feed":name,"generated_epoch":now,"cadence_s":cadence,
         "ok":True,"error":None,"data":data}
    json.dump(env,open(os.path.join(root,name+".json"),"w"))
PY
  out="$(MISSION_CONTROL_HOME="$mch" MISSION_CONTROL_NOW_EPOCH="$now" bash "$DASH" status 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -E '^install' | grep -q 'UNVERIFIED: missing'; then
    ok "status: missing install stamp is an explicit red row"
  else
    no "status: missing install stamp was omitted or green (rc=$rc out=$out)"
  fi
  mkdir -p "$mch/bin"; printf '[]\n' > "$mch/bin/install-stamp.json"
  out="$(MISSION_CONTROL_HOME="$mch" MISSION_CONTROL_NOW_EPOCH="$now" bash "$DASH" status 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -E '^install' | grep -q 'UNVERIFIED: malformed' && \
     ! printf '%s\n' "$out" | grep -q 'Traceback'; then
    ok "status: malformed install stamp fails closed without traceback"
  else
    no "status: malformed install stamp did not return a structured red row (rc=$rc out=$out)"
  fi
}

c26() { # production install never silently downgrades to an uncommitted worktree
  local fr mch rc; fr="$(mktemp -d)"; mch="$(mktemp -d)"
  REPO_ROOT="$fr" MISSION_CONTROL_HOME="$mch" DASHBOARD_INSTALL_NO_LAUNCHD=1 \
    bash "$DASH" install >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ ! -e "$mch/bin/install-stamp.json" ]; then
    ok "install: missing git HEAD fails closed without a stamp"
  else
    no "install: non-git source silently installed as verified worktree"
  fi
}

c27() { # committed plist source + checked atomic launchd reload/failure behavior
  local gr h mch sbin capture loaded rc out sentinel h2 mch2 h3 mch3 h4 mch4 failbin real_chmod mode fails=0
  gr="$(mktemp -d)/repo"; mkdir -p "$gr/scripts" "$gr/dashboard/vendor" "$gr/launchd"
  local n
  for n in dashboard mission_control_common.py morning-brief morning-brief-deadman decision-alert; do
    cp "$REPO/scripts/$n" "$gr/scripts/$n"
  done
  cp "$REPO/dashboard/index.html" "$gr/dashboard/index.html"
  cp "$REPO/dashboard/vendor/cytoscape.min.js" "$gr/dashboard/vendor/cytoscape.min.js"
  cp "$REPO/launchd/com.gillettes.mission-control.plist.template" "$gr/launchd/com.gillettes.mission-control.plist.template"
  python3 - "$gr/launchd/com.gillettes.mission-control.plist.template" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s.replace("</dict>","<!-- VERSION_ONE -->\n</dict>"))
PY
  ( cd "$gr" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm v1 )
  h="$(mktemp -d)"; mch="$h/state"; sbin="$(mktemp -d)"; capture="$h/calls"; loaded="$h/loaded"
  cat > "$sbin/launchctl" <<'EOF'
#!/bin/sh
echo "$1" >> "$LAUNCH_CAPTURE"
case "$1" in
  print) [ -f "$LAUNCH_STATE" ] ;;
  bootout) [ "${FAIL_BOOTOUT:-0}" != 1 ] || exit 1; rm -f "$LAUNCH_STATE" ;;
  bootstrap) [ "${FAIL_BOOTSTRAP:-0}" != 1 ] || exit 1; : > "$LAUNCH_STATE" ;;
esac
EOF
  chmod +x "$sbin/launchctl"
  HOME="$h" PATH="$sbin:$PATH" LAUNCH_CAPTURE="$capture" LAUNCH_STATE="$loaded" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" bash "$gr/scripts/dashboard" install >/dev/null 2>&1 || fails=1
  # Commit v2, then dirty the worktree with a third marker. Install must deploy v2.
  python3 - "$gr/launchd/com.gillettes.mission-control.plist.template" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s.replace("VERSION_ONE","VERSION_TWO"))
PY
  ( cd "$gr" && git add launchd && git -c user.email=t@t -c user.name=t commit -qm v2 )
  python3 - "$gr/launchd/com.gillettes.mission-control.plist.template" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s.replace("</dict>","<!-- DIRTY_THREE -->\n</dict>"))
PY
  : > "$capture"
  HOME="$h" PATH="$sbin:$PATH" LAUNCH_CAPTURE="$capture" LAUNCH_STATE="$loaded" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" bash "$gr/scripts/dashboard" install >/dev/null 2>&1 || fails=1
  out="$h/Library/LaunchAgents/com.gillettes.mission-control.plist"
  grep -q 'VERSION_TWO' "$out" || fails=1
  ! grep -q 'DIRTY_THREE' "$out" || fails=1
  [ "$(tr '\n' ' ' < "$capture")" = "print bootout bootstrap " ] || fails=1
  # Content equality must not hide mode drift. Reinstall repairs an unchanged
  # selected plist back to the install contract's private 0600 mode.
  python3 - "$out" <<'PY'
import os, sys
os.chmod(sys.argv[1], 0o666)
PY
  : > "$capture"
  HOME="$h" PATH="$sbin:$PATH" LAUNCH_CAPTURE="$capture" LAUNCH_STATE="$loaded" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" bash "$gr/scripts/dashboard" install >/dev/null 2>&1 || fails=1
  [ "$(tr '\n' ' ' < "$capture")" = "print " ] || fails=1
  [ "$(python3 - "$out" <<'PY'
import os, stat, sys
print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])
PY
)" = "600" ] || fails=1

  # Unsafe destination is rejected before any launchd state move.
  h2="$(mktemp -d)"; mch2="$h2/state"; mkdir -p "$h2/Library/LaunchAgents"; sentinel="$h2/outside"
  printf 'DO-NOT-TOUCH\n' > "$sentinel"
  ln -s "$sentinel" "$h2/Library/LaunchAgents/com.gillettes.mission-control.plist"
  : > "$capture"
  HOME="$h2" PATH="$sbin:$PATH" LAUNCH_CAPTURE="$capture" LAUNCH_STATE="$h2/loaded" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch2" bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && [ "$(cat "$sentinel")" = "DO-NOT-TOUCH" ] && [ ! -s "$capture" ] || fails=1

  # Bootstrap failure is fatal and leaves no stamp; retry applies unchanged bytes.
  h3="$(mktemp -d)"; mch3="$h3/state"; : > "$capture"
  HOME="$h3" PATH="$sbin:$PATH" LAUNCH_CAPTURE="$capture" LAUNCH_STATE="$h3/loaded" FAIL_BOOTSTRAP=1 \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch3" bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$mch3/bin/install-stamp.json" ] || fails=1
  HOME="$h3" PATH="$sbin:$PATH" LAUNCH_CAPTURE="$capture" LAUNCH_STATE="$h3/loaded" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch3" bash "$gr/scripts/dashboard" install >/dev/null 2>&1 || fails=1

  # A plist chmod failure is fatal even after bytes land; the next unchanged-byte
  # retry must enforce 0600, bootstrap, and stamp successfully.
  h4="$(mktemp -d)"; mch4="$h4/state"; failbin="$(mktemp -d)"; real_chmod="$(command -v chmod)"
  cp "$sbin/launchctl" "$failbin/launchctl"
  cat > "$failbin/chmod" <<'EOF'
#!/bin/sh
case "$*" in
  *"/Library/LaunchAgents/"*)
    if [ ! -e "$CHMOD_FAILED_ONCE" ]; then : > "$CHMOD_FAILED_ONCE"; exit 1; fi ;;
esac
exec "$REAL_CHMOD" "$@"
EOF
  chmod +x "$failbin/launchctl" "$failbin/chmod"
  HOME="$h4" PATH="$failbin:$PATH" LAUNCH_CAPTURE="$h4/calls" LAUNCH_STATE="$h4/loaded" \
    CHMOD_FAILED_ONCE="$h4/chmod-failed" REAL_CHMOD="$real_chmod" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch4" bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$mch4/bin/install-stamp.json" ] || fails=1
  HOME="$h4" PATH="$failbin:$PATH" LAUNCH_CAPTURE="$h4/calls" LAUNCH_STATE="$h4/loaded" \
    CHMOD_FAILED_ONCE="$h4/chmod-failed" REAL_CHMOD="$real_chmod" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch4" bash "$gr/scripts/dashboard" install >/dev/null 2>&1 || fails=1
  mode="$(python3 - "$h4/Library/LaunchAgents/com.gillettes.mission-control.plist" <<'PY'
import os, stat, sys
print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])
PY
)"
  [ "$mode" = "600" ] && [ -e "$mch4/bin/install-stamp.json" ] && \
    [ -e "$h4/loaded" ] || fails=1

  # A failed bootout leaves the old bytes and loaded definition untouched.
  git -C "$gr" restore launchd/com.gillettes.mission-control.plist.template
  python3 - "$gr/launchd/com.gillettes.mission-control.plist.template" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s.replace("VERSION_TWO","VERSION_FOUR"))
PY
  ( cd "$gr" && git add launchd && git -c user.email=t@t -c user.name=t commit -qm v4 )
  : > "$capture"
  HOME="$h" PATH="$sbin:$PATH" LAUNCH_CAPTURE="$capture" LAUNCH_STATE="$loaded" FAIL_BOOTOUT=1 \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || fails=1
  grep -q 'VERSION_TWO' "$out" || fails=1
  ! grep -q 'VERSION_FOUR' "$out" || fails=1
  [ "$(tr '\n' ' ' < "$capture")" = "print bootout " ] || fails=1
  [ ! -e "$mch/bin/install-stamp.json" ] || fails=1

  if [ "$fails" = 0 ]; then
    ok "plist install: committed bytes, atomic safety, checked reload, and fatal launchd failures"
  else
    no "plist install: provenance/reload/failure contract regressed"
  fi
}

c28() { # malformed feed envelopes are red, never a status/freshness traceback
  local h out rc kind fails=0; h="$(newhome)"
  make_valid_stamp "$h"
  for kind in epoch ok cadence cadence_huge data; do
    MISSION_CONTROL_HOME="$h" bash "$DASH" collect --force >/dev/null 2>&1
    python3 - "$h/data/usage.json" "$kind" <<'PY'
import json,sys
p,kind=sys.argv[1:]; d=json.load(open(p))
if kind == "epoch": d["generated_epoch"] = float("inf")
elif kind == "ok": d["ok"] = "false"
elif kind == "cadence": d["cadence_s"] = True
elif kind == "cadence_huge": d["cadence_s"] = 1000000000
elif kind == "data": d["data"] = []
json.dump(d,open(p,"w"))
PY
    out="$(MISSION_CONTROL_HOME="$h" bash "$DASH" status 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && ! printf '%s\n' "$out" | grep -q 'Traceback' || fails=1
  done
  if [ "$fails" = 0 ]; then
    ok "status: malformed epoch/ok/cadence/data fields fail closed without traceback"
  else
    no "status: malformed feed envelope crashed or remained green"
  fi
}

c29() { # unsupported install flags are rejected before any mutation
  local gr mch sentinel before rc; gr="$(_mkrepo)"; mch="$(mktemp -d)"
  mkdir -p "$mch/bin"
  sentinel="$mch/bin/install-stamp.json"
  printf 'DO-NOT-INVALIDATE\n' > "$sentinel"
  before="$(find "$mch" -type f -print -exec shasum -a 256 {} \; | sort)"
  REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" DASHBOARD_INSTALL_NO_LAUNCHD=1 \
    bash "$gr/scripts/dashboard" install --verify >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ] && [ "$before" = "$(find "$mch" -type f -print -exec shasum -a 256 {} \; | sort)" ]; then
    ok "install: unsupported flags fail before filesystem or launchd mutation"
  else
    no "install: unsupported flag mutated state or returned the wrong status (rc=$rc)"
  fi
}

c30() { # one captured commit pins every installed byte even if HEAD moves
  local gr mch sbin marker real_git old_sha stamped rc
  gr="$(_mkrepo)"; mch="$(mktemp -d)"; sbin="$(mktemp -d)"
  marker="$sbin/moved"; real_git="$(command -v git)"; old_sha="$($real_git -C "$gr" rev-parse HEAD)"
  cat > "$sbin/git" <<'EOF'
#!/bin/sh
if [ "$1" = "-C" ] && [ "$2" = "$RACE_REPO" ] && [ "$3" = "rev-parse" ] && [ ! -e "$RACE_MARKER" ]; then
  old="$($RACE_REAL_GIT "$@")" || exit $?
  printf '%s\n' "$old"
  : > "$RACE_MARKER"
  printf '\n<!-- MOVED_HEAD_V2 -->\n' >> "$RACE_REPO/dashboard/index.html"
  "$RACE_REAL_GIT" -C "$RACE_REPO" add dashboard/index.html || exit $?
  "$RACE_REAL_GIT" -C "$RACE_REPO" -c user.email=t@t -c user.name=t commit -qm moved-head || exit $?
  exit 0
fi
exec "$RACE_REAL_GIT" "$@"
EOF
  chmod +x "$sbin/git"
  PATH="$sbin:$PATH" RACE_REPO="$gr" RACE_MARKER="$marker" RACE_REAL_GIT="$real_git" \
    REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" DASHBOARD_INSTALL_NO_LAUNCHD=1 \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  stamped="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["head_sha"])' "$mch/bin/install-stamp.json" 2>/dev/null)"
  if [ "$rc" -eq 0 ] && [ "$stamped" = "$old_sha" ] && \
     ! grep -q 'MOVED_HEAD_V2' "$mch/index.html" && [ "$($real_git -C "$gr" rev-parse HEAD)" != "$old_sha" ]; then
    ok "install: captured immutable commit survives concurrent HEAD movement"
  else
    no "install: moving HEAD produced mixed bytes or false provenance (rc=$rc stamp=$stamped)"
  fi
}

c31() { # the real macOS Bash 3.2 path executes embedded Python, not EOF
  local h count rc; h="$(newhome)"
  MISSION_CONTROL_HOME="$h" /bin/bash "$DASH" collect --force >/dev/null 2>&1; rc=$?
  count="$(find "$h/data" -type f \( -name '*.json' -o -name '*.js' \) 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rc" -eq 0 ] && [ "$count" = 12 ]; then
    ok "bash-3.2: system /bin/bash executes the embedded Python engine"
  else
    no "bash-3.2: dashboard returned rc=$rc with $count/12 feed files"
  fi
}

c32() { # a runtime chmod failure is fatal and cannot receive a green stamp
  local gr mch sbin real_chmod rc; gr="$(_mkrepo)"; mch="$(mktemp -d)"; sbin="$(mktemp -d)"
  real_chmod="$(command -v chmod)"
  cat > "$sbin/chmod" <<'EOF'
#!/bin/sh
case "$*" in
  *"/bin/dashboard"*) exit 1 ;;
esac
exec "$REAL_CHMOD" "$@"
EOF
  chmod +x "$sbin/chmod"
  PATH="$sbin:$PATH" REAL_CHMOD="$real_chmod" REPO_ROOT="$gr" \
    MISSION_CONTROL_HOME="$mch" DASHBOARD_INSTALL_NO_LAUNCHD=1 \
    bash "$gr/scripts/dashboard" install >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ ! -e "$mch/bin/install-stamp.json" ]; then
    ok "install: runtime chmod failure is fatal and leaves no green stamp"
  else
    no "install: runtime chmod failure was ignored (rc=$rc)"
  fi
}

c33() { # concurrent installers cannot interleave bytes and provenance stamps
  local ga gb mch sbin real_python ready release loops apid arc brc final_sha fails=0
  ga="$(_mkrepo)"; gb="$(mktemp -d)/repo"; mch="$(mktemp -d)"; sbin="$(mktemp -d)"
  git clone -q "$ga" "$gb" || { no "install-lock: could not build second commit fixture"; return; }
  printf '\n<!-- INSTALLER_B -->\n' >> "$gb/dashboard/index.html"
  ( cd "$gb" && git add dashboard/index.html && \
    git -c user.email=t@t -c user.name=t commit -qm installer-b ) || { no "install-lock: could not commit second fixture"; return; }
  real_python="$(command -v python3)"; ready="$sbin/ready"; release="$sbin/release"
  cat > "$sbin/python3" <<'EOF'
#!/bin/sh
: > "$STAMP_READY"
i=0
while [ ! -e "$STAMP_RELEASE" ] && [ "$i" -lt 200 ]; do
  sleep 0.05
  i=$((i+1))
done
[ -e "$STAMP_RELEASE" ] || exit 70
exec "$REAL_PYTHON3" "$@"
EOF
  chmod +x "$sbin/python3"
  PATH="$sbin:$PATH" REAL_PYTHON3="$real_python" STAMP_READY="$ready" STAMP_RELEASE="$release" \
    REPO_ROOT="$ga" MISSION_CONTROL_HOME="$mch" DASHBOARD_INSTALL_NO_LAUNCHD=1 \
    bash "$ga/scripts/dashboard" install >/dev/null 2>&1 &
  apid=$!
  loops=0
  while [ ! -e "$ready" ] && [ "$loops" -lt 200 ]; do sleep 0.05; loops=$((loops+1)); done
  [ -e "$ready" ] || fails=1
  REPO_ROOT="$gb" MISSION_CONTROL_HOME="$mch" DASHBOARD_INSTALL_NO_LAUNCHD=1 \
    bash "$gb/scripts/dashboard" install >/dev/null 2>&1; brc=$?
  : > "$release"
  wait "$apid"; arc=$?
  final_sha="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["head_sha"])' "$mch/bin/install-stamp.json" 2>/dev/null)"
  [ "$brc" -eq 75 ] || fails=1
  [ "$arc" -eq 0 ] || fails=1
  [ "$final_sha" = "$(git -C "$ga" rev-parse HEAD)" ] || fails=1
  ! grep -q 'INSTALLER_B' "$mch/index.html" || fails=1
  [ ! -e "$mch/.install.lock" ] || fails=1
  PYTHONPATH="$REPO/scripts" python3 -c \
    'import sys; from mission_control_common import verify_install_stamp; assert verify_install_stamp(sys.argv[1])["ok"]' \
    "$mch/bin" || fails=1
  if [ "$fails" = 0 ]; then
    ok "install-lock: concurrent commit cannot interleave files and stamp"
  else
    no "install-lock: concurrent installers were not isolated (A=$arc B=$brc sha=$final_sha)"
  fi
}

c34() { # forced timeout kills a non-cooperative group and its owned lock
  local gr mch cgh child rc alive=0 start end bounded
  gr="$(mktemp -d)/repo"; mch="$(mktemp -d)"; cgh="$(mktemp -d)"
  mkdir -p "$gr/scripts"
  cp "$REPO/scripts/dashboard" "$REPO/scripts/mission_control_common.py" "$gr/scripts/"
  # Keep the production code path but shrink only this fixture's chats timeout.
  sed -i.bak 's/("chats",      1800, "", "DASHBOARD_CMD_CHATS", 150)/("chats",      1800, "", "DASHBOARD_CMD_CHATS", 1)/' \
    "$gr/scripts/dashboard"
  rm -f "$gr/scripts/dashboard.bak"
  cat > "$gr/scripts/chat-graph" <<'EOF'
#!/bin/sh
mkdir -p "$CHAT_GRAPH_HOME/export" "$CHAT_GRAPH_HOME/ingest.lock"
printf '{"pid":%s,"token":"%s"}\n' "$$" "$CHAT_GRAPH_LOCK_TOKEN" \
  > "$CHAT_GRAPH_HOME/ingest.lock/owner.json"
trap 'exit 143' TERM INT
(
  exec >/dev/null 2>&1
  trap '' TERM INT
  while :; do sleep 1; done
) &
echo $! > "$CHAT_GRAPH_HOME/child.pid"
wait
EOF
  chmod +x "$gr/scripts/chat-graph"
  start="$(python3 -c 'import time; print(time.monotonic())')"
  env -u DASHBOARD_CMD_CHATS REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    CHAT_GRAPH_HOME="$cgh" bash "$gr/scripts/dashboard" collect --force chats \
    >/dev/null 2>&1; rc=$?
  end="$(python3 -c 'import time; print(time.monotonic())')"
  bounded="$(python3 - "$start" "$end" <<'PY'
import sys
print(1 if float(sys.argv[2]) - float(sys.argv[1]) < 8 else 0)
PY
)"
  child="$(cat "$cgh/child.pid" 2>/dev/null || true)"
  for _ in $(seq 1 100); do
    [ -z "$child" ] || ! kill -0 "$child" 2>/dev/null && break
    sleep 0.02
  done
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then alive=1; kill -KILL "$child" 2>/dev/null || true; fi
  if [ "$rc" -eq 0 ] && [ "$bounded" = 1 ] && [ "$alive" -eq 0 ] && \
     [ ! -d "$cgh/ingest.lock" ] && \
     grep -q 'timed out' "$mch/data/chats.error.json" 2>/dev/null; then
    ok "timeout: SIGKILL reaps a non-cooperative group and removes its owned lock"
  else
    rm -f "$cgh/ingest.lock/owner.json" 2>/dev/null || true
    rmdir "$cgh/ingest.lock" 2>/dev/null || true
    no "timeout: forced cleanup was unbounded or left residue (rc=$rc child_alive=$alive)"
  fi
}

c35() { # dashboard Git->Chats pipeline scans once and preserves failed-cycle uncertainty
  local stub count gr mch cgh roots rc success_count failure_count success_snapshot
  stub="$(mktemp -d)/scan"; count="$(mktemp -d)/count"; : > "$count"
  cat > "$stub" <<'EOF'
#!/bin/sh
printf 'x\n' >> "$SCAN_COUNT_FILE"
if [ "$SCAN_MODE" = fail ]; then
  echo 'forced Git failure' >&2
  exit 2
fi
printf '%s\n' '{"generated":"now","stale_days":21,"findings_total":1,"repos":[{"repo":"cached","dirty":true,"dirty_files":1,"ahead":0,"detached":false,"branches":[]}]}'
exit 1
EOF
  chmod +x "$stub"
  gr="$(mktemp -d)/repo"; mkdir -p "$gr/scripts"
  cp "$REPO/scripts/dashboard" "$REPO/scripts/chat-graph" \
     "$REPO/scripts/mission_control_common.py" "$gr/scripts/"
  cp "$stub" "$gr/scripts/scan-unfinished-work"
  chmod +x "$gr/scripts/dashboard" "$gr/scripts/chat-graph" \
    "$gr/scripts/scan-unfinished-work"

  run_pipeline_case() {
    mch="${2:-$(mktemp -d)}"; cgh="${3:-$(mktemp -d)}"; roots="${4:-$(mktemp -d)}"
    mkdir -p "$cgh"; date +%s > "$cgh/last-ingest"
    : > "$roots/register.md"
    env -u DASHBOARD_CMD_CHATS \
      SCAN_MODE="$1" SCAN_COUNT_FILE="$count" DASHBOARD_CMD_GIT="$stub" \
      CHAT_GRAPH_HOME="$cgh" \
      CHAT_GRAPH_CLAUDE_ROOT="$roots/claude" CHAT_GRAPH_CODEX_ROOT="$roots/codex" \
      CHAT_GRAPH_CURSOR_ROOT="$roots/cursor" CHAT_GRAPH_HERMES_ROOT="$roots/hermes" \
      CHAT_GRAPH_COPILOT_ROOT="$roots/copilot" CHAT_GRAPH_SESSION_INDEX="$roots/index.jsonl" \
      CHAT_GRAPH_CHAT_SOURCE=/usr/bin/false CHAT_GRAPH_CODING_ROOT="$roots" \
      CHAT_GRAPH_REPO_ROOTS="$roots" CHAT_GRAPH_REGISTER="$roots/register.md" \
      CHAT_GRAPH_NIGHTLY_REPORT_GLOB="$roots/reports/*.md" \
      CHAT_GRAPH_HERMES_STATE_DB="$roots/hermes.db" \
      REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
      bash "$DASH" collect --force git chats >/dev/null 2>&1
    PIPELINE_MCH="$mch"
    PIPELINE_CGH="$cgh"
    PIPELINE_ROOTS="$roots"
  }

  run_pipeline_case ok; rc=$?; success_count="$(wc -l < "$count" | tr -d ' ')"
  local success_home="$PIPELINE_MCH"
  local success_cgh="$PIPELINE_CGH"
  local success_roots="$PIPELINE_ROOTS"
  success_snapshot="$(mktemp)"
  cp "$success_home/data/chats.json" "$success_snapshot"
  : > "$count"
  # Reuse the successful cycle's home so git.json is a fresh last-good cache.
  run_pipeline_case fail "$success_home" "$success_cgh" "$success_roots"; rc=$?
  failure_count="$(wc -l < "$count" | tr -d ' ')"
  local failure_home="$PIPELINE_MCH"
  if [ "$success_count" = 1 ] && [ "$failure_count" = 1 ] && \
     python3 - "$success_snapshot" "$failure_home/data/chats.json" <<'PY'
import json,sys
good=json.load(open(sys.argv[1]))["data"]
bad=json.load(open(sys.argv[2]))["data"]
assert good["repo_annotations"][0]["repo"] == "cached", good
assert bad["repo_annotations"] == [], bad
assert any("repo annotations unavailable" in n for n in bad["notes"]), bad["notes"]
PY
  then
    ok "pipeline: Git success/failure each invokes scanner once with explicit uncertainty"
  else
    no "pipeline: duplicate scanner call remained (success=$success_count failure=$failure_count)"
  fi
}

c36() { # timeout cleanup must not remove a lock with a different nonce
  local gr mch cgh rc
  gr="$(mktemp -d)/repo"; mch="$(mktemp -d)"; cgh="$(mktemp -d)"
  mkdir -p "$gr/scripts"
  cp "$REPO/scripts/dashboard" "$REPO/scripts/mission_control_common.py" "$gr/scripts/"
  sed -i.bak 's/("chats",      1800, "", "DASHBOARD_CMD_CHATS", 150)/("chats",      1800, "", "DASHBOARD_CMD_CHATS", 1)/' \
    "$gr/scripts/dashboard"; rm -f "$gr/scripts/dashboard.bak"
  cat > "$gr/scripts/chat-graph" <<'EOF'
#!/bin/sh
mkdir -p "$CHAT_GRAPH_HOME/ingest.lock"
printf '{"pid":%s,"token":"wrong-%s"}\n' "$$" "$CHAT_GRAPH_LOCK_TOKEN" \
  > "$CHAT_GRAPH_HOME/ingest.lock/owner.json"
trap '' TERM INT
while :; do sleep 1; done
EOF
  chmod +x "$gr/scripts/chat-graph"
  env -u DASHBOARD_CMD_CHATS REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    CHAT_GRAPH_HOME="$cgh" bash "$gr/scripts/dashboard" collect --force chats \
    >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$cgh/ingest.lock/owner.json" ]; then
    ok "timeout: owner nonce mismatch leaves another lock untouched"
  else
    no "timeout: cleanup removed an unproven lock"
  fi
  rm -f "$cgh/ingest.lock/owner.json" 2>/dev/null || true
  rmdir "$cgh/ingest.lock" 2>/dev/null || true
}

c37() { # an escaped descendant holding pipes cannot wedge communicate forever
  local gr mch cgh runner child completed=0 rc=0
  gr="$(mktemp -d)/repo"; mch="$(mktemp -d)"; cgh="$(mktemp -d)"
  mkdir -p "$gr/scripts"
  cp "$REPO/scripts/dashboard" "$REPO/scripts/mission_control_common.py" "$gr/scripts/"
  sed -i.bak 's/("chats",      1800, "", "DASHBOARD_CMD_CHATS", 150)/("chats",      1800, "", "DASHBOARD_CMD_CHATS", 1)/' \
    "$gr/scripts/dashboard"; rm -f "$gr/scripts/dashboard.bak"
  cat > "$gr/scripts/chat-graph" <<'PY'
#!/usr/bin/env python3
import json, os, signal, time
home = os.environ["CHAT_GRAPH_HOME"]
lock = os.path.join(home, "ingest.lock")
os.makedirs(lock, exist_ok=True)
with open(os.path.join(lock, "owner.json"), "w") as f:
    json.dump({"pid": os.getpid(), "token": os.environ["CHAT_GRAPH_LOCK_TOKEN"]}, f)
child = os.fork()
if child == 0:
    os.setsid()
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(os.path.join(home, "escaped.pid"), "w") as f:
        f.write(str(os.getpid()))
    while True: time.sleep(1)
os._exit(0)
PY
  chmod +x "$gr/scripts/chat-graph"
  env -u DASHBOARD_CMD_CHATS REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    CHAT_GRAPH_HOME="$cgh" bash "$gr/scripts/dashboard" collect --force chats \
    >/dev/null 2>&1 &
  runner=$!
  for _ in $(seq 1 160); do
    if ! kill -0 "$runner" 2>/dev/null; then completed=1; break; fi
    sleep 0.05
  done
  child="$(cat "$cgh/escaped.pid" 2>/dev/null || true)"
  [ -z "$child" ] || kill -KILL "$child" 2>/dev/null || true
  if [ "$completed" = 0 ]; then kill -TERM "$runner" 2>/dev/null || true; fi
  wait "$runner" 2>/dev/null; rc=$?
  if [ "$completed" = 1 ] && [ "$rc" -eq 0 ] && \
     [ -f "$cgh/ingest.lock/owner.json" ] && \
     grep -q 'timed out' "$mch/data/chats.error.json" 2>/dev/null; then
    ok "timeout: escaped pipe holder is bounded and its lock remains fail-closed"
  else
    no "timeout: escaped descriptor caused an unbounded or dirty return"
  fi
  rm -f "$cgh/ingest.lock/owner.json" 2>/dev/null || true
  rmdir "$cgh/ingest.lock" 2>/dev/null || true
}

c38() { # runtime imports must not litter the source directory with bytecode
  local gr mch cgh
  gr="$(mktemp -d)/repo"; mch="$(mktemp -d)"; cgh="$(mktemp -d)"
  mkdir -p "$gr/scripts"
  cp "$REPO/scripts/dashboard" "$REPO/scripts/chat-graph" \
     "$REPO/scripts/mission_control_common.py" "$gr/scripts/"
  env -u PYTHONDONTWRITEBYTECODE MISSION_CONTROL_HOME="$mch" \
    bash "$gr/scripts/dashboard" status >/dev/null 2>&1 || true
  env -u PYTHONDONTWRITEBYTECODE CHAT_GRAPH_HOME="$cgh" CHAT_GRAPH_SCAN_CMD='/bin/echo []' \
    CHAT_GRAPH_REPO_ROOTS="$(mktemp -d)" "$gr/scripts/chat-graph" stats >/dev/null 2>&1 || true
  if ! find "$gr/scripts" \( -type d -name __pycache__ -o -type f -name '*.pyc' \) | grep -q .; then
    ok "runtime: source tree remains free of Python bytecode"
  else
    no "runtime: source imports wrote __pycache__ or .pyc files"
  fi
}

c39() { # an interrupted engine cleans the feeder and only its proven lock
  local gr mch cgh runner engine feeder completed=0 rc=0 alive=0
  gr="$(mktemp -d)/repo"; mch="$(mktemp -d)"; cgh="$(mktemp -d)"
  mkdir -p "$gr/scripts"
  cp "$REPO/scripts/dashboard" "$REPO/scripts/mission_control_common.py" "$gr/scripts/"
  cat > "$gr/scripts/chat-graph" <<'EOF'
#!/bin/sh
mkdir -p "$CHAT_GRAPH_HOME/ingest.lock"
printf '{"pid":%s,"token":"%s"}\n' "$$" "$CHAT_GRAPH_LOCK_TOKEN" \
  > "$CHAT_GRAPH_HOME/ingest.lock/owner.json"
printf '%s\n' "$PPID" > "$CHAT_GRAPH_HOME/engine.pid"
printf '%s\n' "$$" > "$CHAT_GRAPH_HOME/feeder.pid"
trap '' TERM INT
while :; do sleep 1; done
EOF
  chmod +x "$gr/scripts/chat-graph"
  env -u DASHBOARD_CMD_CHATS REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    CHAT_GRAPH_HOME="$cgh" python3 - "$gr/scripts/dashboard" <<'PY' >/dev/null 2>&1 &
import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
os.execv("/bin/bash", ["/bin/bash", sys.argv[1], "collect", "--force", "chats"])
PY
  runner=$!
  for _ in $(seq 1 100); do [ -f "$cgh/engine.pid" ] && break; sleep 0.05; done
  engine="$(cat "$cgh/engine.pid" 2>/dev/null || true)"
  feeder="$(cat "$cgh/feeder.pid" 2>/dev/null || true)"
  [ -z "$engine" ] || kill -INT "$engine" 2>/dev/null || true
  for _ in $(seq 1 160); do
    if ! kill -0 "$runner" 2>/dev/null; then completed=1; break; fi
    sleep 0.05
  done
  if [ "$completed" = 0 ]; then kill -TERM "$runner" 2>/dev/null || true; fi
  wait "$runner" 2>/dev/null; rc=$?
  if [ -n "$feeder" ] && kill -0 "$feeder" 2>/dev/null; then
    alive=1; kill -KILL "$feeder" 2>/dev/null || true
  fi
  if [ "$completed" = 1 ] && [ "$rc" -ne 0 ] && [ "$alive" = 0 ] && \
     [ ! -d "$cgh/ingest.lock" ]; then
    ok "interrupt: BaseException path reaps feeder and removes its proven lock"
  else
    rm -f "$cgh/ingest.lock/owner.json" 2>/dev/null || true
    rmdir "$cgh/ingest.lock" 2>/dev/null || true
    no "interrupt: engine interruption left residue (done=$completed rc=$rc feeder_alive=$alive lock=$([ -d "$cgh/ingest.lock" ] && echo yes || echo no))"
  fi
}

c40() { # post-reap invalid bytes cannot authorize false group cleanup
  local gr mch cgh child rc alive=0 start end bounded
  gr="$(mktemp -d)/repo"; mch="$(mktemp -d)"; cgh="$(mktemp -d)"
  mkdir -p "$gr/scripts"
  cp "$REPO/scripts/dashboard" "$REPO/scripts/mission_control_common.py" "$gr/scripts/"
  cat > "$gr/scripts/chat-graph" <<'PY'
#!/usr/bin/env python3
import json, os, signal, time
home = os.environ["CHAT_GRAPH_HOME"]
lock = os.path.join(home, "ingest.lock")
os.makedirs(lock, exist_ok=True)
with open(os.path.join(lock, "owner.json"), "w") as f:
    json.dump({"pid": os.getpid(), "token": os.environ["CHAT_GRAPH_LOCK_TOKEN"]}, f)
child = os.fork()
if child == 0:
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1); os.dup2(devnull, 2); os.close(devnull)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(os.path.join(home, "same-group.pid"), "w") as f:
        f.write(str(os.getpid()))
    while True: time.sleep(1)
for _ in range(100):
    if os.path.exists(os.path.join(home, "same-group.pid")): break
    time.sleep(0.01)
os.write(1, b"\xff")
os._exit(0)
PY
  chmod +x "$gr/scripts/chat-graph"
  start="$(python3 -c 'import time; print(time.monotonic())')"
  env -u DASHBOARD_CMD_CHATS REPO_ROOT="$gr" MISSION_CONTROL_HOME="$mch" \
    CHAT_GRAPH_HOME="$cgh" bash "$gr/scripts/dashboard" collect --force chats \
    >/dev/null 2>&1; rc=$?
  end="$(python3 -c 'import time; print(time.monotonic())')"
  bounded="$(python3 - "$start" "$end" <<'PY'
import sys
print(1 if float(sys.argv[2]) - float(sys.argv[1]) < 8 else 0)
PY
)"
  child="$(cat "$cgh/same-group.pid" 2>/dev/null || true)"
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then alive=1; fi
  if [ "$rc" -eq 0 ] && [ "$bounded" = 1 ] && [ "$alive" = 1 ] && \
     [ -f "$cgh/ingest.lock/owner.json" ] && [ -f "$mch/data/chats.error.json" ]; then
    ok "decode: post-reap invalid bytes leave the owner lock fail-closed"
  else
    no "decode: post-reap exception falsely cleaned group/lock (rc=$rc alive=$alive)"
  fi
  [ -z "$child" ] || kill -KILL "$child" 2>/dev/null || true
  rm -f "$cgh/ingest.lock/owner.json" 2>/dev/null || true
  rmdir "$cgh/ingest.lock" 2>/dev/null || true
}


c41() { # decide alert-backfill is an explicit capped operator path (stub sender)
  local mch out id sender capture
  mch="$(mktemp -d)"; sender="$mch/sender.py"; capture="$mch/send.json"
  cat > "$sender" <<'PY'
#!/usr/bin/env python3
import fcntl,json,os,sys
p=os.environ["DECISION_SEND_CAPTURE"]
with open(p,"a+") as handle:
    fcntl.flock(handle,fcntl.LOCK_EX)
    handle.seek(0)
    try: rows=json.load(handle)
    except Exception: rows=[]
    rows.append(sys.argv[1:])
    handle.seek(0); handle.truncate(); json.dump(rows,handle); handle.flush()
sys.exit(0)
PY
  chmod +x "$sender"
  printf '[]\n' > "$capture"
  created="$(MISSION_CONTROL_HOME="$mch" DECISION_ALERT_NOW_EPOCH=1784365200 \
    "$REPO/scripts/decision-alert" ingest \
    --source-kind git --source-key dash-bf \
    --text 'Choose dashboard backfill decision' --evidence 'dash-bf' \
    --trust structured --provenance git-facts --json)" || { no "alert-backfill fixture ingest failed"; return; }
  id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$created")"
  if env -u DASHBOARD_CMD_DECISIONS REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" \
       bash "$DASH" decide alert-backfill --max 26 >/dev/null 2>&1; then
    no "dashboard alert-backfill accepted max above ceiling"; return
  fi
  out="$(DECISION_ALERT_SEND_BIN="$sender" DECISION_ALERT_CHAT_ID=12345 \
    DECISION_SEND_CAPTURE="$capture" \
    env -u DASHBOARD_CMD_DECISIONS REPO_ROOT="$REPO" MISSION_CONTROL_HOME="$mch" \
    bash "$DASH" decide alert-backfill --max 2)" || { no "dashboard alert-backfill send failed"; return; }
  if python3 - "$out" "$id" "$capture" <<'PY'
import json,sys
x=json.loads(sys.argv[1])
assert x["mode"] == "backfill" and x["ok"] is True
assert x["sent_count"] == 1 and sys.argv[2] in x["sent"]
assert x.get("max") == 2
calls=json.load(open(sys.argv[3]))
assert len(calls) == 1
PY
  then
    ok "dashboard decide alert-backfill caps, sends via stub, and stamps path"
  else
    no "dashboard decide alert-backfill missed cap/send/receipt contract"
  fi
}

c1; c2; c3; c4; c5; c6; c7; c8; c8a; c8b; c9; c10; c11; c12; c13; c14; c14a; c15; c16; c17; c18; c19; c20; c21; c22; c23; c24; c25; c26; c27; c28; c29; c30; c31; c32; c33; c34; c35; c36; c37; c38; c39; c40; c41
shell_contract
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
