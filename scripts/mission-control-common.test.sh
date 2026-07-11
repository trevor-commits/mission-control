#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

PYTHONPATH="$ROOT/scripts" python3 - <<'PY'
import json
import os
import tempfile

from mission_control_common import (
    ACTION,
    ERROR,
    IDENTIFIER,
    MODEL_INPUT,
    NARRATIVE,
    NOTIFICATION,
    EgressCounters,
    sanitize_chunks,
    sanitize_model_messages,
    sanitize_text,
)

counters = EgressCounters()

def safe(value, field=NARRATIVE, **kwargs):
    return sanitize_text(value, field, counters=counters, **kwargs)

# Secrets/PII/denylist fail closed for every field class.
for field in (NARRATIVE, ACTION, IDENTIFIER, ERROR, MODEL_INPUT, NOTIFICATION):
    out = safe("keep sk-abcdefghijklmnopqrstuvwxyz123456 end", field)
    assert out.dropped and out.value == "«REDACTED-SECRET»", (field, out)

# Redact provider token-family prefixes even when documentation intentionally
# omits the secret body. Those prefixes should not appear in briefs or alerts.
for field in (NARRATIVE, ACTION, IDENTIFIER, ERROR, MODEL_INPUT, NOTIFICATION):
    out = safe("setup token starts with sk-ant-oat01-", field)
    assert out.dropped and out.value == "«REDACTED-SECRET»", (field, out)

assert safe("email trevor@example.com", NARRATIVE).dropped
assert safe("call +1 (415) 555-0199", ACTION).dropped
assert safe("contains private-customer-x", NARRATIVE,
            denylist=("private-customer-x",)).dropped

# Narrative strips ordinary host paths, but approved repo/tool roots survive.
ordinary = safe("read /Users/gillettes/Downloads/private/raw.txt", NARRATIVE)
assert not ordinary.dropped and "/Users/" not in ordinary.value
approved_repo = safe("changed /Users/gillettes/Coding Projects/mission-control/scripts/chat-graph", NARRATIVE)
assert "Coding Projects/mission-control" in approved_repo.value
approved_tool = safe("run /Users/gillettes/.codex/scripts/chat-source", NARRATIVE)
assert "/Users/gillettes/.codex/scripts/chat-source" in approved_tool.value

# Structured actions retain required local paths after sensitive screening.
action = safe('cd "/Users/gillettes/Coding Projects/mission-control" && git status', ACTION)
assert not action.dropped and "/Users/gillettes/Coding Projects/mission-control" in action.value

# Model preparation excludes raw tool results and records source metadata only.
messages = [
    {"role": "assistant", "text": "Done in /Users/gillettes/Downloads/secret.txt"},
    {"role": "tool", "text": "raw output sk-abcdefghijklmnopqrstuvwxyz123456"},
    {"type": "tool_result", "content": "also raw"},
    {"role": "user", "text": "Trevor said proceed"},
]
prepared, metadata = sanitize_model_messages(
    messages,
    source_provider="codex",
    max_messages=3,
    max_bytes=200,
    counters=counters,
)
assert all(row.get("role") != "tool" and row.get("type") != "tool_result" for row in prepared)
assert metadata["source_provider"] == "codex"
assert metadata["messages_selected"] <= 3
assert "content" not in metadata and "text" not in metadata
assert "sk-" not in json.dumps(prepared)

# Notification chunks use the same policy and drop sensitive chunks.
chunks = sanitize_chunks([
    "safe first chunk",
    "token sk-abcdefghijklmnopqrstuvwxyz123456",
], counters=counters)
assert chunks == ["safe first chunk"], chunks

snapshot = counters.snapshot()
assert snapshot["dropped_fields"] >= 15, snapshot
assert snapshot["tool_outputs_skipped"] == 2, snapshot
assert snapshot["path_redactions"] >= 2, snapshot

# Public objects contain no source content in their repr/JSON metadata.
assert "trevor@example.com" not in repr(counters)
assert "private-customer-x" not in json.dumps(snapshot)
print("PYTHON PASS")
PY
RC=$?

if [ "$RC" -eq 0 ]; then pass "field-aware privacy matrix"; else fail "field-aware privacy matrix"; fi

