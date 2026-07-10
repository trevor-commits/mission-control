#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
RUNNER="$ROOT/scripts/loose-end-runner"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
REPO=$(cd "$REPO" && pwd -P)
printf 'unchanged\n' > "$REPO/sentinel"
SENTINEL_BEFORE=$(shasum -a 256 "$REPO/sentinel" | awk '{print $1}')

STUB="$TMP/scanner-stub"

# The stub records every exact scanner invocation and emits one branch row.
# Its scenarios exercise each independent refusal and an action-time race.
python3 - "$STUB" <<'PY'
import os,sys
path=sys.argv[1]
body=r'''#!/usr/bin/env python3
import json,os,sys,time
if os.environ.get("GIT_OPTIONAL_LOCKS") != "0":
    print("optional locks not disabled", file=sys.stderr); sys.exit(3)
repo=(os.path.realpath(sys.argv[sys.argv.index("--repo")+1]) if "--repo" in sys.argv
      else os.path.realpath(os.environ["STUB_DEFAULT_REPO"]))
scenario=os.environ.get("STUB_SCENARIO","eligible")
call_log=os.environ["STUB_CALL_LOG"]
try:
    with open(call_log) as f: count=sum(1 for _ in f)
except OSError:
    count=0
with open(call_log,"a") as f:
    f.write(json.dumps(sys.argv[1:])+"\n")
count += 1
disable_on=int(os.environ.get("STUB_CREATE_DISABLE_ON_CALL","0") or 0)
if disable_on and count == disable_on:
    p=os.environ["STUB_DISABLE_PATH"]
    os.makedirs(os.path.dirname(p),exist_ok=True)
    open(p,"a").close()
now=int(time.time())
stable_epoch=1700000000
branch="feature-safe"
local="refs/heads/"+branch
remote_ref="refs/heads/"+branch
row={
 "name":branch,"local_ref":local,
 "upstream_ref":"refs/remotes/origin/feature-safe",
 "remote_name":"origin","remote_classification":"local",
 "remote_branch_ref":remote_ref,"ahead":1,"behind":0,
 "default_branch":"main","is_default":False,"is_protected":False,
 "remote_is_default":False,"remote_is_protected":False,
 "checkout_paths":[],"repo_or_worktree_dirty":False,
 "worktree_state_known":True,
 "last_commit":{"sha":"a"*40,"subject":"not persisted by runner","epoch":stable_epoch},
 "last_activity":{"epoch":stable_epoch,"age_seconds":30000,"state":"stale",
                  "guard_seconds":21600,"evidence":"reflog_or_commit"},
 "facts_generated_epoch":now,"facts_max_age_seconds":120,
 "activity_facts_fresh":True,"push_eligible":True,"refusal_reasons":[],
 "proposal_argv":["git","-C",repo,"push","--","origin",local+":"+remote_ref],
}
def refuse(reason):
    row["push_eligible"]=False; row["refusal_reasons"].append(reason); row["proposal_argv"]=None
if scenario == "checked_out": row["checkout_paths"]=[repo]; refuse("branch_checked_out")
elif scenario == "becomes_checked_out" and count >= 2: row["checkout_paths"]=[repo]; refuse("branch_checked_out")
elif scenario == "dirty": row["repo_or_worktree_dirty"]=True; refuse("repo_or_worktree_dirty")
elif scenario == "dirty_lie": row["repo_or_worktree_dirty"]=True
elif scenario == "no_upstream": row["upstream_ref"]=None; refuse("upstream_missing")
elif scenario == "behind": row["ahead"]=0; row["behind"]=1; refuse("behind_upstream")
elif scenario == "diverged": row["behind"]=1; refuse("diverged_upstream")
elif scenario == "default": row["is_default"]=True; refuse("default_branch")
elif scenario == "default_unknown": row["default_branch"]=None
elif scenario == "protected": row["is_protected"]=True; refuse("protected_branch")
elif scenario == "remote_default_target":
    row["remote_branch_ref"]="refs/heads/main"
    row["upstream_ref"]="refs/remotes/origin/main"
    row["remote_is_default"]=True; row["remote_is_protected"]=True
    row["proposal_argv"]=["git","-C",repo,"push","--","origin",local+":refs/heads/main"]
elif scenario == "upstream_mismatch":
    row["upstream_ref"]="refs/remotes/origin/different"
elif scenario == "recent":
    row["last_activity"].update(epoch=now-10,age_seconds=10,state="recent"); refuse("recent_activity")
elif scenario == "unknown_activity":
    row["last_activity"].update(epoch=None,age_seconds=None,state="unknown"); refuse("activity_unknown")
elif scenario == "weak_guard":
    row["last_activity"].update(epoch=now-100,age_seconds=100,state="stale",guard_seconds=0)
elif scenario == "credential":
    row["remote_classification"]="credentialed"
    row["raw_remote_url"]="https://user:never-print-this@example.invalid/repo.git"
    refuse("remote_credentials")
elif scenario == "stale_facts":
    row["facts_generated_epoch"]=now-999; row["activity_facts_fresh"]=False; refuse("activity_facts_not_fresh")
elif scenario == "after_stale" and count >= 3:
    row["facts_generated_epoch"]=now-999; row["activity_facts_fresh"]=False; refuse("activity_facts_not_fresh")
elif scenario == "changed" and count >= 3:
    row["last_commit"]["sha"]="b"*40
elif scenario == "sensitive_ref":
    secret="sk-abcdefghijklmnopqrstuvwxyz123456"
    row["name"]=secret; row["local_ref"]="refs/heads/"+secret
    row["upstream_ref"]="refs/remotes/origin/"+secret
    row["remote_branch_ref"]="refs/heads/"+secret
    row["proposal_argv"]=["git","-C",repo,"push","--","origin",row["local_ref"]+":"+row["remote_branch_ref"]]
payload={"generated":"now","stale_days":21,"findings_total":1,"repos":[{
 "repo":os.path.basename(repo),"path":repo,"branch":"main","branches":[],"branch_facts":[row]}]}
print(json.dumps(payload))
sys.exit(1)
'''
with open(path,"w") as f: f.write(body)
os.chmod(path,0o755)
PY

