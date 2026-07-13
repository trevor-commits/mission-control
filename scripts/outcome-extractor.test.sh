#!/usr/bin/env bash
# outcome-extractor.test.sh — isolated, bounded Tier 2 outcome extraction.
# Synthetic transcripts and a local stub only: no network, real model, or real HOME.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CG="$HERE/chat-graph"
FAILS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

q() {
  python3 - "$1" <<'PY'
import os, sqlite3, sys
con = sqlite3.connect(os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db"))
row = con.execute(sys.argv[1]).fetchone()
print(row[0] if row is not None else "")
PY
}

new_env() {
  export TIER2_TMP="$(mktemp -d)"
  export CHAT_GRAPH_HOME="$TIER2_TMP/graph"
  export MISSION_CONTROL_HOME="$TIER2_TMP/mission-control"
  export CHAT_GRAPH_CROSS_AGENT_ROOT="$TIER2_TMP/cross-agent"
  export CHAT_GRAPH_SESSION_INDEX="$TIER2_TMP/session-index.jsonl"
  export CHAT_GRAPH_CLAUDE_ROOT="$TIER2_TMP/claude"
  export CHAT_GRAPH_CODEX_ROOT="$TIER2_TMP/codex"
  export CHAT_GRAPH_CURSOR_ROOT="$TIER2_TMP/cursor"
  export CHAT_GRAPH_HERMES_ROOT="$TIER2_TMP/hermes"
  export CHAT_GRAPH_HERMES_STATE_DB="$TIER2_TMP/hermes-state.db"
  export CHAT_GRAPH_COPILOT_ROOT="$TIER2_TMP/copilot"
  export CHAT_GRAPH_CODING_ROOT="$TIER2_TMP/repos"
  export CHAT_GRAPH_REPO_ROOTS="$TIER2_TMP/repos"
  export CHAT_GRAPH_NIGHTLY_REPORT_GLOB="$TIER2_TMP/nightly/*.md"
  export CHAT_GRAPH_SCAN_CMD="/bin/echo []"
  export CHAT_GRAPH_REGISTER="$TIER2_TMP/register.md"
  export CHAT_GRAPH_CHAT_SOURCE="$TIER2_TMP/chat-source"
  mkdir -p "$CHAT_GRAPH_CLAUDE_ROOT/project" "$CHAT_GRAPH_CODEX_ROOT" \
           "$CHAT_GRAPH_CURSOR_ROOT" "$CHAT_GRAPH_HERMES_ROOT" \
           "$CHAT_GRAPH_COPILOT_ROOT" "$CHAT_GRAPH_CODING_ROOT" \
           "$CHAT_GRAPH_HOME" "$TIER2_TMP/nightly"
  : > "$CHAT_GRAPH_SESSION_INDEX"
  : > "$CHAT_GRAPH_REGISTER"
  cat > "$CHAT_GRAPH_CHAT_SOURCE" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  describe) echo "provider: ${CHAT_SOURCE_PROVIDER:-claude}" ;;
  resolve) echo "${2:-}" ;;
esac
exit 0
SH
  chmod +x "$CHAT_GRAPH_CHAT_SOURCE"

  export MORNING_BRIEF_LLM=1
  export MORNING_BRIEF_LLM_CLAUDE=1
  export MORNING_BRIEF_LLM_CODEX=1
  export MORNING_BRIEF_LLM_CURSOR=1
  export MORNING_BRIEF_LLM_HERMES=1
  export MORNING_BRIEF_LLM_COPILOT=1
  export MORNING_BRIEF_LLM_DAILY_CALL_CAP=20
  export MORNING_BRIEF_LLM_DAILY_TOKEN_CAP=100000
  export MORNING_BRIEF_LLM_MODEL="claude-haiku-4-5-20251001"
  export MORNING_BRIEF_LLM_TIMEOUT=8
  export MORNING_BRIEF_LLM_TESTING=1
  unset MORNING_BRIEF_LLM_TEST_PROMPT_VERSION MORNING_BRIEF_LLM_MAX_OUTPUT_TOKENS
  export MORNING_BRIEF_LLM_CMD="$TIER2_TMP/claude-stub"
  export STUB_CAPTURE="$TIER2_TMP/model-calls.jsonl"
  export STUB_PROMPT="$TIER2_TMP/model-prompt.txt"
  export STUB_STARTED="$TIER2_TMP/model-started"
  export STUB_BEHAVIOR=success
  cat > "$MORNING_BRIEF_LLM_CMD" <<'PY'
#!/usr/bin/env python3
import json, os, sys, time

prompt = sys.stdin.read()
with open(os.environ["STUB_PROMPT"], "w") as handle:
    handle.write(prompt)
with open(os.environ["STUB_CAPTURE"], "a") as handle:
    handle.write(json.dumps({
        "argv": sys.argv[1:],
        "oauth_timeout": int(os.environ.get("CLAUDE_OAUTH_LOCK_TIMEOUT", "0")),
        "newest_marker": "NEWEST_MARKER" in prompt,
    }, sort_keys=True) + "\n")
open(os.environ["STUB_STARTED"], "w").close()
behavior = os.environ.get("STUB_BEHAVIOR", "success")
if behavior == "slow":
    time.sleep(2.5)
elif behavior == "defer":
    sys.stderr.write("claude-oauth-lock: another claude holds the OAuth lock\n")
    sys.exit(75)
elif behavior == "defer_slow":
    time.sleep(int(os.environ.get("CLAUDE_OAUTH_LOCK_TIMEOUT", "1")) + 0.2)
    sys.stderr.write("claude-oauth-lock: another claude holds the OAuth lock\n")
    sys.exit(75)
elif behavior == "invalid":
    print("not-json")
    sys.exit(0)
elif behavior == "oversized":
    print("X" * 20000)
    sys.exit(0)

result = {
    "did": ["analysis_completed"],
    "left_open": ["follow_up_remaining"],
    "needs_trevor": ["review_evidence"],
    "confidence": 0.74,
    "ambiguity": False,
}
if behavior == "ambiguous":
    model = sys.argv[sys.argv.index("--model") + 1]
    result = {
        "did": ["work_verified"] if "sonnet" in model else [],
        "left_open": [],
        "needs_trevor": [] if "sonnet" in model else ["resolve_ambiguity"],
        "confidence": 0.71,
        "ambiguity": "sonnet" not in model,
    }
elif behavior == "ambiguous_always":
    result = {
        "did": ["analysis_completed"],
        "left_open": [], "needs_trevor": [], "confidence": 0.31,
        "ambiguity": True,
    }
print(json.dumps({
    "type": "result", "subtype": "success", "is_error": False,
    "result": json.dumps(result, sort_keys=True),
    "usage": {"input_tokens": 120, "output_tokens": 44},
}))
PY
  chmod +x "$MORNING_BRIEF_LLM_CMD"
}