PYTHONPATH="$ROOT/scripts" python3 - <<'PY'
import json, os, tempfile, time
from mission_control_common import (
    feed_health, nested_ingest_stale, write_install_stamp, verify_install_stamp,
    next_local_midnight,
)

NOW = 1783674000
CAD = 300

def env(**kw):
    base = {"schema": 1, "ok": True, "generated_epoch": NOW}
    base.update(kw)
    return base

def local_noon(epoch):  # 12:00 local on epoch's day — a TZ-robust anchor for
    lt = time.localtime(int(epoch))  # horizon tests (next_local_midnight is ~12h out)
    return int(time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, 12, 0, 0, 0, 0, -1)))
NOON = local_noon(NOW)

# --- skew: a FUTURE generated_epoch must never read fresh -------------------
h = feed_health(env(generated_epoch=NOW + 600), CAD, NOW)
assert h["state"] == "skew" and h["red"] is False and h["age_s"] == -600, h
assert next_local_midnight(10 ** 100) is None
h = feed_health(env(generated_epoch=10 ** 100, valid_until=10 ** 100), CAD, NOW)
assert h["state"] == "skew" and h["red"] is False, h
h = feed_health(env(generated_epoch=-(10 ** 100), valid_until=NOW + 3600), CAD, NOW)
assert h["state"] == "stale" and h["red"] is True, h

# --- bounded validity: an absurd far-future valid_until must NOT suppress
# staleness. Old epoch (year 2001) + far-future valid_until (year 2100) -> stale.
h = feed_health(env(generated_epoch=1000000000, valid_until=4102444800), CAD, NOW)
assert h["state"] == "stale" and h["red"] is True, h
# a legit within-horizon valid_until IS honored even though age > cadence: composed
# at local noon, valid to tonight's local midnight, read 4h later. Noon-anchored so
# the next-local-midnight horizon is a stable ~12h out regardless of run time/TZ.
h = feed_health(env(generated_epoch=NOON, valid_until=next_local_midnight(NOON)),
                CAD, NOON + 4 * 3600)
assert h["state"] == "fresh" and h["red"] is False, h
# ER-109 round 6: the validity horizon is next local midnight (<=~24-25h), NOT a flat
# 2-day slab. A ~47h-span valid_until on an OLD brief must be REJECTED (was accepted
# as fresh under the old 48h bound) -> falls to the age ladder -> stale.
h = feed_health(env(generated_epoch=NOON - 40 * 3600, valid_until=NOON + 7 * 3600),
                CAD, NOON)
assert h["state"] == "stale" and h["red"] is True, h
# a 30h-old brief cannot read fresh off a too-long valid_until (17h in the future,
# i.e. epoch+47h). Old 48h bound honored it; next-midnight horizon rejects it.
h = feed_health(env(generated_epoch=NOON - 30 * 3600, valid_until=NOON + 17 * 3600),
                CAD, NOON)
assert h["state"] == "stale" and h["red"] is True, h
# a valid_until several days past the horizon is rejected -> falls to age ladder.
h = feed_health(env(generated_epoch=NOW - 10 * 86400,
                    valid_until=NOW + 3 * 86400), CAD, NOW)
assert h["state"] == "stale", h
# ER-109 round 7: valid_until is a HARD expiry at exact-midnight rollover. A brief
# composed 23:59 local, valid to the next local midnight, must read fresh 30s before
# midnight, then stale AT midnight (now == valid_until) and 5 min after -- an expired
# daily brief cannot linger fresh on the poll cadence.
MID = next_local_midnight(NOON)          # a real local midnight
BR = MID - 60                            # composed 23:59 local, valid to MID
h = feed_health(env(generated_epoch=BR, valid_until=MID), CAD, MID - 30)
assert h["state"] == "fresh" and h["red"] is False, h
h = feed_health(env(generated_epoch=BR, valid_until=MID), CAD, MID)
assert h["state"] == "stale" and h["red"] is True, h
h = feed_health(env(generated_epoch=BR, valid_until=MID), CAD, MID + 300)
assert h["state"] == "stale" and h["red"] is True, h

