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
import json, os, sys
d = sys.argv[1]
def w(name, obj):
    json.dump(obj, open(os.path.join(d, name), "w"))
# raw payloads -> dashboard wraps them
w("usage.json", {"providers": [{"name": "claude", "pct": 62}]})
w("git.json", {"repos": [{"name": "gi", "dirty": True}]})
w("git2.json", {"repos": [{"marker": "NEW"}]})
# chats: already a full envelope (passthrough) + hostile title
w("chats.json", {"schema": 1, "feed": "chats",
                 "generated_at": "2026-07-02T12:00:00Z", "generated_epoch": 1751467200,
                 "cadence_s": 1800, "ok": True, "error": None,
                 "data": {"nodes": [{"id": "x:1",
                          "title": "Tre'vor \U0001F600 </script> chat"}],
                          "edges": [], "topics": [], "counts": {}}})
# automation envelopes; counts carries a "red" COUNT key on purpose (false-match trap)
def auto(jobs, red):
    return {"schema": 1, "feed": "automation", "generated_at": "2026-07-02T12:00:00Z",
            "generated_epoch": 1751467200, "cadence_s": 300, "ok": True, "error": None,
            "data": {"jobs": jobs, "counts": {"green": len(jobs) - red, "red": red}}}
w("auto_green.json", auto([{"label": "A", "state": "green"},
                           {"label": "B", "state": "green"}], 0))
w("auto_red.json", auto([{"label": "A", "state": "green"},
                         {"label": "B", "state": "red"}], 1))
PYEOF

# stub `open` on PATH: touches a sentinel if ever invoked
printf '#!/bin/sh\ntouch "%s/open-called"\n' "$STUB" > "$STUB/bin/open"
chmod +x "$STUB/bin/open"

export DASHBOARD_CMD_USAGE="cat '$STUB/usage.json'"
export DASHBOARD_CMD_GIT="cat '$STUB/git.json'"
export DASHBOARD_CMD_CHATS="cat '$STUB/chats.json'"
export DASHBOARD_CMD_AUTOMATION="cat '$STUB/auto_green.json'"

newhome() { mktemp -d "$ROOT/home.XXXXXX"; }

# --- case 1: collect --force writes 8 files, every .json envelope-valid --------
c1() {
  local H; H="$(newhome)"
  MISSION_CONTROL_HOME="$H" bash "$DASH" collect --force >/dev/null 2>&1
  local f miss=0
  for f in usage git chats automation; do
    [ -f "$H/data/$f.json" ] || miss=1
    [ -f "$H/data/$f.js" ] || miss=1
  done
  if [ "$miss" != 0 ]; then no "collect --force writes 8 files (some missing)"; return; fi
  if python3 /dev/stdin "$H/data" <<'PYEOF'
import json, os, sys
d = sys.argv[1]
keys = {"schema", "feed", "generated_at", "generated_epoch", "cadence_s", "ok", "error", "data"}
for f in ("usage", "git", "chats", "automation"):
    e = json.load(open(os.path.join(d, f + ".json")))
    assert keys <= set(e), (f, keys - set(e))
    assert e["schema"] == 1 and e["feed"] == f, f
    assert isinstance(e["generated_epoch"], int), f
PYEOF
  then ok "collect --force writes 8 files, all .json envelope-valid"
  else no "collect --force .json not envelope-valid"; fi
}

# --- case 2: .js transport byte-equals .json canonical (incl hostile title) ----
c2() {
  local H; H="$(newhome)"
  MISSION_CONTROL_HOME="$H" bash "$DASH" collect --force >/dev/null 2>&1
  if python3 /dev/stdin "$H/data" <<'PYEOF'
import json, os, sys
d = sys.argv[1]
for f in ("usage", "git", "chats", "automation"):
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
  local mch; mch="$(mktemp -d)"
  if DASHBOARD_CMD_GIT='echo "{\"findings\": 3}"; exit 1' \
     DASHBOARD_CMD_USAGE='echo {}' DASHBOARD_CMD_CHATS='echo {}' DASHBOARD_CMD_AUTOMATION='echo {}' \
     MISSION_CONTROL_HOME="$mch" bash "$DASH" collect --force >/dev/null 2>&1 \
     && [ -f "$mch/data/git.json" ] && [ ! -f "$mch/data/git.error.json" ]; then
    ok "git feeder exit 1 (findings) accepted as valid"
  else
    no "git feeder exit 1 wrongly treated as failure"
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
         -u DASHBOARD_CMD_AUTOMATION -u REPO_ROOT \
         MISSION_CONTROL_HOME="$mch" CHAT_GRAPH_HOME="$cgh" \
         bash "$mch/bin/dashboard" collect --force >/dev/null 2>&1 \
     && [ -f "$mch/data/usage.json" ] && [ -f "$mch/data/git.json" ] \
     && [ -f "$mch/data/chats.json" ] && [ -f "$mch/data/automation.json" ]; then
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

c12() { # FIX 3: chats (slow) must be LAST in FEEDS so it never starves the fast feeds
  local order; order="$(grep -oE '\("(usage|git|chats|automation)"' "$DASH" | sed -E 's/[("]//g' | tr '\n' ' ')"
  case "$order" in
    *chats\ ) ok "feed order: chats collected last ($order)" ;;
    *) no "feed order: chats not last — slow scan starves other tabs ($order)" ;;
  esac
}
c13() { # FIX 6: the data/ dir must be 0700, not world-readable
  local mch; mch="$(mktemp -d)/mc"
  DASHBOARD_CMD_USAGE='echo {}' DASHBOARD_CMD_GIT='echo {}' DASHBOARD_CMD_CHATS='echo {}' DASHBOARD_CMD_AUTOMATION='echo {}' \
    MISSION_CONTROL_HOME="$mch" bash "$DASH" collect --force >/dev/null 2>&1
  local p; p="$(stat -f '%Lp' "$mch/data" 2>/dev/null || stat -c '%a' "$mch/data" 2>/dev/null)"
  [ "$p" = "700" ] && ok "data dir perms 700 (got $p)" || no "data dir world-readable (got $p, want 700)"
}

c1; c2; c3; c4; c5; c6; c7; c8; c9; c10; c11; c12; c13
shell_contract
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