write_claude_source() {
  local sid="$1" shape="$2"
  local path="$CHAT_GRAPH_CLAUDE_ROOT/project/$sid.jsonl"
  if [ "$shape" = structured ]; then
    cat > "$path" <<'JSONL'
{"id":"safe-1","role":"assistant","type":"assistant","content":"Re: orchestration\n\nAnswer\nThe run completed.\n\nDone\n- Implemented the deterministic layer.\n\nNext\n- Review the bounded follow-up.\n\nVerification\nCommit: 1a2b3c4"}
JSONL
  else
    cat > "$path" <<'JSONL'
{"id":"safe-1","role":"assistant","type":"assistant","content":"I traced the orchestration run and found useful work, but the closeout is not written in a standard format."}
JSONL
  fi
  cat >> "$path" <<'JSONL'
{"id":"tool-1","role":"tool","type":"tool_result","content":"raw tool output sk-abcdefghijklmnopqrstuvwxyz123456"}
{"id":"path-1","role":"assistant","type":"assistant","content":"A private artifact lives at /Users/gillettes/Downloads/private/tail.txt"}
{"id":"pii-1","role":"assistant","type":"assistant","content":"Contact private.person@example.com for the hidden detail"}
JSONL
}

seed_high_value() {
  local sid="$1" provider="${2:-claude}"
  "$CG" ingest --full >/dev/null 2>&1
  python3 - "$sid" "$provider" <<'PY'
import os, sqlite3, sys
sid, provider = sys.argv[1:]
con = sqlite3.connect(os.path.join(os.environ["CHAT_GRAPH_HOME"], "graph.db"))
con.execute("UPDATE sessions SET repo='mission-control',provider=?,node_kind='chat' WHERE id=?",
            (provider, sid))
con.commit()
PY
}

run_extract() {
  "$CG" extract-outcomes --days 7 --limit 20 --json
}

# Global kill switch: normal ingest/export remain deterministic and never call a model.
new_env
SID0="10000000-0000-4000-8000-000000000000"
write_claude_source "$SID0" unstructured
seed_high_value "$SID0"
export MORNING_BRIEF_LLM=0
if run_extract > "$TIER2_TMP/disabled.json" 2> "$TIER2_TMP/disabled.err" \
   && [ ! -e "$STUB_CAPTURE" ]; then
  pass "global kill switch makes no model call"
else
  fail "global kill switch"
fi
rm -f "$STUB_CAPTURE" "$STUB_PROMPT" "$STUB_STARTED"
"$CG" ingest >/dev/null 2>&1
"$CG" export --json --catchup-limit 0 >/dev/null 2>&1
if [ ! -e "$STUB_CAPTURE" ]; then pass "ingest and export never invoke Tier 2"
else fail "ingest/export invoked the model stub"; fi

# Only Fable's high-value subset is eligible; an unrelated tail is ignored.
new_env
SID0B="10000000-0000-4000-8000-000000000001"
write_claude_source "$SID0B" unstructured
"$CG" ingest --full >/dev/null 2>&1
if run_extract > "$TIER2_TMP/low-value.json" 2> "$TIER2_TMP/low-value.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && python3 - "$TIER2_TMP/low-value.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["eligible"] == 0 and d["calls"] == 0
PY
then
  pass "low-value tail without repo, commit, or lineage evidence is skipped"
else
  fail "high-value candidate subset"
fi

# The extractor lock serializes model work without sharing the ingest lock.
new_env
SID0C="10000000-0000-4000-8000-000000000002"
write_claude_source "$SID0C" unstructured
seed_high_value "$SID0C"
mkdir "$CHAT_GRAPH_HOME/outcome-extract.lock"
if run_extract > "$TIER2_TMP/lock.json" 2> "$TIER2_TMP/lock.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && [ "$(q "SELECT lock_skips FROM outcome_extraction_health")" -ge 1 ]; then
  pass "separate extractor lock defers overlapping model work"
else
  fail "separate extractor lock"
fi
rmdir "$CHAT_GRAPH_HOME/outcome-extract.lock"

# Age alone cannot steal a lock from a still-live extractor process.
new_env
SID0D="10000000-0000-4000-8000-000000000003"
write_claude_source "$SID0D" unstructured
seed_high_value "$SID0D"
sleep 10 & LOCK_OWNER_PID=$!
mkdir "$CHAT_GRAPH_HOME/outcome-extract.lock"
python3 - "$CHAT_GRAPH_HOME/outcome-extract.lock" "$LOCK_OWNER_PID" <<'PY'
import json,os,sys,time
path,pid=sys.argv[1],int(sys.argv[2])
with open(os.path.join(path,"owner.json"),"w") as handle:
    json.dump({"pid":pid,"token":"another-run","started_at":int(time.time())-3600},handle)
old=time.time()-1900
os.utime(path,(old,old))
PY
if run_extract > "$TIER2_TMP/live-lock.json" 2> "$TIER2_TMP/live-lock.err" \
   && [ -d "$CHAT_GRAPH_HOME/outcome-extract.lock" ] \
   && [ ! -e "$STUB_CAPTURE" ]; then
  pass "aged lock owned by a live process is never stolen"
else
  fail "live owner lock protection"
fi
kill "$LOCK_OWNER_PID" >/dev/null 2>&1
wait "$LOCK_OWNER_PID" 2>/dev/null
rm -f "$CHAT_GRAPH_HOME/outcome-extract.lock/owner.json"
rmdir "$CHAT_GRAPH_HOME/outcome-extract.lock"

# A reused live PID with a mismatched process-start identity belongs to the
# crashed former owner and is reclaimable after the stale horizon.
new_env
SID0E="10000000-0000-4000-8000-000000000004"
write_claude_source "$SID0E" unstructured
seed_high_value "$SID0E"
mkdir "$CHAT_GRAPH_HOME/outcome-extract.lock"
python3 - "$CHAT_GRAPH_HOME/outcome-extract.lock" "$$" <<'PY'
import json,os,sys,time
path,pid=sys.argv[1],int(sys.argv[2])
with open(os.path.join(path,"owner.json"),"w") as handle:
    json.dump({"pid":pid,"token":"crashed-owner","start":"definitely-not-this-process"},handle)
old=time.time()-7200
os.utime(path,(old,old))
PY
if run_extract > "$TIER2_TMP/reused-pid-lock.json" 2> "$TIER2_TMP/reused-pid-lock.err" \
   && [ ! -d "$CHAT_GRAPH_HOME/outcome-extract.lock" ] \
   && [ -e "$STUB_CAPTURE" ]; then
  pass "stale extractor lock with reused PID identity is reclaimed"
else
  fail "reused PID extractor lock reclaim"
fi

