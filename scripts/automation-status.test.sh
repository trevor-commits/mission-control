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
export MISSION_CONTROL_HOME="$WORK/default-mission-control-home"
mkdir -p "$MISSION_CONTROL_HOME"

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

# A safety-gated job that is deliberately not installed is not a failure and
# cannot expose a kickstart action until activation is explicitly authorized.
AREG="$WORK/activation-required.json"
cat > "$AREG" <<JSON
{ "jobs": [
  { "label": "Awaiting Job", "name": "com.gillettes.awaiting-job",
    "activation_required": true, "kind": "calendar", "schedule": "07:00 daily",
    "expected_freshness_s": 93600, "evidence": [] }
] }
JSON
AOUT="$WORK/activation-required.out"
AUTOMATION_STATUS_LAUNCHCTL="$STUB" \
  python3 "$SC" --json --registry "$AREG" > "$AOUT" 2>/dev/null
[ "$(getfield "$AOUT" com.gillettes.awaiting-job state)" = "awaiting-activation" ] \
  && [ "$(top "$AOUT" exceptions)" = "0" ] \
  && pass "activation-gated unloaded job is honest, non-failing state" \
  || fail "activation-gated unloaded job was treated as failure"

# A fresh, exit-zero job is still degraded when its content-free run marker
# says the fail-open operation did not complete cleanly.
SEM_MARKER="$WORK/semantic-run.json"
printf '%s\n' '{"status":"completed_with_failures"}' > "$SEM_MARKER"
SEM_REG="$WORK/semantic-jobs.json"
cat > "$SEM_REG" <<JSON
{"jobs":[{"label":"Semantic Job","name":"com.gillettes.semantic-job",
"kind":"calendar","schedule":"06:40 daily","expected_freshness_s":3600,
"evidence":[{"path":"$SEM_MARKER","role":"run","run_key":true,"semantic_status":true}]}]}
JSON
SEM_STUB="$WORK/semantic-launchctl.sh"
cat > "$SEM_STUB" <<'SH'
#!/usr/bin/env bash
printf 'PID\tStatus\tLabel\n100\t0\tcom.gillettes.semantic-job\n'
SH
chmod +x "$SEM_STUB"
SEM_OUT="$WORK/semantic.out"
AUTOMATION_STATUS_LAUNCHCTL="$SEM_STUB" python3 "$SC" --json \
  --registry "$SEM_REG" > "$SEM_OUT" 2>/dev/null
if [ "$(getfield "$SEM_OUT" com.gillettes.semantic-job state)" = yellow ] \
   && [ "$(getfield "$SEM_OUT" com.gillettes.semantic-job semantic_status)" = completed_with_failures ] \
   && python3 - "$SEM_OUT" <<'PY'
import json,sys
job=json.load(open(sys.argv[1]))["data"]["jobs"][0]
assert job["recent_runs"][-1]["result"] == "failure"
assert job["failure_streak"] == 1
PY
then
  pass "semantic fail-open marker prevents a false green job"
else
  fail "semantic fail-open marker classification"
fi
printf '%s\n' '{"status":"completed"}' > "$SEM_MARKER"
AUTOMATION_STATUS_LAUNCHCTL="$SEM_STUB" python3 "$SC" --json \
  --registry "$SEM_REG" > "$SEM_OUT" 2>/dev/null
if [ "$(getfield "$SEM_OUT" com.gillettes.semantic-job state)" = green ] \
  && python3 - "$SEM_OUT" <<'PY'
import json,sys
job=json.load(open(sys.argv[1]))["data"]["jobs"][0]
assert job["recent_runs"][-1]["result"] == "success"
assert job["failure_streak"] == 0
PY
then pass "semantic completed marker permits green and resets history"
else fail "semantic completed marker classification"; fi

# The production registry must consume the fail-closed repository-bundle
# receipt semantically. A fresh file or exit-zero launchd row alone must never
# turn a partial backup into a green automation card.
if python3 - "$HERE/../dashboard/jobs.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
j = next(x for x in d["jobs"] if x["name"] == "com.gillettes.repo-nightly-bundle")
assert j["kind"] == "calendar" and j["schedule"] == "02:30 daily", j
assert j["expected_freshness_s"] == 93600, j
assert j["err_log"].endswith("repo-nightly-bundle/launchd.err.log"), j
assert j["evidence"] == [{
    "path": "/Users/gillettes/.local/state/repo-nightly-bundle/last-status.json",
    "role": "run", "run_key": True, "semantic_status": True,
}], j
PY
then pass "registry: nightly bundles use the semantic fail-closed receipt"
else fail "registry: nightly bundle health contract is missing or diluted"; fi

