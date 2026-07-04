#!/usr/bin/env bash
# automation-status.test.sh — acceptance suite for scripts/automation-status
# (ER-087 Part B automation-health collector).
# bash-3.2 compatible; python3 stdlib only; mktemp fixtures only; no network;
# never touches real $HOME. One PASS:/FAIL: line per case; exit 0 iff all pass.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SC="$HERE/automation-status"
FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- fixtures -------------------------------------------------------------
FRESH="$WORK/fresh-evidence.log"; : > "$FRESH"            # mtime = now
STALE="$WORK/stale-evidence.log"; : > "$STALE"
touch -t 200001010000 "$STALE"                            # ancient → stale
BROKEN_EV="$WORK/broken-evidence.log"; : > "$BROKEN_EV"
touch -t 200001010000 "$BROKEN_EV"
ERRLOG="$WORK/broken.err"
printf 'first line\nlast failure: exit 1 boom\n' > "$ERRLOG"
OFFLINE="/Volumes/NOPE_T7_er087p3a/evidence.log"          # mount absent

REG="$WORK/jobs.json"
cat > "$REG" <<JSON
{ "jobs": [
  { "label": "Green Job", "name": "com.gillettes.greenjob", "kind": "interval",
    "schedule": "every 5m", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$FRESH" } ],
    "err_log": "$ERRLOG" },
  { "label": "Yellow Job", "name": "com.gillettes.yellowjob", "kind": "interval",
    "schedule": "every 5m", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$STALE" } ] },
  { "label": "Broken Job", "name": "com.gillettes.brokenjob", "kind": "interval",
    "schedule": "hourly", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$BROKEN_EV" } ],
    "err_log": "$ERRLOG" },
  { "label": "Offline Job", "name": "com.gillettes.offlinejob", "kind": "interval",
    "schedule": "daily", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$OFFLINE" } ] },
  { "label": "Retired Job", "name": "com.gillettes.retiredjob", "kind": "interval",
    "schedule": "never", "expected_freshness_s": 3600, "retired": true,
    "evidence": [ { "role": "run", "path": "$STALE" } ] }
] }
JSON

# good launchctl stub: 3-col PID/Status/Label; greenjob+yellowjob loaded,
# plus an extra com.gillette* label absent from the registry (drift).
STUB="$WORK/launchctl-good.sh"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
printf 'PID\tStatus\tLabel\n'
printf '100\t0\tcom.gillettes.greenjob\n'
printf '200\t0\tcom.gillettes.yellowjob\n'
printf '50\t0\tcom.gillette.repo-state-watch.extra\n'
SH
chmod +x "$STUB"

# garbage launchctl stub
GARBAGE="$WORK/launchctl-garbage.sh"
cat > "$GARBAGE" <<'SH'
#!/usr/bin/env bash
echo "this is not launchctl output at all"
echo "$$ random garbage"
SH
chmod +x "$GARBAGE"

# read one job's field from the saved json: getfield <json> <name> <key>
getfield() { python3 - "$1" "$2" "$3" <<'PY'
import json, sys
env = json.load(open(sys.argv[1]))
for j in env["data"]["jobs"]:
    if j["name"] == sys.argv[2]:
        print(j.get(sys.argv[3])); break
else:
    print("__MISSING__")
PY
}
top() { python3 - "$1" "$2" <<'PY'
import json, sys
env = json.load(open(sys.argv[1]))
d = env["data"]
key = sys.argv[2]
print(d[key] if key in d else env[key])
PY
}

# --- run: good stub -------------------------------------------------------
OUT="$WORK/out.json"
AUTOMATION_STATUS_LAUNCHCTL="$STUB" \
  python3 "$SC" --json --registry "$REG" > "$OUT" 2>"$WORK/err.txt"
RC=$?
[ "$RC" -eq 0 ] && pass "exit 0 on good run" || fail "exit 0 on good run (rc=$RC)"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$OUT" \
  && pass "--json parses" || fail "--json parses"

# envelope fields present
MISS=""
for k in schema feed generated_at generated_epoch cadence_s ok data; do
  python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in e else 1)' "$OUT" "$k" || MISS="$MISS $k"
done
[ "$(top "$OUT" feed)" = "automation" ] || MISS="$MISS feed-value"
[ "$(top "$OUT" cadence_s)" = "300" ] || MISS="$MISS cadence-value"
for k in checked_at t7_mounted jobs unregistered; do
  python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in e["data"] else 1)' "$OUT" "$k" || MISS="$MISS data.$k"
done
[ -z "$MISS" ] && pass "envelope fields present" || fail "envelope fields present (missing:$MISS)"

[ "$(top "$OUT" ok)" = "True" ] && pass "ok:true on readable registry" || fail "ok:true on readable registry"

# green
[ "$(getfield "$OUT" com.gillettes.greenjob state)" = "green" ] \
  && pass "green: fresh evidence + loaded" || fail "green: fresh evidence + loaded"

# broken → red, err_log last line captured
[ "$(getfield "$OUT" com.gillettes.brokenjob state)" = "red" ] \
  && pass "broken → red (not loaded, stale)" || fail "broken → red"
case "$(getfield "$OUT" com.gillettes.brokenjob err_log_tail)" in
  *"exit 1 boom"*) pass "broken: err_log last line captured" ;;
  *) fail "broken: err_log last line captured" ;;
esac

# yellow
[ "$(getfield "$OUT" com.gillettes.yellowjob state)" = "yellow" ] \
  && pass "yellow: loaded but stale evidence" || fail "yellow: loaded but stale evidence"