# --- nightly full-ingest SLA (30h default), NOT the 1800s envelope cadence ---
def chats(age_s, **counts):
    c = {"last_full_ingest_age_s": age_s}
    c.update(counts)
    return env(generated_epoch=NOW, data={"counts": c})
assert nested_ingest_stale(chats(7 * 3600)) is False        # healthy last-night
assert nested_ingest_stale(chats(26 * 3600)) is False       # within nightly band
assert nested_ingest_stale(chats(50 * 3600)) is True        # missed nightly
assert nested_ingest_stale(chats(None)) is True             # unknown -> stale
assert nested_ingest_stale(env(feed="chats", generated_epoch=NOW, data={"counts": {}})) is True
assert nested_ingest_stale(chats("not-an-int")) is True
assert nested_ingest_stale(chats(-60)) is True
assert nested_ingest_stale(chats(9999, ingest_skipped=True)) is True
# envelope may override with its own completion SLA
assert nested_ingest_stale(chats(2 * 3600, full_ingest_sla_s=3600)) is True
# env override tightens the default
os.environ["MISSION_CONTROL_FULL_INGEST_SLA_S"] = "3600"
assert nested_ingest_stale(chats(2 * 3600)) is True
del os.environ["MISSION_CONTROL_FULL_INGEST_SLA_S"]

# --- install stamp covers deployment assets (index.html, vendor/*) -----------
home = tempfile.mkdtemp()
bin_dir = os.path.join(home, "bin"); os.makedirs(bin_dir)
for runtime in ["dashboard", "morning-brief", "morning-brief-deadman",
                "decision-alert", "mission_control_common.py"]:
    open(os.path.join(bin_dir, runtime), "w").write("runtime %s\n" % runtime)
open(os.path.join(home, "index.html"), "w").write("<html>shell</html>\n")
os.makedirs(os.path.join(home, "vendor"))
open(os.path.join(home, "vendor", "cytoscape.min.js"), "w").write("//vendor\n")
assets = {"index.html": os.path.join(home, "index.html"),
          "vendor/cytoscape.min.js": os.path.join(home, "vendor", "cytoscape.min.js")}
write_install_stamp(bin_dir, "abc123", "head",
                    ["dashboard", "morning-brief", "morning-brief-deadman",
                     "decision-alert", "mission_control_common.py"],
                    NOW, assets=assets)
v = verify_install_stamp(bin_dir)
assert v["present"] and v["ok"], v
# omitted required keys must fail verification; an underspecified stamp is not proof.
stamp_path = os.path.join(bin_dir, "install-stamp.json")
with open(stamp_path, "w") as handle:
    json.dump({"schema": 1, "installed_at": NOW, "head_sha": "abc123",
               "provenance": "head", "files": {"dashboard": "x"},
               "assets": {"index.html": "x"}}, handle)
v = verify_install_stamp(bin_dir)
assert not v["ok"] and "decision-alert" in v["missing"] and "vendor/cytoscape.min.js" in v["missing"], v
write_install_stamp(bin_dir, "abc123", "head",
                    ["dashboard", "morning-brief", "morning-brief-deadman",
                     "decision-alert", "mission_control_common.py"],
                    NOW, assets=assets)
# drift in the render shell must be caught (it carries the render JS)
open(os.path.join(home, "index.html"), "a").write("<!-- drift -->\n")
v = verify_install_stamp(bin_dir)
assert not v["ok"] and "index.html" in v["mismatches"], v
# a missing vendored asset is caught too
os.remove(os.path.join(home, "vendor", "cytoscape.min.js"))
v = verify_install_stamp(bin_dir)
assert "vendor/cytoscape.min.js" in v["missing"], v
print("PYTHON PASS")
PY
RC=$?
if [ "$RC" -eq 0 ]; then pass "freshness/skew/validity + nightly ingest SLA + install-asset stamp"; else fail "freshness/skew/validity + nightly ingest SLA + install-asset stamp"; fi

printf '%s\n' "----"
if [ "$FAIL" -eq 0 ]; then
  printf 'PASS=%s FAIL=0\n' "$PASS"
  exit 0
fi
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit 1