# --- distinct-run history, schedule math, globs, and atomic persistence ----
RUNS="$WORK/distinct-runs"; mkdir -p "$RUNS"
RUN_MARKER="$RUNS/run-marker.json"
GLOB_OLD="$RUNS/run-older.json"
GLOB_NEW="$RUNS/run-newer.json"
RUN_ERR="$RUNS/run.err"
STATUS_FILE="$RUNS/status"
KEEPALIVE_MODE_FILE="$RUNS/keepalive-mode"
: > "$RUN_MARKER"; : > "$GLOB_OLD"; : > "$GLOB_NEW"; : > "$RUN_ERR"
printf '1\n' > "$STATUS_FILE"
printf 'down\n' > "$KEEPALIVE_MODE_FILE"

# Fixed UTC clock: 2026-07-09 12:00:00Z. Newest glob evidence is 100 seconds old.
FAKE_NOW=1783598400
python3 - "$RUN_MARKER" "$GLOB_OLD" "$GLOB_NEW" "$RUN_ERR" "$FAKE_NOW" <<'PY'
import os, sys
marker, old, new, err, now = sys.argv[1:5] + [int(sys.argv[5])]
for path, ts in ((marker, now - 100), (old, now - 900), (new, now - 100), (err, now - 50)):
    os.utime(path, ns=(ts * 1000000000, ts * 1000000000))
PY

HREG="$RUNS/jobs.json"
cat > "$HREG" <<JSON
{ "jobs": [
  { "label": "Distinct Job", "name": "com.gillettes.distinct", "kind": "calendar",
    "schedule": "23:30 daily", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$RUNS/run-*.json", "run_key": true } ],
    "err_log": "$RUN_ERR" },
  { "label": "Interval Job", "name": "com.gillettes.interval", "kind": "interval",
    "schedule": "every 300s", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "$RUN_MARKER", "run_key": true } ] },
  { "label": "Unknown History", "name": "com.gillettes.unknown", "kind": "calendar",
    "schedule": "07:00 daily", "expected_freshness_s": 3600,
    "evidence": [ { "role": "display", "path": "$RUN_MARKER" } ] },
  { "label": "Offline Failure", "name": "com.gillettes.offline-failure", "kind": "calendar",
    "schedule": "07:00 daily", "expected_freshness_s": 3600,
    "evidence": [ { "role": "run", "path": "/Volumes/NOPE_T7_history/run", "run_key": true } ],
    "err_log": "$RUN_ERR" },
  { "label": "Keepalive Episode", "name": "com.gillettes.keepalive-episode", "kind": "keepalive",
    "schedule": "keepalive", "expected_freshness_s": 3600,
    "evidence": [ { "role": "progress", "path": "$RUN_MARKER" } ] }
] }
JSON

HSTUB="$RUNS/launchctl.sh"
cat > "$HSTUB" <<'SH'
#!/usr/bin/env bash
printf 'PID\tStatus\tLabel\n'
printf -- '-\t%s\tcom.gillettes.distinct\n' "$(cat "$STATUS_FILE")"
printf -- '-\t0\tcom.gillettes.interval\n'
printf -- '-\t0\tcom.gillettes.unknown\n'
printf -- '-\t1\tcom.gillettes.offline-failure\n'
if [ "$(cat "$KEEPALIVE_MODE_FILE")" = up ]; then
  printf '4321\t0\tcom.gillettes.keepalive-episode\n'
fi
SH
chmod +x "$HSTUB"

HIST_HOME="$RUNS/home"; mkdir -p "$HIST_HOME"
run_history_collect() {
  TZ=UTC AUTOMATION_STATUS_NOW_EPOCH="$FAKE_NOW" MISSION_CONTROL_HOME="$HIST_HOME" \
    STATUS_FILE="$STATUS_FILE" KEEPALIVE_MODE_FILE="$KEEPALIVE_MODE_FILE" \
    AUTOMATION_STATUS_LAUNCHCTL="$HSTUB" python3 "$SC" --json --registry "$HREG"
}

