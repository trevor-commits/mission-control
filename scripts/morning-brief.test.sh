#!/bin/bash
# Deterministic Morning Brief acceptance suite. Synthetic fixtures only.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIEF="$ROOT/scripts/morning-brief"
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export MISSION_CONTROL_HOME="$TMP/state"
export MORNING_BRIEF_NOW_EPOCH=1783674000
mkdir -p "$MISSION_CONTROL_HOME/data"

python3 - "$MISSION_CONTROL_HOME/data" <<'PY'
import json, os, sys
root = sys.argv[1]; now = 1783674000
def write(name, data, cadence=1800, age=0, ok=True):
    value = {"schema": 1, "feed": name, "generated_at": "2026-07-10T09:00:00Z",
             "generated_epoch": now-age, "cadence_s": cadence, "ok": ok,
             "error": None if ok else "synthetic failure", "data": data}
    with open(os.path.join(root, name + ".json"), "w") as f: json.dump(value, f)
write("automation", {"jobs": [
    {"name": "Broken Job", "label": "com.example.broken", "state": "red",
     "run_cmd": "launchctl kickstart -k gui/501/com.example.broken",
     "failure_streak": 2, "history_confidence": "trusted"},
    {"name": "Healthy Job", "state": "green", "failure_streak": 0}],
    "counts": {"red": 1, "green": 1}}, cadence=300)
write("usage", {"providers": [
    {"provider": "codex", "window": "5h", "used_pct": 62.0, "confidence": "live"},
    {"provider": "claude", "window": "weekly", "used_pct": 34.0, "confidence": "estimated"}
]}, cadence=604800, age=6*86400)
write("decisions", {"pinned": [
    {"id": "decision:" + "1"*24, "text": "Choose the rollout window",
     "trust": "structured", "provenance": "chat-graph tier1"}],
    "inferred": [], "counts": {"structured_open": 1}}, cadence=300)
write("git", {"repos": [
    {"repo": "mission-control", "path": "/Users/gillettes/Coding Projects/mission-control",
     "branch": "codex/morning-brief", "remote": "ahead", "dirty": False,
     "dirty_files": 0, "ahead": 1, "behind": 0, "detached": False,
     "last_commit": {"sha": "a"*40, "subject": "feat: add morning brief", "epoch": now-60},
     "recent_commits": [
       {"sha": "a"*40, "subject": "feat: add morning brief", "epoch": now-60},
       {"sha": "b"*40, "subject": "test: cover equal timestamps", "epoch": now-120}
     ], "branches": []}
]}, cadence=900)
changes = [
    {"id": "chat-1:item-a", "stable_id": "chat-1:item-a", "source_id": "chat-1",
     "source_node": "codex:chat-1", "kind": "chat_open_end", "item_key": "item-a",
     "text": "Review the release evidence", "change_type": "new", "updated_at": now-20,
     "resolved_at": None, "resolution_evidence_type": None, "resolution_evidence_ref": None},
    {"id": "chat-1:item-b", "stable_id": "chat-1:item-b", "source_id": "chat-1",
     "source_node": "codex:chat-1", "kind": "chat_open_end", "item_key": "item-b",
     "text": "Old decision was answered", "change_type": "resolved", "updated_at": now-20,
     "resolved_at": now-20, "resolution_evidence_type": "manual", "resolution_evidence_ref": "journal"}
]
changes.append({"id": "unsafe", "stable_id": "operator@example.com", "source_id": "chat-unsafe",
 "source_node": "codex:chat-unsafe", "kind": "chat_open_end", "item_key": "unsafe",
 "text": "This item must fail closed", "change_type": "new", "updated_at": now-10,
 "resolved_at": None, "resolution_evidence_type": None, "resolution_evidence_ref": None})
write("chats", {"nodes": [], "edges": [], "topics": [], "counts": {},
     "outcomes": [
       {"card_id": "c"*40, "session_id": "chat-outcome", "provider": "codex",
        "method": "tier1", "updated_at": now-30,
        "did": ["Implemented the verified outcome"],
        "anchors": {"commits": ["c"*40], "commands": [], "ids": []}}
     ],
     "outcome_updates": [
       {"id": "late-1", "provider": "claude", "method": "tier1",
        "change_type": "late_update", "updated_at": now-25}
     ],
     "loose_end_changes": changes,
     "loose_ends": [
       {"id": "repo:alpha:item-aging", "kind": "todo_open", "source_node": "repo:alpha",
        "title": "Repo: alpha", "repo": "alpha", "text": "Old unchecked task",
        "text_hash": "aging-hash", "item_key": "item-aging", "first_seen_at": now-9*86400,
        "updated_at": now-9*86400, "action_hint": "check it", "age_days": 9,
        "severity": "amber", "resolve_cmd": "chat-graph resolve repo:alpha aging-hash"}
     ]}, cadence=1800)
PY

if [ ! -x "$BRIEF" ]; then
  fail "morning-brief executable exists"
else
  "$BRIEF" >/dev/null 2>&1 || fail "compose exits zero"
fi

LATEST="$MISSION_CONTROL_HOME/morning-brief/latest.json"
MARKDOWN="$MISSION_CONTROL_HOME/morning-brief/latest.md"
if [ -s "$LATEST" ] && [ -s "$MARKDOWN" ]; then pass "compose writes Markdown and sidecar"
else fail "compose writes Markdown and sidecar"; fi