pass=0
fail=0
ok() { pass=$((pass+1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail+1)); }

run_case() {
  name="$1"
  home="$TMP/home-$name"
  calls="$TMP/calls-$name.jsonl"
  out="$TMP/out-$name.json"
  mkdir -p "$home"
  if MISSION_CONTROL_HOME="$home" STUB_SCENARIO="$name" STUB_CALL_LOG="$calls" \
      "$RUNNER" --scanner "$STUB" --repo "$REPO" > "$out"; then :; else bad "$name runner exit"; return; fi
  if python3 - "$name" "$out" "$home/loose-end-runner/report.jsonl" "$calls" "$REPO" <<'PY'
import json,os,stat,sys
name,outp,logp,callp,repo=sys.argv[1:]
with open(outp) as f: out=json.load(f)
assert out["status"] == "dry-run" and out["dry_run"] is True
assert out["automatic_push_enabled"] is False
assert len(out["actions"]) == 1, out
with open(logp) as f: lines=[json.loads(x) for x in f if x.strip()]
assert len(lines)==1 and lines[0]==out["actions"][0]
r=lines[0]
assert r["tier"]=="explicit_branch_push" and r["mode"]=="dry-run"
assert r["before"]["repo_path"]==repo and r["after"]["repo_path"]==repo
assert "subject" not in r["before"]["last_commit"]
assert stat.S_IMODE(os.stat(logp).st_mode)==0o600
assert stat.S_IMODE(os.stat(os.path.dirname(logp)).st_mode)==0o700
with open(callp) as f: calls=[json.loads(x) for x in f if x.strip()]
assert len(calls)==3, calls
assert all(c==["--json","--repo",repo] for c in calls), calls
expected=["git","-C",repo,"push","--","origin",
          "refs/heads/feature-safe:refs/heads/feature-safe"]
if name=="eligible":
    assert r["decision"]=="proposed" and r["argv"]==expected, r
else:
    assert r["decision"]=="refused" and r["argv"] is None, r
checks={
 "checked_out":"branch_checked_out", "becomes_checked_out":"branch_checked_out",
 "dirty":"repo_or_worktree_dirty", "dirty_lie":"repo_or_worktree_dirty",
 "no_upstream":"upstream_missing",
 "behind":"behind_upstream", "diverged":"diverged_upstream",
 "default":"default_branch", "protected":"protected_branch",
 "default_unknown":"default_branch_unknown",
 "remote_default_target":"remote_target_default_or_protected",
 "upstream_mismatch":"upstream_remote_mismatch",
 "recent":"recent_activity", "unknown_activity":"activity_unknown",
 "weak_guard":"recent_or_unknown_activity",
 "credential":"remote_credentials", "stale_facts":"activity_facts_not_fresh",
 "after_stale":"activity_facts_not_fresh",
 "changed":"facts_changed_during_evaluation",
}
if name in checks: assert checks[name] in r["reason"], (checks[name],r)
raw=json.dumps(out)+open(logp).read()
assert "never-print-this" not in raw and "example.invalid" not in raw
PY
  then ok; else bad "$name contract"; fi
}