HOUT="$RUNS/history.json.out"
run_history_collect > "$HOUT"

python3 - "$HOUT" "$FAKE_NOW" <<'PY'
import json, sys
env = json.load(open(sys.argv[1])); now = int(sys.argv[2])
jobs = {j["name"]: j for j in env["data"]["jobs"]}
daily = jobs["com.gillettes.distinct"]
interval = jobs["com.gillettes.interval"]
unknown = jobs["com.gillettes.unknown"]
offline = jobs["com.gillettes.offline-failure"]
assert daily["evidence_age_s"] == 100.0, daily
assert daily["next_run_epoch"] == 1783639800, daily
assert interval["next_run_epoch"] == now + 200, interval
assert daily["failure_streak"] == 1 and len(daily["recent_runs"]) == 1, daily
assert unknown["history_confidence"] == "unknown" and not unknown["recent_runs"], unknown
assert offline["state"] == "offline-media" and not offline["recent_runs"], offline
assert daily["run_cmd"].endswith("/com.gillettes.distinct"), daily
PY
if [ "$?" -eq 0 ]; then pass "history: newest glob, fake-time schedules, trusted/unknown fields";
else fail "history: newest glob, fake-time schedules, trusted/unknown fields"; fi

# Twelve repeated observations of the same failed run must remain one event.
i=1
while [ "$i" -le 11 ]; do run_history_collect >/dev/null; i=$((i + 1)); done
run_history_collect > "$HOUT"
python3 - "$HOUT" <<'PY'
import json, sys
j = next(x for x in json.load(open(sys.argv[1]))["data"]["jobs"] if x["name"] == "com.gillettes.distinct")
assert len(j["recent_runs"]) == 1, j
assert j["failure_streak"] == 1, j
PY
if [ "$?" -eq 0 ]; then pass "history: repeated polls do not inflate distinct failure streak";
else fail "history: repeated polls inflated failure streak"; fi

# A new error mtime is a distinct failed run; a later trusted success resets it.
FAKE_NOW=$((FAKE_NOW + 60))
python3 - "$RUN_ERR" "$FAKE_NOW" <<'PY'
import os, sys
ts = int(sys.argv[2]); os.utime(sys.argv[1], ns=(ts * 1000000000, ts * 1000000000))
PY
run_history_collect > "$HOUT"
printf '0\n' > "$STATUS_FILE"
FAKE_NOW=$((FAKE_NOW + 60))
python3 - "$GLOB_NEW" "$FAKE_NOW" <<'PY'
import os, sys
ts = int(sys.argv[2]); os.utime(sys.argv[1], ns=(ts * 1000000000, ts * 1000000000))
PY
run_history_collect > "$HOUT"
python3 - "$HOUT" <<'PY'
import json, sys
j = next(x for x in json.load(open(sys.argv[1]))["data"]["jobs"] if x["name"] == "com.gillettes.distinct")
assert [x["result"] for x in j["recent_runs"]] == ["failure", "failure", "success"], j
assert j["failure_streak"] == 0, j
PY
if [ "$?" -eq 0 ]; then pass "history: new error creates failure and distinct success resets streak";
else fail "history: distinct failure/success semantics"; fi

# Unparseable launchctl must preserve history bytes and report confidence unknown.
HIST_BEFORE="$(shasum "$HIST_HOME/job-history.json" | awk '{print $1}')"
TZ=UTC AUTOMATION_STATUS_NOW_EPOCH="$FAKE_NOW" MISSION_CONTROL_HOME="$HIST_HOME" \
  AUTOMATION_STATUS_LAUNCHCTL="$GARBAGE" python3 "$SC" --json --registry "$HREG" > "$HOUT"
HIST_AFTER="$(shasum "$HIST_HOME/job-history.json" | awk '{print $1}')"
if [ "$HIST_BEFORE" = "$HIST_AFTER" ] \
   && [ "$(getfield "$HOUT" com.gillettes.distinct history_confidence)" = "unknown" ]; then
  pass "history: unparseable state preserves persisted history and reports unknown"