for STALE_KIND in ownerless corrupt; do
  new_env
  case "$STALE_KIND" in
    ownerless) SID0E="10000000-0000-4000-8000-000000000004" ;;
    *) SID0E="10000000-0000-4000-8000-000000000005" ;;
  esac
  write_claude_source "$SID0E" unstructured
  seed_high_value "$SID0E"
  mkdir "$CHAT_GRAPH_HOME/outcome-extract.lock"
  if [ "$STALE_KIND" = corrupt ]; then
    printf '%s\n' 'not-json' > "$CHAT_GRAPH_HOME/outcome-extract.lock/owner.json"
  fi
  python3 - "$CHAT_GRAPH_HOME/outcome-extract.lock" <<'PY'
import os,sys,time
old=time.time()-1900
os.utime(sys.argv[1],(old,old))
PY
  if run_extract > "$TIER2_TMP/stale-$STALE_KIND.json" \
       2> "$TIER2_TMP/stale-$STALE_KIND.err" \
     && [ -e "$STUB_CAPTURE" ] \
     && [ ! -d "$CHAT_GRAPH_HOME/outcome-extract.lock" ]; then
    pass "stale $STALE_KIND extractor lock is safely reclaimed"
  else
    fail "stale $STALE_KIND extractor lock reclaim"
  fi
done

# Zero budget fails open to Tier 1 and records content-free health.
new_env
SID1="11111111-1111-4111-8111-111111111111"
write_claude_source "$SID1" unstructured
seed_high_value "$SID1"
export MORNING_BRIEF_LLM_DAILY_CALL_CAP=0
if run_extract > "$TIER2_TMP/budget.json" 2> "$TIER2_TMP/budget.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='$SID1' AND method='tier1'")" = 1 ] \
   && [ "$(q "SELECT budget_skips FROM outcome_extraction_health ORDER BY day DESC LIMIT 1")" -ge 1 ]; then
  pass "zero budget skips calls, preserves Tier 1, and records health"
else
  fail "zero-budget fail-open contract"
fi

# Per-source-provider kill switch is independent from the global switch.
new_env
SID2="22222222-2222-4222-8222-222222222222"
write_claude_source "$SID2" structured
seed_high_value "$SID2"
export MORNING_BRIEF_LLM_CLAUDE=0
if run_extract > "$TIER2_TMP/provider.json" 2> "$TIER2_TMP/provider.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && [ "$(q "SELECT provider_skips FROM outcome_extraction_health ORDER BY day DESC LIMIT 1")" -ge 1 ]; then
  pass "per-provider kill switch prevents cross-provider egress"
else
  fail "per-provider kill switch"
fi

# Omitted providers in a valid calibrated config are off even when an inherited
# environment tries to enable them.
new_env
mkdir -p "$MISSION_CONTROL_HOME/outcome-extractor"
cat > "$MISSION_CONTROL_HOME/outcome-extractor/config.json" <<'JSON'
{"schema":"mission-control/outcome-extractor-config/v1","enabled":true,"daily_call_cap":5,"daily_token_cap":50000,"providers":{"claude":true}}
JSON
if python3 - "$HERE" <<'PY'
import os,sys
sys.path.insert(0,sys.argv[1])
import outcome_extractor as module
os.environ["MORNING_BRIEF_LLM_CODEX"]="1"
assert module._load_config_env() == "uncalibrated"
assert os.environ["MORNING_BRIEF_LLM"] == "0"
assert os.environ["MORNING_BRIEF_LLM_CLAUDE"] == "0"
assert os.environ["MORNING_BRIEF_LLM_CODEX"] == "0"
assert all(os.environ["MORNING_BRIEF_LLM_%s" % name.upper()] == "0"
           for name in ("cursor","hermes","copilot"))
PY
then
  pass "calibrated provider omission dominates ambient enable"
else
  fail "calibrated provider scope precedence"
fi

new_env
SID2B="22222222-2222-4222-8222-222222222223"
write_claude_source "$SID2B" structured
seed_high_value "$SID2B"
mkdir -p "$MISSION_CONTROL_HOME/outcome-extractor"
cat > "$MISSION_CONTROL_HOME/outcome-extractor/config.json" <<'JSON'
{"schema":"mission-control/outcome-extractor-config/v1","enabled":"yes","daily_call_cap":5,"daily_token_cap":50000,"providers":{"claude":true,"codex":true,"cursor":true,"hermes":true,"copilot":true}}
JSON
export MORNING_BRIEF_LLM_TESTING=0 MORNING_BRIEF_LLM=1
if run_extract > "$TIER2_TMP/malformed-config.json" 2> "$TIER2_TMP/malformed-config.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && python3 - "$TIER2_TMP/malformed-config.json" <<'PY'
import json,sys
row=json.load(open(sys.argv[1]))
assert row["uncalibrated_skips"] == 1 and row["calls"] == 0
PY
then
  pass "malformed calibration cannot egress through ambient enable"
else
  fail "malformed calibration fail-closed"
fi

# Loaded production caps keep the same hard ceiling as calibration output and
# reject bool-as-int corruption.
new_env
mkdir -p "$MISSION_CONTROL_HOME/outcome-extractor"
if python3 - "$HERE" "$MISSION_CONTROL_HOME/outcome-extractor/config.json" <<'PY'
import json,os,sys
sys.path.insert(0,sys.argv[1])
import outcome_extractor as module
path=sys.argv[2]
base={"schema":"mission-control/outcome-extractor-config/v1","enabled":True,
      "providers":{name:True for name in ("claude","codex","cursor","hermes","copilot")}}
for calls,tokens in ((10**12,10**18),(True,50000),(5,False)):
    value=dict(base,daily_call_cap=calls,daily_token_cap=tokens)
    json.dump(value,open(path,"w"))
    os.environ["MORNING_BRIEF_LLM"]="1"
    assert module._load_config_env() == "uncalibrated"
    assert os.environ["MORNING_BRIEF_LLM"] == "0"
json.dump(dict(base,daily_call_cap=100,daily_token_cap=10000000),open(path,"w"))
os.environ.pop("MORNING_BRIEF_LLM",None)
os.environ.pop("MORNING_BRIEF_LLM_DAILY_CALL_CAP",None)
os.environ.pop("MORNING_BRIEF_LLM_DAILY_TOKEN_CAP",None)
assert module._load_config_env() == "ready"
assert os.environ["MORNING_BRIEF_LLM_DAILY_CALL_CAP"] == "100"
assert os.environ["MORNING_BRIEF_LLM_DAILY_TOKEN_CAP"] == "10000000"
PY
then
  pass "loaded calibration enforces non-boolean hard budget ceilings"
else
  fail "loaded hard budget ceiling"
fi