# Hard DISABLE is checked before log creation or scanner invocation.
DISABLED_HOME="$TMP/home-disabled"
mkdir -p "$DISABLED_HOME/loose-end-runner"
: > "$DISABLED_HOME/loose-end-runner/DISABLE"
if MISSION_CONTROL_HOME="$DISABLED_HOME" STUB_SCENARIO=eligible \
    STUB_CALL_LOG="$TMP/calls-disabled" "$RUNNER" --scanner "$STUB" --repo "$REPO" \
    > "$TMP/out-disabled.json"; then
  if python3 - "$TMP/out-disabled.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d=={"actions":[],"dry_run":True,"status":"disabled"}
PY
  then ok; else bad "DISABLE response"; fi
else bad "DISABLE exit"; fi
[ ! -e "$TMP/calls-disabled" ] && [ ! -e "$DISABLED_HOME/loose-end-runner/report.jsonl" ] && ok || bad "DISABLE touched scanner/log"

# There is deliberately no live execution route.
if MISSION_CONTROL_HOME="$TMP/home-execute" STUB_SCENARIO=eligible \
    STUB_CALL_LOG="$TMP/calls-execute" "$RUNNER" --execute --scanner "$STUB" --repo "$REPO" \
    > "$TMP/out-execute" 2> "$TMP/err-execute"; then
  bad "--execute unexpectedly accepted"
else
  [ ! -e "$TMP/calls-execute" ] && ok || bad "--execute called scanner"
fi

for case_name in eligible checked_out becomes_checked_out dirty dirty_lie no_upstream behind diverged default default_unknown protected remote_default_target upstream_mismatch recent unknown_activity weak_guard credential stale_facts after_stale changed; do
  run_case "$case_name"
done

# Sensitive refs/argv must produce only a content-free refusal.
SENSITIVE_HOME="$TMP/home-sensitive"
if MISSION_CONTROL_HOME="$SENSITIVE_HOME" STUB_SCENARIO=sensitive_ref \
    STUB_CALL_LOG="$TMP/calls-sensitive" "$RUNNER" --scanner "$STUB" --repo "$REPO" \
    > "$TMP/out-sensitive.json"; then
  if ! rg -q 'sk-abcdefghijklmnopqrstuvwxyz123456' "$TMP/out-sensitive.json" "$SENSITIVE_HOME/loose-end-runner/report.jsonl" &&
      python3 - "$TMP/out-sensitive.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["actions"][0]["reason"]=="privacy_rejected", d
PY
  then ok; else bad "shared privacy content-free refusal"; fi
else bad "sensitive-ref exit"; fi

# DISABLE races: after discovery and before append must stop without a log.
for disable_call in 1 3; do
  race_home="$TMP/home-disable-race-$disable_call"
  race_disable="$race_home/loose-end-runner/DISABLE"
  if MISSION_CONTROL_HOME="$race_home" STUB_SCENARIO=eligible \
      STUB_CALL_LOG="$TMP/calls-disable-race-$disable_call" \
      STUB_CREATE_DISABLE_ON_CALL="$disable_call" STUB_DISABLE_PATH="$race_disable" \
      "$RUNNER" --scanner "$STUB" --repo "$REPO" > "$TMP/out-disable-race-$disable_call.json"; then
    [ ! -e "$race_home/loose-end-runner/report.jsonl" ] && ok || bad "DISABLE race $disable_call logged"
  else bad "DISABLE race $disable_call exit"; fi
done