# offline-media
[ "$(getfield "$OUT" com.gillettes.offlinejob state)" = "offline-media" ] \
  && pass "offline-media: T7 root absent" || fail "offline-media: T7 root absent"

# unregistered
case "$(top "$OUT" unregistered)" in
  *"com.gillette.repo-state-watch.extra"*) pass "unregistered live label surfaced" ;;
  *) fail "unregistered live label surfaced" ;;
esac

# retired + excluded from exceptions
[ "$(getfield "$OUT" com.gillettes.retiredjob state)" = "retired" ] \
  && pass "retired:true → retired state" || fail "retired:true → retired state"
# exceptions = red(1)+yellow(1) = 2; retired NOT counted (would be 3)
[ "$(top "$OUT" exceptions)" = "2" ] \
  && pass "retired excluded from exception count" \
  || fail "retired excluded from exception count (got $(top "$OUT" exceptions))"

# --- run: garbage stub ----------------------------------------------------
GOUT="$WORK/garbage.json"
AUTOMATION_STATUS_LAUNCHCTL="$GARBAGE" \
  python3 "$SC" --json --registry "$REG" > "$GOUT" 2>/dev/null
GRC=$?
[ "$GRC" -eq 0 ] && pass "garbage launchctl: exit still 0" || fail "garbage: exit 0 (rc=$GRC)"
[ "$(top "$GOUT" ok)" = "True" ] && pass "garbage: ok:true" || fail "garbage: ok:true"
# every non-retired job degraded (retired stays retired)
ALLDEG=1
for n in com.gillettes.greenjob com.gillettes.yellowjob com.gillettes.brokenjob com.gillettes.offlinejob; do
  [ "$(getfield "$GOUT" "$n" state)" = "degraded" ] || ALLDEG=0
done
[ "$ALLDEG" -eq 1 ] && pass "garbage: all jobs degraded (never all-red)" || fail "garbage: all jobs degraded"
case "$(top "$GOUT" launchctl_note)" in
  *degraded*) pass "garbage: note present" ;;
  *) fail "garbage: note present" ;;
esac

# --- run: missing registry → ok:false, still exit 0 -----------------------
MOUT="$WORK/missing.json"
AUTOMATION_STATUS_LAUNCHCTL="$STUB" \
  python3 "$SC" --json --registry "$WORK/does-not-exist.json" > "$MOUT" 2>/dev/null
MRC=$?
[ "$MRC" -eq 0 ] && pass "missing registry: exit 0" || fail "missing registry: exit 0 (rc=$MRC)"
[ "$(top "$MOUT" ok)" = "False" ] && pass "missing registry: ok:false" || fail "missing registry: ok:false"

# --- human table default (no --json) --------------------------------------
AUTOMATION_STATUS_LAUNCHCTL="$STUB" \
  python3 "$SC" --registry "$REG" > "$WORK/table.txt" 2>/dev/null
case "$(cat "$WORK/table.txt")" in
  *"STATE"*"green"*"Green Job"*) pass "human table renders" ;;
  *) fail "human table renders" ;;
esac

# --- pseudo jobs: freshness-only, NEVER red-for-unloaded ------------------
# A pseudo job (e.g. the nightly chat-graph refresh) is NOT a launchd label, so
# the good STUB never lists it. Without the pseudo branch it would be marked
# red-for-unloaded forever; it must classify from evidence freshness only.
MISSING_EV="$WORK/pseudo-missing.log"   # deliberately never created
PREG="$WORK/pseudo.json"
cat > "$PREG" <<JSON
{ "jobs": [
  { "label": "Pseudo Fresh", "name": "pseudo-fresh", "pseudo": true, "kind": "interval",
    "schedule": "nightly", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$FRESH" } ] },
  { "label": "Pseudo Stale", "name": "pseudo-stale", "pseudo": true, "kind": "interval",
    "schedule": "nightly", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$STALE" } ] },
  { "label": "Pseudo Missing", "name": "pseudo-missing", "pseudo": true, "kind": "interval",
    "schedule": "nightly", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$MISSING_EV" } ] }
] }
JSON
POUT="$WORK/pseudo.json.out"
AUTOMATION_STATUS_LAUNCHCTL="$STUB" \
  python3 "$SC" --json --registry "$PREG" > "$POUT" 2>/dev/null
[ "$(getfield "$POUT" pseudo-fresh state)" = "green" ] \
  && pass "pseudo + fresh evidence -> green (not red-for-unloaded)" \
  || fail "pseudo fresh -> green (got $(getfield "$POUT" pseudo-fresh state))"
[ "$(getfield "$POUT" pseudo-stale state)" = "yellow" ] \
  && pass "pseudo + stale evidence -> yellow" \
  || fail "pseudo stale -> yellow (got $(getfield "$POUT" pseudo-stale state))"
[ "$(getfield "$POUT" pseudo-missing state)" = "yellow" ] \
  && pass "pseudo + missing evidence -> yellow" \
  || fail "pseudo missing -> yellow (got $(getfield "$POUT" pseudo-missing state))"
PRED=0
for n in pseudo-fresh pseudo-stale pseudo-missing; do
  [ "$(getfield "$POUT" "$n" state)" = "red" ] && PRED=1
done
[ "$PRED" -eq 0 ] && pass "no pseudo job is ever RED (unloaded launchd label ignored)" \
  || fail "a pseudo job was marked RED"

# --- summary --------------------------------------------------------------
echo "-----"
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$FAILS FAIL(S)"; exit 1; fi