# Export must use the exact same calibrated-config validity boundary as the
# extractor; invalid caps/provider shapes cannot keep stale Tier 2 current.
if python3 - "$HERE/chat-graph" "$MISSION_CONTROL_HOME/outcome-extractor/config.json" <<'PY'
import importlib.machinery,importlib.util,json,os,sys
sys.path.insert(0,os.path.dirname(sys.argv[1]))
loader=importlib.machinery.SourceFileLoader("chat_graph_config_test",sys.argv[1])
spec=importlib.util.spec_from_loader(loader.name,loader)
graph=importlib.util.module_from_spec(spec); loader.exec_module(graph)
path=sys.argv[2]
os.environ["MORNING_BRIEF_LLM_TESTING"]="0"
os.environ["MORNING_BRIEF_LLM"]="1"
base={"schema":"mission-control/outcome-extractor-config/v1","enabled":True,
      "providers":{name:True for name in ("claude","codex","cursor","hermes","copilot")}}
invalid=(
    dict(base,daily_call_cap=10**12,daily_token_cap=10**18),
    dict(base,daily_call_cap=True,daily_token_cap=50000),
    dict(base,daily_call_cap=5,daily_token_cap=50000,
         providers={"claude":True}),
)
for value in invalid:
    json.dump(value,open(path,"w"))
    assert graph._tier2_export_providers()==set(),value
valid=dict(base,daily_call_cap=100,daily_token_cap=10000000)
json.dump(valid,open(path,"w"))
assert graph._tier2_export_providers()==set(graph.CHAT_PROVIDERS)
PY
then
  pass "extractor and export share the strict calibrated-config boundary"
else
  fail "extractor/export config parity"
fi

# A successful high-value call uses fixed argv/stdin, sanitized input, narrative-only
# output, deterministic anchors, a content-hash cache, and private state.
new_env
SID3="33333333-3333-4333-8333-333333333333"
write_claude_source "$SID3" structured
seed_high_value "$SID3"
export MORNING_BRIEF_LLM_MAX_OUTPUT_TOKENS=4096
if run_extract > "$TIER2_TMP/success.json" 2> "$TIER2_TMP/success.err"; then
  pass "bounded Tier 2 command exits zero"
else
  fail "bounded Tier 2 command exits zero"
fi
if python3 - "$STUB_CAPTURE" "$STUB_PROMPT" "$CHAT_GRAPH_HOME/graph.db" "$SID3" \
  "$MISSION_CONTROL_HOME/outcome-extractor/last-run.json" <<'PY'
import json, os, sqlite3, sys
capture, prompt_path, db, sid, marker_path = sys.argv[1:]
call = json.loads(open(capture).readline())
argv = call["argv"]
assert 1 <= call["oauth_timeout"] < 8, call["oauth_timeout"]
assert "--model" in argv and argv[argv.index("--model") + 1] == "claude-haiku-4-5-20251001"
assert "--output-format" in argv and argv[argv.index("--output-format") + 1] == "json"
schema=json.loads(argv[argv.index("--json-schema")+1])
assert schema["properties"]["did"]["maxItems"] == 4
assert "analysis_completed" in schema["properties"]["did"]["items"]["enum"]
assert "Run deploy" not in schema["properties"]["did"]["items"]["enum"]
assert "--no-session-persistence" in argv
assert "--tools" in argv and argv[argv.index("--tools") + 1] == ""
assert all("The run completed" not in value for value in argv)
prompt = open(prompt_path).read()
assert "The run completed" in prompt
for forbidden in ("sk-abcdefghijklmnopqrstuvwxyz123456", "private.person@example.com",
                  "/Users/gillettes/Downloads/private/tail.txt", "raw tool output"):
    assert forbidden not in prompt, forbidden
assert "REDACTED-PATH" in prompt
con = sqlite3.connect(db); con.row_factory = sqlite3.Row
row = con.execute("SELECT outcome_json,method FROM session_outcomes WHERE session_id=? AND method='tier2'", (sid,)).fetchone()
assert row and row["method"] == "tier2"
card = json.loads(row["outcome_json"]); blob = json.dumps(card, sort_keys=True)
assert card["did"] == ["Analysis was completed."]
assert card["method"] == "tier2" and card["provenance"] == "inferred"
assert card["anchors"]["commits"] == ["1a2b3c4"]
assert card["open_work"] and all(item.get("trust") == "structured" for item in card["open_work"])
for forbidden in ("rm -rf", "invented-repo", "deadbeef",
                  "12345678-1234-4234-8234-123456789abc", "ER-999",
                  "Make deploy", "Terraform apply", "Kubectl", "./deploy.sh"):
    assert forbidden not in blob, forbidden
assert "commands" not in card and "repos" not in card and "commits" not in card
cache = con.execute("SELECT result_json FROM outcome_extraction_cache").fetchone()[0]
for forbidden in ("rm -rf", "invented-repo", "deadbeef",
                  "12345678-1234-4234-8234-123456789abc", "ER-999",
                  "Make deploy", "Terraform apply", "Kubectl", "./deploy.sh"):
    assert forbidden not in cache, forbidden
health = con.execute("SELECT calls,successes,input_tokens,output_tokens FROM outcome_extraction_health").fetchone()
assert tuple(health) == (1, 1, 120, 44), tuple(health)
assert os.stat(os.path.dirname(db)).st_mode & 0o777 == 0o700
marker=json.load(open(marker_path))
assert marker["schema"] == "mission-control/outcome-extractor-run/v1"
assert marker["status"] == "completed" and marker["calls"] == 1
assert os.stat(marker_path).st_mode & 0o777 == 0o600
con.close()
PY
then
  pass "fixed argv, privacy boundary, narrative-only output, and deterministic anchors"
else
  fail "successful extraction contract"
fi
run_extract > "$TIER2_TMP/cache.json" 2> "$TIER2_TMP/cache.err"
if [ "$(wc -l < "$STUB_CAPTURE" | tr -d ' ')" = 1 ] \
   && [ "$(q "SELECT cache_hits FROM outcome_extraction_health ORDER BY day DESC LIMIT 1")" -ge 1 ]; then
  pass "sanitized-tail cache prevents unchanged re-summarization"
else
  fail "content-hash cache"
fi

KILL_CAL="$TIER2_TMP/kill-calibration.json"
cat > "$KILL_CAL" <<'JSON'
{"schema":"mission-control/outcome-calibration/v1","model_calls":1,"observations":[{"provider":"claude","model":"claude-haiku-4-5-20251001","input_tokens":120,"output_tokens":44,"latency_ms":1,"status":"success"}],"recommended_caps":{"daily_call_cap":5,"daily_token_cap":50000}}
JSON
"$CG" extract-outcomes --apply-calibration "$KILL_CAL" --json >/dev/null
export MORNING_BRIEF_LLM=1
"$CG" extract-outcomes --set-enabled 0 --json >/dev/null
export MORNING_BRIEF_LLM_TESTING=0
KILL_CALLS_BEFORE="$(wc -l < "$STUB_CAPTURE" | tr -d ' ')"
run_extract > "$TIER2_TMP/persistent-disabled-run.json" 2> "$TIER2_TMP/persistent-disabled-run.err"
"$CG" export --out "$TIER2_TMP/tier2-disabled-export.json" --catchup-limit 0 >/dev/null
"$CG" extract-outcomes --set-enabled 1 --json >/dev/null
"$CG" export --out "$TIER2_TMP/tier2-enabled-export.json" --catchup-limit 0 >/dev/null
export MORNING_BRIEF_LLM_TESTING=1
if python3 - "$TIER2_TMP/tier2-disabled-export.json" \
  "$TIER2_TMP/tier2-enabled-export.json" "$SID3" "$STUB_CAPTURE" \
  "$KILL_CALLS_BEFORE" "$TIER2_TMP/persistent-disabled-run.json" <<'PY'