# Existing checked duplicate todo text is detected as a proposal, without edit.
printf '%s\n' '## Work' '- [x] Same deterministic item' '- [ ] Same deterministic item' > "$REPO/todo.md"
TODO_BEFORE=$(shasum -a 256 "$REPO/todo.md" | awk '{print $1}')
LOCAL_HOME="$TMP/home-local-proposals"
mkdir -p "$LOCAL_HOME/export"
printf '%s\n' '{"data":{"loose_ends":[]}}' > "$LOCAL_HOME/export/graph.json"
if MISSION_CONTROL_HOME="$LOCAL_HOME" STUB_SCENARIO=eligible STUB_CALL_LOG="$TMP/calls-local" \
    "$RUNNER" --scanner "$STUB" --repo "$REPO" > "$TMP/out-local.json"; then
  TODO_AFTER=$(shasum -a 256 "$REPO/todo.md" | awk '{print $1}')
  if [ "$TODO_BEFORE" = "$TODO_AFTER" ] && python3 - "$TMP/out-local.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); tiers=[x["tier"] for x in d["actions"]]
assert "satisfied_todo_detection" in tiers, tiers
assert "open_end_reconciliation" in tiers, tiers
assert all(x.get("mode")=="dry-run" for x in d["actions"])
PY
  then ok; else bad "local reconciliation/todo proposals"; fi
else bad "local proposal exit"; fi
rm -f "$REPO/todo.md"

# A short JSONL write must roll back to its exact prior length.
if python3 - "$RUNNER" "$TMP/short-write.jsonl" <<'PY'
import importlib.machinery,os,sys
m=importlib.machinery.SourceFileLoader("runner_short_write",sys.argv[1]).load_module()
p=m.Path(sys.argv[2]); p.write_bytes(b"prior\n")
real=m.os.write; calls=[0]
def short(fd,data):
    calls[0]+=1
    if calls[0]==1: return real(fd,bytes(data[:max(1,len(data)//2)]))
    return 0
m.os.write=short
try: m.append_jsonl(p,{"safe":"value"})
except RuntimeError: pass
else: raise AssertionError("short write accepted")
finally: m.os.write=real
assert p.read_bytes()==b"prior\n", p.read_bytes()
PY
then ok; else bad "short-write rollback"; fi

# DISABLE created by the first append syscall rolls the record back exactly.
if python3 - "$RUNNER" "$TMP/disable-write.jsonl" "$TMP/DISABLE-during-write" <<'PY'
import importlib.machinery,os,sys
m=importlib.machinery.SourceFileLoader("runner_disable_write",sys.argv[1]).load_module()
p=m.Path(sys.argv[2]); stop=m.Path(sys.argv[3]); p.write_bytes(b"prior\n")
real=m.os.write
def racing_write(fd,data):
    stop.touch()
    return real(fd,data)
m.os.write=racing_write
try:
    committed=m.append_jsonl(p,{"safe":"value"},lambda: stop.exists())
finally:
    m.os.write=real
assert committed is False
assert p.read_bytes()==b"prior\n", p.read_bytes()
PY
then ok; else bad "DISABLE append-window rollback"; fi

# Without --repo, the runner discovers the bounded repository list once, then
# still uses exact-repo recomputation immediately before and after proposals.
DEFAULT_HOME="$TMP/home-default-scope"
DEFAULT_CALLS="$TMP/calls-default-scope.jsonl"
if MISSION_CONTROL_HOME="$DEFAULT_HOME" STUB_SCENARIO=eligible STUB_CALL_LOG="$DEFAULT_CALLS" \
    STUB_DEFAULT_REPO="$REPO" "$RUNNER" --scanner "$STUB" > "$TMP/out-default-scope.json"; then
  if python3 - "$TMP/out-default-scope.json" "$DEFAULT_CALLS" "$REPO" <<'PY'
import json,sys
out=json.load(open(sys.argv[1])); calls=[json.loads(x) for x in open(sys.argv[2]) if x.strip()]
repo=sys.argv[3]
assert len(out["actions"])==1 and out["actions"][0]["decision"]=="proposed", out
assert calls==[["--json"],["--json","--repo",repo],["--json","--repo",repo]], calls
PY
  then ok; else bad "default discovery contract"; fi
else bad "default discovery exit"; fi

# The stub receives scanner invocations only. The runner never invokes git push.
if ! rg -q '"push"' "$TMP"/calls-*.jsonl 2>/dev/null; then ok; else bad "runner executed or delegated push"; fi
SENTINEL_AFTER=$(shasum -a 256 "$REPO/sentinel" | awk '{print $1}')
[ "$SENTINEL_BEFORE" = "$SENTINEL_AFTER" ] && ok || bad "repository sentinel mutated"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