if [ -s "$LATEST" ] && python3 - "$LATEST" "$MARKDOWN" <<'PY'
import json, os, sys
d=json.load(open(sys.argv[1])); md=open(sys.argv[2]).read()
assert d["schema"] == 1 and d["brief_id"]
assert len(d["markdown_sha256"]) == 64
assert d["delivery"]["state"] == "not_sent"
assert d["selection_high_water"]["loose_end_changes"] == [1783673980, "chat-1:item-b"]
assert "operator@example.com" not in json.dumps(d)
assert d["egress_counters"]["compose"]["dropped_fields"] >= 1
assert d["egress_counters"]["compose"]["reason_email"] >= 1
assert set(d["inputs"]) == {"automation", "usage", "git", "chats", "decisions"}
assert d["inputs"]["usage"]["state"] == "fresh", d["inputs"]["usage"]
assert not d["stale_required_inputs"]
expected=["NEEDS YOU", "What happened", "Open work changes", "Machinery health", "Usage headroom"]
assert [s["title"] for s in d["sections"]] == expected
assert md.index("## NEEDS YOU") < md.index("## What happened") < md.index("## Open work changes")
assert "Confirmed" in md and "Inferred" not in d["sections"][0]["lines"][0]["trust"]
assert d["sections"][0]["lines"][0]["text"] == "Choose the rollout window"
assert d["sections"][0]["lines"][0]["action_cmd"].startswith("dashboard decide dismiss decision:")
assert "Implemented the verified outcome" in md and "A session outcome received a late closeout update" in md
assert "commit cccccccccccc" in md
assert "aaaaaaaa" in md and "feat: add morning brief" in md
assert "Review the release evidence" in md and "Old decision was answered" in md
assert "Old unchecked task" in md and "Aging" in md
assert not list(os.path.dirname(sys.argv[1]) for _ in [] )
PY
then pass "sidecar preserves order, freshness, equal-timestamp cursor, Git and open deltas"
else fail "sidecar preserves order, freshness, equal-timestamp cursor, Git and open deltas"; fi

if find "$MISSION_CONTROL_HOME/morning-brief" -name '*.tmp.*' -print | grep -q .; then
  fail "atomic compose leaves no temp files"
else pass "atomic compose leaves no temp files"; fi

rm -f "$MISSION_CONTROL_HOME/morning-brief/delivery-cursor.json"
PRINTED="$TMP/printed.md"
if "$BRIEF" --print > "$PRINTED" 2>/dev/null && [ ! -e "$MISSION_CONTROL_HOME/morning-brief/delivery-cursor.json" ]; then
  pass "preview prints without advancing delivery cursor"
else fail "preview prints without advancing delivery cursor"; fi
if REPO_ROOT="$ROOT" "$ROOT/scripts/dashboard" brief --print | grep -q "## NEEDS YOU"; then
  pass "dashboard brief --print routes to deterministic preview"
else fail "dashboard brief --print routes to deterministic preview"; fi

# The composer snapshots inputs before a test hook mutates the source. The late
# event must not leak into that compose, but it must appear on the next compose.
HOOK="$TMP/add-late-event"
cat > "$HOOK" <<'SH'
#!/bin/bash
python3 - "$MISSION_CONTROL_HOME/data/chats.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["data"]["loose_end_changes"].append({
 "id":"chat-2:item-late","stable_id":"chat-2:item-late","source_id":"chat-2",
 "source_node":"claude:chat-2","kind":"chat_open_end","item_key":"item-late",
 "text":"Arrived during compose","change_type":"new","updated_at":1783673990,
 "resolved_at":None,"resolution_evidence_type":None,"resolution_evidence_ref":None})
json.dump(d, open(p,"w"))
PY
SH
chmod +x "$HOOK"
MORNING_BRIEF_TEST_AFTER_SNAPSHOT_HOOK="$HOOK" "$BRIEF" >/dev/null 2>&1
if grep -q "Arrived during compose" "$MARKDOWN"; then fail "event arriving after snapshot leaked into compose"
else pass "event arriving after snapshot is deferred"; fi
"$BRIEF" >/dev/null 2>&1
if grep -q "Arrived during compose" "$MARKDOWN"; then pass "next compose includes deferred event"
else fail "next compose includes deferred event"; fi

# A missing required feed creates a top-level warning; volume remains bounded.
rm -f "$MISSION_CONTROL_HOME/data/git.json"
MORNING_BRIEF_TOP_N=1 MORNING_BRIEF_NEEDS_YOU_MAX=1 "$BRIEF" >/dev/null 2>&1
if python3 - "$LATEST" <<'PY'
import json, sys
d=json.load(open(sys.argv[1])); sections={s["title"]:s for s in d["sections"]}
assert "git" in d["stale_required_inputs"]
assert len(sections["NEEDS YOU"]["lines"]) == 1
assert sections["Open work changes"]["collapsed_count"] >= 1
PY
then pass "missing required input warns and configurable caps collapse volume"
else fail "missing required input warns and configurable caps collapse volume"; fi

printf '%s\n' "----"
if [ "$FAIL" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$FAIL FAILED"; exit 1