import json,sys
disabled,enabled=(json.load(open(path))["data"]["outcomes"] for path in sys.argv[1:3])
sid=sys.argv[3]
disabled_card=[row for row in disabled if row["session_id"] == sid][0]
enabled_card=[row for row in enabled if row["session_id"] == sid][0]
assert disabled_card["method"] == "tier1", disabled_card["method"]
assert enabled_card["method"] == "tier2", enabled_card["method"]
assert sum(1 for _ in open(sys.argv[4])) == int(sys.argv[5])
assert json.load(open(sys.argv[6]))["disabled_skips"] == 1
PY
then
  pass "persistent kill switch overrides ambient enable and restores Tier 1"
else
  fail "kill-switch export rollback"
fi
export MORNING_BRIEF_LLM=1

# Cached model text is re-screened under the current denylist and a rejection
# restores deterministic Tier 1 as the current observation.
export MISSION_CONTROL_EGRESS_DENYLIST="Analysis was completed"
run_extract > "$TIER2_TMP/cache-rejected.json" 2> "$TIER2_TMP/cache-rejected.err"
if [ "$(wc -l < "$STUB_CAPTURE" | tr -d ' ')" = 1 ] \
   && [ "$(q "SELECT COUNT(*) FROM outcome_extraction_cache")" = 0 ] \
   && [ "$(q "SELECT v.method FROM session_outcome_observations o JOIN session_outcomes v ON v.id=o.outcome_id WHERE o.session_id='$SID3' ORDER BY o.observation_id DESC LIMIT 1")" = tier1 ] \
   && [ "$(q "SELECT privacy_skips FROM outcome_extraction_health")" -ge 1 ]; then
  pass "cache reuse revalidates current privacy policy and restores Tier 1"
else
  fail "cache policy revalidation"
fi
unset MISSION_CONTROL_EGRESS_DENYLIST

if python3 - "$HERE" <<'PY'
import sys
sys.path.insert(0,sys.argv[1])
import outcome_extractor as module
for value in ("Make deploy to finish.", "Terraform apply will finish.",
              "Kubectl rollout restart now.", "Run ./deploy.sh now.",
              "The remaining artifact is at /Users/gillettes/Coding Projects/private.",
              "git push origin main", "python3 deploy.py", "npm run deploy",
              "curl https://example.invalid", "launchctl kickstart gui/501/job",
              "Updated inventedrepo successfully.",
              "Reviewed inventedrepo successfully.", "rm -f relative.txt",
              "bash deploy.sh", "sh cleanup.sh", "zsh run.zsh", "cp source dest",
              "mv old new", "chmod 600 file", "pytest tests/test_x.py",
              "Please execute the migration", "Click the deploy button", "Type yes",
              "Select deploy and confirm", "Worked in inventedrepo",
              "Would you run deploy now?", "You should execute deploy now",
              "Kindly execute deploy now", "echo secret", "cat private.txt",
              "tee output.txt", "sed -i change file", "awk program file",
              "find . -delete", "xargs rm", "dd if=a of=b", "tar -xf payload",
              "unzip payload", "openssl enc data", "jq . file",
              "Completed issue 99999", "Resolved ticket 12345",
              "Completed task ID 987654"):
    raw={"did":[value],"left_open":[],"needs_trevor":[],
         "confidence":0.5,"ambiguity":False}
    assert module._clean_result(raw) is None, value
valid=module._clean_result({"did":["implementation_completed"],
    "left_open":["review_remaining"],"needs_trevor":["review_evidence"],
    "confidence":0.7,"ambiguity":False})
assert valid["did"] == ["Implementation work was completed."]
for invalid in (
    {"did":["analysis_completed"],"left_open":[],"needs_trevor":[],
     "confidence":0.5,"ambiguity":False,"extra":"value"},
    {"did":["analysis_completed"],"left_open":"wrong","needs_trevor":[],
     "confidence":0.5,"ambiguity":False},
    {"did":["analysis_completed"],"left_open":[],"needs_trevor":[],
     "confidence":"0.5","ambiguity":False},
    {"did":["analysis_completed"],"left_open":[],"needs_trevor":[],
     "confidence":float("nan"),"ambiguity":False},
    {"did":["analysis_completed"],"did_codes":["work_verified"],
     "left_open":[],"needs_trevor":[],"confidence":0.5,"ambiguity":False},
):
    assert module._clean_result(invalid) is None, invalid
ambiguous=module._clean_result({"did":[],"left_open":[],
    "needs_trevor":["resolve_ambiguity"],"confidence":0.1,"ambiguity":True},
    allow_ambiguous_empty=True)
assert ambiguous is not None and ambiguous["ambiguity"] and not ambiguous["did"]
PY
then
  pass "fixed taxonomy and strict local schema exclude malformed model output"
else
  fail "fixed narrative taxonomy"
fi

# Identical sanitized text in two sessions is not a cross-session cache hit.
new_env
SID3S1="33333333-3333-4333-8333-333333333351"
SID3S2="33333333-3333-4333-8333-333333333352"
write_claude_source "$SID3S1" structured
write_claude_source "$SID3S2" structured
seed_high_value "$SID3S1"
seed_high_value "$SID3S2"
run_extract > "$TIER2_TMP/session-cache.json" 2> "$TIER2_TMP/session-cache.err"
if [ "$(wc -l < "$STUB_CAPTURE" | tr -d ' ')" = 2 ] \
   && [ "$(q "SELECT COUNT(*) FROM outcome_extraction_cache")" = 2 ]; then
  pass "cache identity is namespaced by source session"
else
  fail "cross-session cache isolation"
fi

# --limit bounds new model calls, not the cached prefix of the candidate list;
# repeated runs must advance through an initial backlog instead of starving it.
new_env
SID3A1="33333333-3333-4333-8333-333333333341"
SID3A2="33333333-3333-4333-8333-333333333342"
write_claude_source "$SID3A1" structured
write_claude_source "$SID3A2" structured
printf '%s\n' '{"id":"distinct","role":"assistant","type":"assistant","content":"A distinct bounded tail requires its own rewrite."}' >> \
  "$CHAT_GRAPH_CLAUDE_ROOT/project/$SID3A2.jsonl"
