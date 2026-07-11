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
     "trust": "structured", "provenance": "chat-graph tier1"},
    {"id": "decision:" + "3"*24,
     "text": "DECISION NEEDED: Which rollout path? " + "| Option | Meaning " * 12,
     "trust": "structured", "provenance": "chat-graph tier1"}],
    "inferred": [
      {"id":"decision:"+"2"*24,"text":"Trevor needs to review the evidence.",
       "trust":"inferred","state":"open","provenance":"chat-graph tier2"}],
    "counts": {"structured_open": 1,"inferred":1}}, cadence=300)
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
write("chats", {"nodes": [
       {"id":"chat-outcome","provider":"codex","title":"Morning Brief implementation",
        "repo":"mission-control"},
       {"id":"chat-audit","provider":"claude","title":"Audit: OAuth handling",
        "repo":"global-implementations"}],
     "edges": [
       {"src":"claude:chat-audit","dst":"codex:chat-outcome","type":"audits",
        "source":"titles","confidence":0.7}],
     "topics": [], "counts": {},
     "outcome_extraction_health": {"day":"2026-07-09","successes":2,
       "cache_hits":3,"deferred":1,"failures":0,"budget_skips":1,
       "uncalibrated_skips":1,"disabled_skips":6,"provider_skips":2,"privacy_skips":3,
       "lock_skips":4,"backoff_skips":5,"escalations":1,"last_status":"budget_skip"},
     "outcomes": [
       {"card_id": "c"*40, "session_id": "chat-outcome", "provider": "codex",
        "method": "tier1", "updated_at": now-30,
        "session_title":"Morning Brief implementation","repo":"mission-control",
        "did": ["Implemented the verified outcome"],
        "anchors": {"commits": ["c"*40], "commands": [], "ids": []}},
       {"card_id":"d"*40,"session_id":"chat-audit","provider":"claude",
        "method":"tier2","updated_at":now-29,
        "session_title":"Audit: OAuth handling","repo":"global-implementations",
        "did":["An audit was completed."],"left_open":["Review remains open."],
        "anchors":{"commits":[],"commands":[],"ids":[]}}
     ],
     "outcome_updates": [
       {"id": "late-1", "provider": "claude", "method": "tier1",
        "session_id":"chat-audit","change_type": "late_update", "updated_at": now-25},
       {"id":"late-2","provider":"codex","method":"tier1",
        "session_id":"chat-outcome","change_type":"late_update","updated_at":now-24}
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
expected=["NEEDS YOU", "What happened", "Possible follow-ups — Inferred",
          "Open work changes", "Machinery health", "Usage headroom"]
assert [s["title"] for s in d["sections"]] == expected
assert md.index("## NEEDS YOU") < md.index("## What happened") < md.index("## Open work changes")
assert "Confirmed" in md and "Inferred" not in d["sections"][0]["lines"][0]["trust"]
assert d["sections"][0]["lines"][0]["text"] == "Choose the rollout window"
assert d["sections"][0]["lines"][0]["action_cmd"].startswith("dashboard decide dismiss decision:")
needs=next(s for s in d["sections"] if s["title"]=="NEEDS YOU")
possible=next(s for s in d["sections"] if s["title"]=="Possible follow-ups — Inferred")
# NEEDS YOU headlines fit one phone screen: no pipes, bounded length, and an
# over-length decision is clipped with a marker pointing to the full body.
assert all("|" not in row["text"] for row in needs["lines"]), needs["lines"]
assert all(len(row["text"]) <= 200 for row in needs["lines"]), needs["lines"]
long_line=next(r for r in needs["lines"] if r["text"].startswith("DECISION NEEDED: Which rollout path?"))
assert long_line["text"].endswith("(options in dashboard)"), long_line["text"]
short_line=next(r for r in needs["lines"] if r["text"]=="Choose the rollout window")
assert "options in dashboard" not in short_line["text"]
assert all("Trevor needs to review the evidence" not in row["text"] for row in needs["lines"])
assert any("Trevor needs to review the evidence" in row["text"] for row in possible["lines"])
assert "Morning Brief implementation" in md and "Implemented the verified outcome" in md
assert "Audit: OAuth handling [global-implementations]" in md
assert "audit of Morning Brief implementation [mission-control]" in md
assert "An audit was completed. Review remains open." in md
assert "Audit: OAuth handling [global-implementations] received a late closeout update" in md
assert "Morning Brief implementation [mission-control] received a late closeout update" in md
assert md.index("Morning Brief implementation [mission-control] — Implemented") < md.index(
    "Audit: OAuth handling [global-implementations] — audit of")
assert "\n  - **Inferred:** Audit: OAuth handling" in md
assert "commit cccccccccccc" in md
assert "aaaaaaaa" in md and "feat: add morning brief" in md
assert "Review the release evidence" in md and "Old decision was answered" in md
assert "Old unchecked task" in md and "Aging" in md
assert "Outcome extraction status budget_skip: 2 successes, 3 cache hits, 1 defers, 0 failures, 1 budget skips (1 uncalibrated), 6 disabled, 2 provider, 3 privacy, 4 lock, and 5 backoff skips, with 1 escalations today" in md
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

# P1 regression: sanitize runs on the RAW NEEDS YOU line BEFORE any headline
# clip. A decision whose secret sits PAST a short clip boundary must drop the
# whole row — never survive as a shortened, "safe"-looking clipped headline.
REG="$TMP/reg"; mkdir -p "$REG/state/data"
python3 - "$REG/state/data" <<'PY'
import json, os, sys
root=sys.argv[1]; now=1783674000
def write(name, data, cadence):
    json.dump({"schema":1,"feed":name,"generated_epoch":now,"cadence_s":cadence,
               "ok":True,"error":None,"data":data}, open(os.path.join(root,name+".json"),"w"))
# Safe words fit under the 40-char clip; the secret only appears far past it.
secret_line="Pick the deploy window " + ("x"*120) + " sk-livesecrettoken1234567890abcdef"
write("automation", {"jobs": [], "counts": {"red":0,"green":1}}, 300)
write("git", {"repos": []}, 900)
write("chats", {"nodes":[],"edges":[],"loose_ends":[],"loose_end_changes":[]}, 1800)
write("decisions", {"pinned":[
  {"id":"decision:"+"9"*24,"text":secret_line,"trust":"structured",
   "provenance":"chat-graph tier1"}], "inferred":[]}, 300)
PY
if MISSION_CONTROL_HOME="$REG/state" MORNING_BRIEF_NEEDS_YOU_CHARS=40 \
   MORNING_BRIEF_NOW_EPOCH=1783674000 "$BRIEF" >/dev/null 2>&1 && \
   python3 - "$REG/state/morning-brief/latest.json" "$REG/state/morning-brief/latest.md" <<'PY'
import json, sys
d=json.load(open(sys.argv[1])); md=open(sys.argv[2]).read()
needs=next(s for s in d["sections"] if s["title"]=="NEEDS YOU")
# The sensitive row must not render at all — not even a clipped safe prefix.
assert all("Pick the deploy window" not in r["text"] for r in needs["lines"]), needs["lines"]
assert "Pick the deploy window" not in md, "clipped prefix of a dropped row leaked to markdown"
assert "sk-livesecrettoken" not in json.dumps(d) and "sk-livesecrettoken" not in md
# Fail-closed still shows the reassuring placeholder and counts the secret drop.
assert any("No confirmed operator decision" in r["text"] for r in needs["lines"]), needs["lines"]
assert d["egress_counters"]["compose"]["reason_secret"] >= 1, d["egress_counters"]
PY
then pass "NEEDS YOU sanitizes raw line before clip: past-boundary secret drops the whole row"
else fail "NEEDS YOU sanitizes raw line before clip: past-boundary secret drops the whole row"; fi

# Unit invariant: a row the egress policy drops stays dropped — a clip never rescues it.
if PYTHONPATH="$ROOT/scripts" python3 - "$BRIEF" <<'PY'
import importlib.machinery, sys
m=importlib.machinery.SourceFileLoader("mb", sys.argv[1]).load_module()
raw="safe prefix " + ("y"*80) + " sk-anothersecrettoken0987654321zz"
assert m._sanitize_line(raw) is None, "raw sensitive line must sanitize to None"
assert m._sanitize_line(raw, clip=20) is None, "clip must not rescue a dropped row"
clipped=m._sanitize_line("plain safe headline that is quite long", clip=8)
assert clipped and clipped["text"].endswith("(options in dashboard)"), clipped
PY
then pass "_sanitize_line clip cannot rescue a row the egress policy drops"
else fail "_sanitize_line clip cannot rescue a row the egress policy drops"; fi

# P1 comprehension + P2 source regression: the default NEEDS YOU cap is top-3
# with a '+K more: dashboard' collapse line, and every rendered line shows its
# source. Four structured decisions and no NEEDS_YOU_MAX override.
CAPTEST="$TMP/cap"; mkdir -p "$CAPTEST/state/data"
python3 - "$CAPTEST/state/data" <<'PY'
import json, os, sys
root=sys.argv[1]; now=1783674000
def write(name, data, cadence):
    json.dump({"schema":1,"feed":name,"generated_epoch":now,"cadence_s":cadence,
               "ok":True,"error":None,"data":data}, open(os.path.join(root,name+".json"),"w"))
write("automation", {"jobs": [], "counts": {"red":0,"green":1}}, 300)
write("git", {"repos": []}, 900)
write("chats", {"nodes":[],"edges":[],"loose_ends":[],"loose_end_changes":[]}, 1800)
write("decisions", {"pinned":[
  {"id":"decision:"+str(i)*24,"text":"Decision %d needs review"%i,
   "trust":"structured","provenance":"chat-graph tier1"} for i in range(1,5)],
  "inferred":[]}, 300)
PY
if MISSION_CONTROL_HOME="$CAPTEST/state" MORNING_BRIEF_NOW_EPOCH=1783674000 "$BRIEF" >/dev/null 2>&1 && \
   python3 - "$CAPTEST/state/morning-brief/latest.json" "$CAPTEST/state/morning-brief/latest.md" <<'PY'
import json, sys
d=json.load(open(sys.argv[1])); md=open(sys.argv[2]).read()
needs=next(s for s in d["sections"] if s["title"]=="NEEDS YOU")
assert len(needs["lines"]) == 3, needs["lines"]        # default top-N significance = 3
assert needs["collapsed_count"] == 1, needs
assert "+1 more: dashboard" in md, md
assert "_(chat-graph tier1)_" in md, "per-line source must render in markdown"
PY
then pass "NEEDS YOU default cap is top-3 with '+K more: dashboard' collapse and per-line source"
else fail "NEEDS YOU default cap is top-3 with '+K more: dashboard' collapse and per-line source"; fi

# P2 dedup regression: identical text with different source stays distinct; only
# an exact-provenance duplicate is dropped.
if PYTHONPATH="$ROOT/scripts" python3 - "$BRIEF" <<'PY'
import importlib.machinery, sys
m=importlib.machinery.SourceFileLoader("mb", sys.argv[1]).load_module()
a={"text":"open work","trust":"Confirmed","source":"chat-graph"}
b={"text":"open work","trust":"Confirmed","source":"automation-status"}
c={"text":"open work","trust":"Confirmed","source":"chat-graph"}   # exact duplicate of a
section=m._section("T",[a,b,c])
assert len(section["lines"]) == 2, section["lines"]        # a and b survive; c drops
assert {l["source"] for l in section["lines"]} == {"chat-graph","automation-status"}
PY
then pass "section dedup keeps different-provenance rows and drops exact duplicates"
else fail "section dedup keeps different-provenance rows and drops exact duplicates"; fi

# Defect (a) regression: nested full-ingest freshness uses the NIGHTLY SLA, not
# the 1800s envelope cadence. The full transcript pass runs nightly (23:30
# com.gillettes.nightly-review -> chat-graph ingest), so a healthy last-night
# ingest (~26h band) must NOT flag, while a genuinely MISSED nightly (>30h SLA)
# MUST flag. (Round-3 encoded the defect: 26h treated as stale under the 1800s
# cadence, so a healthy nightly ingest read as stale every morning.)
NEST="$TMP/nested"; mkdir -p "$NEST/state/data"
mk_nest() { # $1=state dir  $2=last_full_ingest_age_s
  mkdir -p "$1/data"
  python3 - "$1/data" "$2" <<'PY'
import json, os, sys
root=sys.argv[1]; age=int(sys.argv[2]); now=1783674000
def write(name, data, cadence):
    json.dump({"schema":1,"feed":name,"generated_epoch":now,"cadence_s":cadence,
               "ok":True,"error":None,"data":data}, open(os.path.join(root,name+".json"),"w"))
write("automation", {"jobs": [], "counts": {"red":0,"green":1}}, 300)
write("git", {"repos": []}, 900)
# envelope fresh (generated_epoch == now); nested full-ingest age varies.
write("chats", {"nodes":[],"edges":[],"loose_ends":[],"loose_end_changes":[],
                "counts":{"last_full_ingest_age_s": age}}, 1800)
write("decisions", {"pinned":[],"inferred":[]}, 300)
PY
}
# Healthy last-night ingest (26h, within the nightly band) must read fresh.
mk_nest "$NEST/healthy/state" $((26*3600))
if MISSION_CONTROL_HOME="$NEST/healthy/state" MORNING_BRIEF_NOW_EPOCH=1783674000 "$BRIEF" >/dev/null 2>&1 && \
   python3 - "$NEST/healthy/state/morning-brief/latest.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
assert d["inputs"]["chats"]["state"] == "fresh", d["inputs"]["chats"]
assert "chats" not in d["stale_required_inputs"], d["stale_required_inputs"]
PY
then pass "healthy last-night full ingest (26h) is NOT flagged stale by the morning brief"
else fail "healthy last-night full ingest (26h) is NOT flagged stale by the morning brief"; fi
# Genuinely missed nightly (50h) must be reported stale.
mk_nest "$NEST/missed/state" $((50*3600))
if MISSION_CONTROL_HOME="$NEST/missed/state" MORNING_BRIEF_NOW_EPOCH=1783674000 "$BRIEF" >/dev/null 2>&1 && \
   python3 - "$NEST/missed/state/morning-brief/latest.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
assert d["inputs"]["chats"]["state"] == "stale", d["inputs"]["chats"]
assert "chats" in d["stale_required_inputs"], d["stale_required_inputs"]
PY
then pass "genuinely missed nightly full ingest (50h) is reported stale (nested freshness)"
else fail "genuinely missed nightly full ingest (50h) is reported stale (nested freshness)"; fi

# Skew regression: a chats input whose generated_epoch is in the FUTURE (clock
# skew / invalid envelope) must render as its own visible "skew" warning, never
# fresh, and count as a not-current required input. (Was: _input_health folded
# skew into "fresh", so a future timestamp read as trustworthy.)
SKEW="$TMP/skew"; mkdir -p "$SKEW/state/data"
python3 - "$SKEW/state/data" <<'PY'
import json, os, sys
root=sys.argv[1]; now=1783674000
def write(name, data, cadence, epoch):
    json.dump({"schema":1,"feed":name,"generated_epoch":epoch,"cadence_s":cadence,
               "ok":True,"error":None,"data":data}, open(os.path.join(root,name+".json"),"w"))
write("automation", {"jobs": [], "counts": {"red":0,"green":1}}, 300, now)
write("git", {"repos": []}, 900, now)
# 10 minutes into the FUTURE relative to compose now.
write("chats", {"nodes":[],"edges":[],"loose_ends":[],"loose_end_changes":[]}, 1800, now+600)
write("decisions", {"pinned":[],"inferred":[]}, 300, now)
PY
if MISSION_CONTROL_HOME="$SKEW/state" MORNING_BRIEF_NOW_EPOCH=1783674000 "$BRIEF" >/dev/null 2>&1 && \
   python3 - "$SKEW/state/morning-brief/latest.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
assert d["inputs"]["chats"]["state"] == "skew", d["inputs"]["chats"]
assert "chats" in d["stale_required_inputs"], d["stale_required_inputs"]
PY
then pass "future generated_epoch renders as visible skew warning, never fresh"
else fail "future generated_epoch renders as visible skew warning, never fresh"; fi

# Defect (c) regression: resolution wording is evidence-honest. Plain "Resolved"
# is reserved for evidence-backed resolutions; a fork dedup reads "Duplicate
# consolidated"; a source-absent inference is marked, never a bare "Resolved".
if PYTHONPATH="$ROOT/scripts" python3 - "$BRIEF" <<'PY'
import importlib.machinery, sys
m=importlib.machinery.SourceFileLoader("mb", sys.argv[1]).load_module()
def snap(rows):
    return {"chats": {"schema":1,"feed":"chats","ok":True,"generated_epoch":1783674000,
                      "data": {"loose_end_changes": rows, "loose_ends": []}}}
def one(evidence):
    rows=[{"id":"x","stable_id":"x","source_node":"codex:x","kind":"chat_open_end",
           "item_key":"x","text":"An item","change_type":"resolved","updated_at":1783673990,
           "resolved_at":1783673990,"resolution_evidence_type":evidence,
           "resolution_evidence_ref":"ref"}]
    lines,_,_=m._open_changes(snap(rows), 8, (0,""))
    return lines[0]["text"]
assert one("manual").startswith("Resolved —"), one("manual")
assert one("source_absent").startswith("Resolved") is False, one("source_absent")
assert "source absent" in one("source_absent").lower(), one("source_absent")
fd=one("fork_dedup")
assert fd.startswith("Duplicate consolidated —"), fd
# change_type resolved but no evidence type must NOT claim a bare "Resolved"
assert one(None).startswith("Resolved —") is False, one(None)
# non-resolution change types keep their plain labels
rows=[{"id":"y","stable_id":"y","source_node":"codex:y","kind":"chat_open_end",
       "item_key":"y","text":"New item","change_type":"new","updated_at":1783673990}]
lines,_,_=m._open_changes(snap(rows), 8, (0,""))
assert lines[0]["text"].startswith("New —"), lines[0]["text"]
PY
then pass "open-change resolution wording keys off evidence type (Resolved reserved for evidence-backed)"
else fail "open-change resolution wording keys off evidence type (Resolved reserved for evidence-backed)"; fi

printf '%s\n' "----"
if [ "$FAIL" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$FAIL FAILED"; exit 1
