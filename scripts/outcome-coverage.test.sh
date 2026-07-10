#!/usr/bin/env bash
# outcome-coverage.test.sh — zero-call seven-day Tier 1 coverage contract.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OC="$HERE/outcome-coverage"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/claude/project" "$TMP/codex/sessions/2026/07/09" \
         "$TMP/cursor" "$TMP/hermes" "$TMP/copilot"

python3 - "$REPO/tests/fixtures/outcomes" "$TMP" <<'PY'
import json, os, sys, time
fixtures, root = sys.argv[1:]
placements = {
    "reply-v5.json": ("claude/project/reply-v5.jsonl", "claude"),
    "codex-closeout.json": ("codex/sessions/2026/07/09/rollout-codex.jsonl", "codex"),
    "audit-report.json": ("claude/project/audit.jsonl", "claude"),
    "handoff-packet.json": ("claude/project/handoff.jsonl", "claude"),
    "unstructured-tail.json": ("cursor/unstructured.jsonl", "cursor"),
}
for name, (rel, provider) in placements.items():
    fixture = json.load(open(os.path.join(fixtures, name)))
    path = os.path.join(root, rel)
    with open(path, "w") as out:
        for i, msg in enumerate(fixture["messages"]):
            out.write(json.dumps({"id": "%s-%d" % (name, i), "role": msg["role"],
                                  "type": msg["role"], "content": msg["content"]}) + "\n")
# An old otherwise-eligible file must not enter the seven-day plan.
old = os.path.join(root, "copilot", "old.jsonl")
with open(old, "w") as out:
    out.write(json.dumps({"role":"assistant", "content":"Outcome\nOld work\nStatus: complete"}) + "\n")
past = time.time() - 9 * 86400
os.utime(old, (past, past))
# A recent user-only transcript is counted for provider coverage but is not a
# model-eligible unparseable assistant tail.
with open(os.path.join(root, "copilot", "user-only.jsonl"), "w") as out:
    out.write(json.dumps({"role":"user", "content":"please inspect this"}) + "\n")
for dirname in ("session-a", "session-b"):
    directory = os.path.join(root, "copilot", dirname)
    os.makedirs(directory)
    with open(os.path.join(directory, "events.jsonl"), "w") as out:
        if dirname == "session-a":
            out.write(json.dumps({"type":"assistant.message", "data":{"content":
                "Outcome\nNative Copilot event parsed.\nStatus: complete"}}) + "\n")
        else:
            out.write(json.dumps({"type":"user.message", "data":{"content":
                "same basename, distinct session"}}) + "\n")
# A newer Claude subagent path includes the parent UUID but must not replace it.
parent="77777777-7777-4777-8777-777777777777"
with open(os.path.join(root,"claude","project",parent+".jsonl"),"w") as out:
    out.write(json.dumps({"id":"parent","role":"assistant","content":
        "Outcome\nCanonical parent closeout.\nStatus: complete"})+"\n")
child_dir=os.path.join(root,"claude","project",parent,"subagents")
os.makedirs(child_dir)
child=os.path.join(child_dir,"agent-child.jsonl")
with open(child,"w") as out:
    out.write(json.dumps({"id":"child","role":"assistant","content":"unstructured child"})+"\n")
future=time.time()+10; os.utime(child,(future,future))
PY
python3 - "$TMP/hermes-state.db" <<'PY'
import sqlite3,time,sys
c=sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE sessions(id TEXT PRIMARY KEY,title TEXT,cwd TEXT,started_at REAL)")
c.execute("""CREATE TABLE messages(id INTEGER PRIMARY KEY,session_id TEXT,role TEXT,
 content TEXT,timestamp REAL,active INTEGER)""")
c.execute("INSERT INTO sessions VALUES(?,?,?,?)",("hermes-one","Fixture","/tmp",time.time()))
c.execute("INSERT INTO messages VALUES(?,?,?,?,?,1)",(1,"hermes-one","assistant",
 "plain unstructured Hermes tail",time.time()))
c.commit()
PY

# A tempting model command is a negative control: plan mode must never execute it.
export OUTCOME_COVERAGE_MODEL_CMD="touch $TMP/MODEL_CALLED"
export OUTCOME_COVERAGE_CLAUDE_ROOT="$TMP/claude"
export OUTCOME_COVERAGE_CODEX_ROOT="$TMP/codex"
export OUTCOME_COVERAGE_CURSOR_ROOT="$TMP/cursor"
export OUTCOME_COVERAGE_HERMES_ROOT="$TMP/hermes"
export OUTCOME_COVERAGE_HERMES_DB="$TMP/hermes-state.db"
export OUTCOME_COVERAGE_COPILOT_ROOT="$TMP/copilot"

if "$OC" --days 7 --json > "$TMP/report.json" 2> "$TMP/stderr"; then
  pass "coverage command exits zero"
else
  fail "coverage command exits zero ($(tr '\n' ' ' < "$TMP/stderr"))"
fi

if [ ! -e "$TMP/MODEL_CALLED" ]; then pass "plan mode makes zero model calls"
else fail "plan mode executed OUTCOME_COVERAGE_MODEL_CMD"; fi

if python3 - "$TMP/report.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == 1 and d["mode"] == "plan"
assert d["window_days"] == 7 and d["model_calls_made"] == 0
assert d["providers"]["claude"]["sessions"] == 4
assert d["providers"]["claude"]["structured"] == 4
assert d["providers"]["codex"]["sessions"] == 1
assert d["providers"]["cursor"]["sessions"] == 1
assert d["providers"]["hermes"]["sessions"] == 1
assert d["providers"]["copilot"]["sessions"] == 3
assert d["providers"]["copilot"]["no_assistant_tail"] == 2
assert d["providers"]["copilot"]["structured"] == 1
assert d["grammar_counts"]["reply_v5"] == 1
assert d["grammar_counts"]["codex_closeout"] >= 2
assert d["grammar_counts"]["audit_report"] == 1
assert d["grammar_counts"]["handoff_packet"] == 1
assert d["packet_tails"] == 1
assert d["unparseable_sessions"] == 2
assert d["eligible_model_calls"] == 2
assert d["no_assistant_tail_sessions"] == 2
assert d["tail_bytes"] > 0
assert d["projection"]["basis"] == "modeled"
assert d["projection"]["charged_api_dollars"] is None
assert d["projection"]["eligible_calls_window"] == 2
assert 0 < d["projection"]["input_tokens_day"] < d["projection"]["input_tokens_window"]
assert d["projection"]["output_tokens_window"] == 512
assert d["projection"]["output_tokens_day"] == round(512 / 7.0, 3)
assert d["projection"]["calls_day"] == round(2 / 7.0, 3)
assert d["source_status"]["hermes"]["storage"] == "state.db"
assert "modeled_call_headroom" in d["quota"]
PY
then pass "coverage reports provider/grammar/packet/unparseable and modeled load"
else fail "coverage report contract"; fi

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