seed_high_value "$SID3A1"
seed_high_value "$SID3A2"
"$CG" extract-outcomes --days 7 --limit 1 --json > "$TIER2_TMP/backlog-1.json"
"$CG" extract-outcomes --days 7 --limit 1 --json > "$TIER2_TMP/backlog-2.json"
if [ "$(wc -l < "$STUB_CAPTURE" | tr -d ' ')" = 2 ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE method='tier2'")" = 2 ]; then
  pass "call limit advances past cached candidates on later runs"
else
  fail "call-limit cache starvation"
fi

# A failed newest candidate backs off, so the next run can spend its bounded
# call on older eligible work instead of retry-starving the queue.
new_env
SID3F1="33333333-3333-4333-8333-333333333361"
SID3F2="33333333-3333-4333-8333-333333333362"
write_claude_source "$SID3F1" structured
write_claude_source "$SID3F2" structured
printf '%s\n' '{"id":"newest","role":"assistant","type":"assistant","content":"NEWEST_MARKER has a bounded rewrite."}' >> \
  "$CHAT_GRAPH_CLAUDE_ROOT/project/$SID3F2.jsonl"
python3 - "$CHAT_GRAPH_CLAUDE_ROOT/project/$SID3F1.jsonl" \
  "$CHAT_GRAPH_CLAUDE_ROOT/project/$SID3F2.jsonl" <<'PY'
import os,sys,time
now=time.time()
os.utime(sys.argv[1],(now-10,now-10)); os.utime(sys.argv[2],(now,now))
PY
seed_high_value "$SID3F1"
seed_high_value "$SID3F2"
export STUB_BEHAVIOR=invalid
"$CG" extract-outcomes --days 7 --limit 1 --json > "$TIER2_TMP/failure-backoff-1.json"
export STUB_BEHAVIOR=success
"$CG" extract-outcomes --days 7 --limit 1 --json > "$TIER2_TMP/failure-backoff-2.json"
if python3 - "$STUB_CAPTURE" "$CHAT_GRAPH_HOME/graph.db" "$SID3F1" <<'PY'
import json,sqlite3,sys
rows=[json.loads(line) for line in open(sys.argv[1])]
assert [row["newest_marker"] for row in rows] == [True,False], rows
con=sqlite3.connect(sys.argv[2])
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id=? AND method='tier2'",(sys.argv[3],)).fetchone()[0] == 1
assert con.execute("SELECT COUNT(*) FROM outcome_extraction_attempts").fetchone()[0] == 1
PY
then
  pass "failed candidates back off without starving older eligible work"
else
  fail "failure backoff queue progression"
fi

# A changed extraction variant must create an immutable new Tier-2 version,
# not collide with the prior (session, tail, method) row.
new_env
SID3V="33333333-3333-4333-8333-333333333343"
write_claude_source "$SID3V" structured
seed_high_value "$SID3V"
run_extract > "$TIER2_TMP/variant-1.json" 2> "$TIER2_TMP/variant-1.err"
export MORNING_BRIEF_LLM_TEST_PROMPT_VERSION=4
export MORNING_BRIEF_LLM_MODEL="untrusted-model-override"
if run_extract > "$TIER2_TMP/variant-2.json" 2> "$TIER2_TMP/variant-2.err" \
   && [ "$(wc -l < "$STUB_CAPTURE" | tr -d ' ')" = 2 ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='$SID3V' AND method='tier2'")" = 2 ] \
   && python3 - "$STUB_CAPTURE" <<'PY'
import json,sys
rows=[json.loads(line) for line in open(sys.argv[1])]
models=[row["argv"][row["argv"].index("--model")+1] for row in rows]
assert models == ["claude-haiku-4-5-20251001","claude-haiku-4-5-20251001"], models
PY
then
  pass "pinned prompt variant changes preserve a new Tier-2 version"
else
  fail "Tier-2 extraction variant uniqueness"
fi

# Haiku escalates exactly once only when its structured result says ambiguous.
new_env
SID3B="33333333-3333-4333-8333-333333333334"
write_claude_source "$SID3B" structured
seed_high_value "$SID3B"
export STUB_BEHAVIOR=ambiguous
if run_extract > "$TIER2_TMP/ambiguous.json" 2> "$TIER2_TMP/ambiguous.err" \
   && python3 - "$STUB_CAPTURE" "$CHAT_GRAPH_HOME/graph.db" "$SID3B" <<'PY'
import json,sqlite3,sys
calls=[json.loads(line)["argv"] for line in open(sys.argv[1])]
models=[argv[argv.index("--model")+1] for argv in calls]
assert models == ["claude-haiku-4-5-20251001", "claude-sonnet-4-6"], models
con=sqlite3.connect(sys.argv[2])
card=json.loads(con.execute("SELECT outcome_json FROM session_outcomes WHERE session_id=? AND method='tier2'",(sys.argv[3],)).fetchone()[0])
assert card["did"] == ["The work was verified."]
assert card["model_metadata"]["model"] == "claude-sonnet-4-6"
health=con.execute("SELECT calls,escalations,successes FROM outcome_extraction_health").fetchone()
assert health == (2,1,1), health
PY
then
  pass "explicit ambiguity alone escalates Haiku once to pinned Sonnet"
else
  fail "ambiguity escalation contract"
fi

# If the stronger rewrite is still ambiguous, fail open to the existing Tier 1
# card; an unresolved inference is not an llm_success outcome.
new_env
SID3D="33333333-3333-4333-8333-333333333336"
write_claude_source "$SID3D" structured
seed_high_value "$SID3D"
export STUB_BEHAVIOR=ambiguous_always
if run_extract > "$TIER2_TMP/ambiguous-always.json" 2> "$TIER2_TMP/ambiguous-always.err" \
   && [ "$(wc -l < "$STUB_CAPTURE" | tr -d ' ')" = 2 ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='$SID3D' AND method='tier2'")" = 0 ] \
   && [ "$(q "SELECT failures FROM outcome_extraction_health")" -ge 1 ] \
   && [ "$(q "SELECT successes FROM outcome_extraction_health")" = 0 ]; then
  pass "ambiguity remaining after Sonnet fails open to Tier 1"
else
  fail "unresolved ambiguity fail-open"
fi