else fail "history: unparseable state mutated history or hid uncertainty"; fi

# Keepalive red polls form one episode; recovery and a later red create new episodes.
printf 'down\n' > "$KEEPALIVE_MODE_FILE"
run_history_collect >/dev/null; run_history_collect > "$HOUT"
printf 'up\n' > "$KEEPALIVE_MODE_FILE"; run_history_collect >/dev/null
printf 'down\n' > "$KEEPALIVE_MODE_FILE"; run_history_collect > "$HOUT"
python3 - "$HOUT" <<'PY'
import json, sys
j = next(x for x in json.load(open(sys.argv[1]))["data"]["jobs"] if x["name"] == "com.gillettes.keepalive-episode")
assert [x["result"] for x in j["recent_runs"]] == ["failure", "success", "failure"], j
assert j["failure_streak"] == 1, j
PY
if [ "$?" -eq 0 ]; then pass "history: persistent keepalive failure is one episode";
else fail "history: keepalive polls inflated or lost episodes"; fi

# Twenty-event cap and atomic concurrent dedupe.
printf '1\n' > "$STATUS_FILE"
i=1
while [ "$i" -le 25 ]; do
  FAKE_NOW=$((FAKE_NOW + 1))
  python3 - "$RUN_ERR" "$FAKE_NOW" <<'PY'
import os, sys
ts = int(sys.argv[2]); os.utime(sys.argv[1], ns=(ts * 1000000000, ts * 1000000000))
PY
  run_history_collect >/dev/null
  i=$((i + 1))
done
run_history_collect > "$HOUT"
python3 - "$HOUT" "$HIST_HOME/job-history.json" <<'PY'
import json, os, stat, sys
env = json.load(open(sys.argv[1])); hist = json.load(open(sys.argv[2]))
j = next(x for x in env["data"]["jobs"] if x["name"] == "com.gillettes.distinct")
events = hist["jobs"]["com.gillettes.distinct"]["events"]
assert len(j["recent_runs"]) == 20 and len(events) == 20, (j, events)
assert len({x["run_key"] for x in events}) == 20, events
assert stat.S_IMODE(os.stat(sys.argv[2]).st_mode) == 0o600
PY
if [ "$?" -eq 0 ]; then pass "history: atomic file is mode 600, unique, and capped at twenty";
else fail "history: cap, uniqueness, or permissions"; fi

CONCURRENT_HOME="$RUNS/concurrent-home"; mkdir -p "$CONCURRENT_HOME"
TZ=UTC AUTOMATION_STATUS_NOW_EPOCH="$FAKE_NOW" MISSION_CONTROL_HOME="$CONCURRENT_HOME" \
  STATUS_FILE="$STATUS_FILE" KEEPALIVE_MODE_FILE="$KEEPALIVE_MODE_FILE" \
  AUTOMATION_STATUS_LAUNCHCTL="$HSTUB" python3 "$SC" --json --registry "$HREG" >/dev/null &
P1=$!
TZ=UTC AUTOMATION_STATUS_NOW_EPOCH="$FAKE_NOW" MISSION_CONTROL_HOME="$CONCURRENT_HOME" \
  STATUS_FILE="$STATUS_FILE" KEEPALIVE_MODE_FILE="$KEEPALIVE_MODE_FILE" \
  AUTOMATION_STATUS_LAUNCHCTL="$HSTUB" python3 "$SC" --json --registry "$HREG" >/dev/null &
P2=$!
wait "$P1"; R1=$?; wait "$P2"; R2=$?
python3 - "$CONCURRENT_HOME/job-history.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for row in d["jobs"].values():
    keys = [x["run_key"] for x in row.get("events", [])]
    assert len(keys) == len(set(keys))
PY
CRC=$?
if [ "$R1" -eq 0 ] && [ "$R2" -eq 0 ] && [ "$CRC" -eq 0 ]; then
  pass "history: concurrent writers preserve valid deduplicated atomic state"
else fail "history: concurrent writers failed (r1=$R1 r2=$R2 parse=$CRC)"; fi

# --- summary --------------------------------------------------------------
echo "-----"
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$FAILS FAIL(S)"; exit 1; fi
