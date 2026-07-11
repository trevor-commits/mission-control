#!/usr/bin/env bash
# scripts/dashboard.test.sh — feeders stubbed via env, mktemp state dirs only.
# Never touches real $HOME. One PASS:/FAIL: line per case; exit 0 iff all pass.
# Optional flag: --require-shell makes the shell-contract checks mandatory.
set -uo pipefail

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
python3 /dev/stdin "$STUB" <<'PYEOF'
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
                          "edges": [], "topics": [], "counts": {}}})
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
  if python3 /dev/stdin "$H/data" <<'PYEOF'
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
  if python3 /dev/stdin "$H/data" <<'PYEOF'
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
  if python3 /dev/stdin "$H/data" <<'PYEOF'
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
  if python3 /dev/stdin "$H/data" "$usage_before" <<'PYEOF'
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
  local out dir
  out="$(PATH="$STUB/bin:$PATH" DASHBOARD_NO_OPEN=1 bash "$DASH" demo 2>&1)"
  dir="$(printf '%s\n' "$out" | sed -n 's/^demo state: //p')"
  if [ -n "$dir" ] && [ -f "$dir/data/chats.json" ]; then
    if [ ! -f "$STUB/open-called" ]; then
      ok "demo builds fixtures into temp dir, no open under DASHBOARD_NO_OPEN=1"
    else no "demo invoked open despite DASHBOARD_NO_OPEN=1"; fi
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
  if python3 /dev/stdin "$REPO/dashboard/fixtures" <<'PYEOF'
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
  if printf '%s\n' "$out" | grep -q "stale full ingest"; then
    ok "status: fresh chats feed still surfaces stale full graph ingest"
  else
    no "status: stale full graph ingest hidden behind fresh chats feed"
  fi
}

c9() { # install copies a RUNNABLE runtime with REPO_ROOT baked in (headless plist path)
  local fr; fr="$(mktemp -d)/fixrepo"
  mkdir -p "$fr/scripts" "$fr/dashboard"
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
  # stub launchctl on PATH so any bootstrap no-ops (fixture has no plist template)
  local sbin; sbin="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "$sbin/launchctl"; chmod +x "$sbin/launchctl"
  local mch; mch="$(mktemp -d)"
  PATH="$sbin:$PATH" REPO_ROOT="$fr" MISSION_CONTROL_HOME="$mch" \
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
  # Anchor to local noon today so same-local-day + valid_until are TZ/date-proof.
  NOW="$(python3 -c 'import time;lt=time.localtime();print(int(time.mktime((lt.tm_year,lt.tm_mon,lt.tm_mday,12,0,0,0,0,-1))))')"
  GEN=$((NOW - 7200))   # 10:00 local: same day, but > 6x brief cadence (1800s) old
  RAWCHATS="$H/chats_raw.json"
  printf '{"nodes":[],"edges":[],"topics":[],"counts":{}}\n' > "$RAWCHATS"
  mkdir -p "$H/morning-brief/delivery"
  python3 /dev/stdin "$H/morning-brief" "$GEN" <<'PYEOF'
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
  if ! python3 /dev/stdin "$H" "$GEN" <<'PYEOF'
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

c1; c2; c3; c4; c5; c6; c7; c8; c8a; c8b; c9; c10; c11; c12; c13; c14; c14a; c15; c16; c17; c18; c19; c20; c21; c22; c23
shell_contract
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