# A deliberately invoked provider sample is hard-bounded, records only
# content-free calibration evidence, and applies private observed caps without
# putting transcript text or secrets into launchd.
new_env
SID3C="33333333-3333-4333-8333-333333333335"
write_claude_source "$SID3C" structured
seed_high_value "$SID3C"
export MISSION_CONTROL_HOME="$TIER2_TMP/mission-control"
unset MORNING_BRIEF_LLM_DAILY_CALL_CAP MORNING_BRIEF_LLM_DAILY_TOKEN_CAP
CALIBRATION="$TIER2_TMP/calibration.json"
if "$CG" extract-outcomes --days 7 --limit 20 --sample-per-provider 1 \
     --calibration-out "$CALIBRATION" --json > "$TIER2_TMP/sample.json" \
     2> "$TIER2_TMP/sample.err" \
   && "$CG" extract-outcomes --apply-calibration "$CALIBRATION" --json \
     > "$TIER2_TMP/apply.json" 2> "$TIER2_TMP/apply.err" \
   && "$CG" extract-outcomes --set-enabled 0 --json > "$TIER2_TMP/disable.json" \
     2> "$TIER2_TMP/disable.err" \
   && "$CG" extract-outcomes --set-enabled 1 --json > "$TIER2_TMP/enable.json" \
     2> "$TIER2_TMP/enable.err" \
   && python3 - "$CALIBRATION" "$MISSION_CONTROL_HOME/outcome-extractor/config.json" \
     "$TIER2_TMP/disable.json" "$TIER2_TMP/enable.json" <<'PY'
import json,os,stat,sys
sample=json.load(open(sys.argv[1])); config=json.load(open(sys.argv[2]))
disabled=json.load(open(sys.argv[3])); enabled=json.load(open(sys.argv[4]))
assert sample["schema"] == "mission-control/outcome-calibration/v1"
assert sample["model_calls"] == 1 and len(sample["observations"]) == 1
row=sample["observations"][0]
assert set(row) == {"provider","model","input_tokens","output_tokens","latency_ms","status"}
assert row["provider"] == "claude" and row["status"] == "success"
assert sample["recommended_caps"]["daily_call_cap"] >= 1
assert sample["recommended_caps"]["daily_token_cap"] >= row["input_tokens"]+row["output_tokens"]
assert config["schema"] == "mission-control/outcome-extractor-config/v1"
assert config["daily_call_cap"] == sample["recommended_caps"]["daily_call_cap"]
assert config["daily_token_cap"] == sample["recommended_caps"]["daily_token_cap"]
assert config["enabled"] is True
assert disabled["enabled"] is False and enabled["enabled"] is True
assert config["providers"]["claude"] is True
assert all(config["providers"][name] is False for name in ("codex","cursor","hermes","copilot"))
assert stat.S_IMODE(os.stat(sys.argv[2]).st_mode) == 0o600
assert stat.S_IMODE(os.stat(os.path.dirname(sys.argv[2])).st_mode) == 0o700
blob=json.dumps(sample)+json.dumps(config)
for forbidden in ("The run completed","private.person@example.com",
                  "sk-abcdefghijklmnopqrstuvwxyz123456","/Users/gillettes/Downloads"):
    assert forbidden not in blob
PY
then
  pass "bounded sample records observed calibration and applies private caps"
else
  fail "bounded sample and calibration application"
fi

# Sampling may bootstrap missing calibration, but it may never override an
# explicit persistent off setting.
new_env
SID3E="33333333-3333-4333-8333-333333333337"
write_claude_source "$SID3E" structured
seed_high_value "$SID3E"
"$CG" extract-outcomes --set-enabled 0 --json >/dev/null
if "$CG" extract-outcomes --days 7 --limit 20 --sample-per-provider 1 \
     --calibration-out "$TIER2_TMP/off-sample-calibration.json" --json \
     > "$TIER2_TMP/off-sample.json" 2> "$TIER2_TMP/off-sample.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && python3 - "$TIER2_TMP/off-sample.json" <<'PY'
import json,sys
row=json.load(open(sys.argv[1]))
assert row["calls"] == 0 and row["disabled_skips"] == 1
PY
then
  pass "persistent off blocks an explicit provider sample"
else
  fail "persistent off versus sample bypass"
fi

# A sample may bootstrap a missing config, but a present malformed/future or
# unsafe config is a fault, never an authorization to call the real wrapper.
new_env
SID3H="33333333-3333-4333-8333-333333333339"
write_claude_source "$SID3H" structured
seed_high_value "$SID3H"
mkdir -p "$MISSION_CONTROL_HOME/outcome-extractor"
printf '%s\n' '{malformed' > "$MISSION_CONTROL_HOME/outcome-extractor/config.json"
if "$CG" extract-outcomes --days 7 --limit 20 --sample-per-provider 1 \
     --calibration-out "$TIER2_TMP/bad-sample-calibration.json" --json \
     > "$TIER2_TMP/bad-sample.json" 2> "$TIER2_TMP/bad-sample.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && python3 - "$TIER2_TMP/bad-sample.json" <<'PY'
import json,sys
row=json.load(open(sys.argv[1]))
assert row["calls"]==0 and row["uncalibrated_skips"]==1
PY
then
  pass "present malformed config blocks an explicit provider sample"
else
  fail "malformed config sample bypass"
fi

if python3 - "$HERE" "$MISSION_CONTROL_HOME/outcome-extractor/config.json" <<'PY'
import json,os,sys
sys.path.insert(0,sys.argv[1])
import outcome_extractor as module
path=sys.argv[2]
providers={name:True for name in ("claude","codex","cursor","hermes","copilot")}
variants=(
 {"schema":"future/v2","enabled":True,"daily_call_cap":5,
  "daily_token_cap":50000,"providers":providers},
 {"schema":"mission-control/outcome-extractor-config/v1","enabled":"0",
  "daily_call_cap":5,"daily_token_cap":50000,"providers":providers},
 {"schema":"mission-control/outcome-extractor-config/v1","enabled":True,
  "daily_call_cap":10**12,"daily_token_cap":50000,"providers":providers},
 {"schema":"mission-control/outcome-extractor-config/v1","enabled":True,
  "daily_call_cap":5,"daily_token_cap":50000,"providers":{"claude":True}},
)
for value in variants:
    json.dump(value,open(path,"w"))
    os.environ["MORNING_BRIEF_LLM"]="1"
    assert module._bypass_config_state()=="uncalibrated",value
    assert os.environ["MORNING_BRIEF_LLM"]=="0"
PY
then
  pass "sample/test bypass rejects future and unsafe present configs"
else
  fail "sample/test strict present-config validation"
fi

# Synthetic testing must name an executable stub; absence can never fall back
# to the real installed wrapper.
new_env
SID3G="33333333-3333-4333-8333-333333333338"
write_claude_source "$SID3G" structured
seed_high_value "$SID3G"
unset MORNING_BRIEF_LLM_CMD
if run_extract > "$TIER2_TMP/no-test-stub.json" 2> "$TIER2_TMP/no-test-stub.err" \
   && [ ! -e "$STUB_CAPTURE" ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='$SID3G' AND method='tier2'")" = 0 ]; then
  pass "testing mode without an explicit stub fails closed"
else
  fail "testing mode real-wrapper fallback"
fi

# OAuth lock contention is a benign defer and invalid output fails open.
new_env
SID4="44444444-4444-4444-8444-444444444444"
write_claude_source "$SID4" unstructured
seed_high_value "$SID4"
export STUB_BEHAVIOR=defer
if run_extract > "$TIER2_TMP/defer.json" 2> "$TIER2_TMP/defer.err" \
   && [ "$(q "SELECT deferred FROM outcome_extraction_health ORDER BY day DESC LIMIT 1")" -ge 1 ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='$SID4' AND method='tier2'")" = 0 ]; then
  pass "OAuth exit 75 defers without replacing Tier 1"
else
  fail "OAuth lock defer"
fi

new_env
SID4B="44444444-4444-4444-8444-444444444445"
write_claude_source "$SID4B" unstructured
seed_high_value "$SID4B"
export MORNING_BRIEF_LLM_TIMEOUT=6
export STUB_BEHAVIOR=defer_slow
START_DEFER="$(python3 -c 'import time; print(time.monotonic())')"
run_extract > "$TIER2_TMP/defer-slow.json" 2> "$TIER2_TMP/defer-slow.err"
END_DEFER="$(python3 -c 'import time; print(time.monotonic())')"
if python3 - "$START_DEFER" "$END_DEFER" "$STUB_CAPTURE" \
  "$CHAT_GRAPH_HOME/graph.db" "$SID4B" <<'PY'
import json,sqlite3,sys
assert float(sys.argv[2])-float(sys.argv[1]) < 5
call=json.loads(open(sys.argv[3]).readline())
assert 1 <= call["oauth_timeout"] < 6
con=sqlite3.connect(sys.argv[4])
assert con.execute("SELECT deferred FROM outcome_extraction_health").fetchone()[0] >= 1
assert con.execute("SELECT COUNT(*) FROM session_outcomes WHERE session_id=? AND method='tier2'",(sys.argv[5],)).fetchone()[0] == 0
PY
then
  pass "OAuth wrapper defers before the extractor timeout"
else
  fail "OAuth wrapper versus extractor timeout ordering"
fi

new_env
SID5="55555555-5555-4555-8555-555555555555"
write_claude_source "$SID5" unstructured
seed_high_value "$SID5"
export STUB_BEHAVIOR=invalid
if run_extract > "$TIER2_TMP/invalid.json" 2> "$TIER2_TMP/invalid.err" \
   && [ "$(q "SELECT failures FROM outcome_extraction_health ORDER BY day DESC LIMIT 1")" -ge 1 ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='$SID5' AND method='tier2'")" = 0 ]; then
  pass "invalid model output fails open with a health counter"
else
  fail "invalid-output fail-open"
fi

new_env
SID5B="55555555-5555-4555-8555-555555555556"
write_claude_source "$SID5B" unstructured
seed_high_value "$SID5B"
export STUB_BEHAVIOR=oversized
if run_extract > "$TIER2_TMP/oversized.json" 2> "$TIER2_TMP/oversized.err" \
   && [ "$(q "SELECT failures FROM outcome_extraction_health")" -ge 1 ] \
   && [ "$(q "SELECT COUNT(*) FROM outcome_extraction_cache")" = 0 ] \
   && [ "$(q "SELECT COUNT(*) FROM session_outcomes WHERE session_id='$SID5B' AND method='tier2'")" = 0 ] \
   && ! rg -q 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX' "$CHAT_GRAPH_HOME" "$MISSION_CONTROL_HOME"; then
  pass "oversized model output is bounded and never persisted"
else
  fail "oversized output bound"
fi

# If a transcript changes after the last collector ingest, the extractor must
# persist that exact current Tier 1 tail before a failed enrichment so stale
# inferred prose cannot remain the latest observation.
new_env
SID5C="55555555-5555-4555-8555-555555555557"
write_claude_source "$SID5C" structured
seed_high_value "$SID5C"
run_extract > "$TIER2_TMP/race-old-success.json" 2> "$TIER2_TMP/race-old-success.err"
cat >> "$CHAT_GRAPH_CLAUDE_ROOT/project/$SID5C.jsonl" <<'JSONL'
{"id":"current-closeout","role":"assistant","type":"assistant","content":"Re: current fallback\n\nAnswer\nThe current deterministic state is different.\n\nDone\n- Current deterministic fallback replaced the older tail.\n\nNext\n- Review current fallback evidence."}
JSONL
export STUB_BEHAVIOR=invalid
run_extract > "$TIER2_TMP/race-current-failure.json" 2> "$TIER2_TMP/race-current-failure.err"
if python3 - "$CHAT_GRAPH_HOME/graph.db" "$SID5C" <<'PY'
import json,sqlite3,sys
con=sqlite3.connect(sys.argv[1]); con.row_factory=sqlite3.Row
rows=con.execute("SELECT method,outcome_json FROM session_outcomes WHERE session_id=? ORDER BY rowid",(sys.argv[2],)).fetchall()
assert sum(row["method"]=="tier1" for row in rows) == 2, [(r["method"],json.loads(r["outcome_json"])["tail_hash"]) for r in rows]
assert sum(row["method"]=="tier2" for row in rows) == 1, [r["method"] for r in rows]
latest=con.execute("""SELECT v.method,v.outcome_json FROM session_outcome_observations o
JOIN session_outcomes v ON v.id=o.outcome_id WHERE o.session_id=?
ORDER BY o.observation_id DESC LIMIT 1""",(sys.argv[2],)).fetchone()
assert latest["method"] == "tier1", latest["method"]
latest_card=json.loads(latest["outcome_json"])
tier2_card=json.loads([row["outcome_json"] for row in rows if row["method"]=="tier2"][0])
assert latest_card["tail_hash"] != tier2_card["tail_hash"]
PY
then
  pass "changed source plus Tier 2 failure makes exact current Tier 1 latest"
else
  fail "exact-tail Tier 1 failure fallback"
fi

# The extractor's own lock and model latency cannot hold the collector DB lock.
new_env
SID6="66666666-6666-4666-8666-666666666666"
write_claude_source "$SID6" structured
seed_high_value "$SID6"
export STUB_BEHAVIOR=slow
run_extract > "$TIER2_TMP/slow.json" 2> "$TIER2_TMP/slow.err" & EXTRACT_PID=$!
i=0
while [ ! -e "$STUB_STARTED" ] && [ "$i" -lt 80 ]; do sleep 0.05; i=$((i + 1)); done
START="$(python3 -c 'import time; print(time.monotonic())')"
"$CG" ingest >/dev/null 2>&1
END="$(python3 -c 'import time; print(time.monotonic())')"
wait "$EXTRACT_PID"; EXTRACT_RC=$?
if python3 - "$START" "$END" "$EXTRACT_RC" <<'PY'
import sys
start, end, rc = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
assert rc == 0
assert end - start < 1.75, end - start
PY
then
  pass "slow model call does not hold the ingest transaction"
else
  fail "slow-model versus ingest concurrency"
fi

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
