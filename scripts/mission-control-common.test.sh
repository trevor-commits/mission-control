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
# Derive fixtures from HOME so the privacy gate remains valid in an isolated
# test home instead of accidentally testing Trevor's production path only.
home = os.environ["HOME"]
ordinary_path = os.path.join(home, "Downloads", "private", "raw.txt")
ordinary = safe("read " + ordinary_path, NARRATIVE)
assert not ordinary.dropped and ordinary_path not in ordinary.value
approved_repo_root = os.path.join(home, "Coding Projects", "mission-control")
approved_repo_path = os.path.join(approved_repo_root, "scripts", "chat-graph")
approved_repo = safe("changed " + approved_repo_path, NARRATIVE)
assert approved_repo_root in approved_repo.value
approved_tool_path = os.path.join(home, ".codex", "scripts", "chat-source")
approved_tool = safe("run " + approved_tool_path, NARRATIVE)
assert approved_tool_path in approved_tool.value

# Structured actions retain required local paths after sensitive screening.
action = safe('cd "' + approved_repo_root + '" && git status', ACTION)
assert not action.dropped and approved_repo_root in action.value

# Model preparation excludes raw tool results and records source metadata only.
messages = [
    {"role": "assistant", "text": "Done in " + os.path.join(home, "Downloads", "secret.txt")},
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
    feed_health, full_ingest_sla_s, nested_ingest_stale, nested_ingest_state,
    same_local_day, write_install_stamp, verify_install_stamp,
    next_local_midnight,
)

NOW = 1783674000
CAD = 300
OID = "a" * 40

def env(**kw):
    base = {"schema": 1, "feed": "fixture", "ok": True,
            "generated_epoch": NOW, "cadence_s": CAD, "data": {}}
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
    return env(feed="chats", generated_epoch=NOW, cadence_s=1800,
               data={"counts": c})
assert nested_ingest_stale(chats(7 * 3600)) is False        # healthy last-night
assert nested_ingest_stale(chats(26 * 3600)) is False       # within nightly band
assert nested_ingest_stale(chats(50 * 3600)) is True        # missed nightly
assert nested_ingest_stale(chats(None)) is True             # unknown -> stale
assert nested_ingest_stale(env(feed="chats", generated_epoch=NOW, data={"counts": {}})) is True
assert nested_ingest_stale(chats("not-an-int")) is True
assert nested_ingest_stale(chats(-60)) is True
assert nested_ingest_stale(chats(9999, ingest_skipped=True)) is True
# Chats are never green when the nested evidence container is absent or has the
# wrong wire type. Unrelated feeds do not inherit the chat-only ingest marker.
assert nested_ingest_state(env(feed="chats", generated_epoch=NOW)) == "unknown"
assert nested_ingest_state(env(feed="chats", generated_epoch=NOW, data={})) == "unknown"
assert nested_ingest_state(env(feed="chats", generated_epoch=NOW,
                               data={"counts": []})) == "unknown"
assert nested_ingest_state(env(feed="automation", generated_epoch=NOW,
                               data={"counts": {"ingest_skipped": True}})) == "fresh"
assert nested_ingest_state(chats(9999, ingest_skipped=False)) == "fresh"
for malformed_skip in (1, 0, "false", [], {}):
    assert nested_ingest_state(chats(9999, ingest_skipped=malformed_skip)) == "unknown"
# A derived green flag cannot launder missing, malformed, negative, or
# contradictory raw evidence into a trusted state.
assert nested_ingest_state(chats(-60, full_ingest_state="fresh")) == "unknown"
assert nested_ingest_state(chats(-60, full_ingest_stale=False)) == "unknown"
assert nested_ingest_state(chats("bad", full_ingest_state="fresh")) == "unknown"
for malformed_age in (True, "60", float("inf"), float("-inf"), float("nan")):
    assert nested_ingest_state(chats(malformed_age, full_ingest_state="fresh",
                                      full_ingest_stale=False)) == "unknown"
assert nested_ingest_state(env(feed="chats", generated_epoch=NOW, data={"counts": {
    "full_ingest_state": "fresh"}})) == "unknown"
assert nested_ingest_state(chats(50 * 3600, full_ingest_state="fresh")) == "unknown"
assert nested_ingest_state(chats(7 * 3600, full_ingest_state="fresh",
                                  full_ingest_stale=True)) == "unknown"
assert nested_ingest_state(chats(7 * 3600, full_ingest_state="bogus",
                                  full_ingest_stale=False)) == "unknown"
assert nested_ingest_state(chats(7 * 3600, full_ingest_state="fresh",
                                  full_ingest_stale="false")) == "unknown"
# The raw helper supports producer computation before derived flags are stamped,
# but a chats consumer must reject an incomplete one-flag schema.
assert nested_ingest_state(chats(7 * 3600)) == "fresh"
for partial in ({"full_ingest_state": "fresh"},
                {"full_ingest_stale": False}):
    h = feed_health(chats(7 * 3600, **partial), 1800, NOW)
    assert h["nested_state"] == "unknown" and h["nested_stale"] is True, h
# Numeric comparison is exact and int-safe: no float truncation and no
# math.isfinite conversion of arbitrary-size integers.
assert nested_ingest_state(chats(30 * 3600, full_ingest_state="fresh",
                                  full_ingest_stale=False)) == "fresh"
assert nested_ingest_state(chats(30 * 3600 + 0.1,
                                  full_ingest_state="fresh",
                                  full_ingest_stale=False)) == "unknown"
assert nested_ingest_state(chats(10 ** 10000)) == "stale"
assert nested_ingest_state(chats(1, full_ingest_sla_s=10 ** 10000)) == "fresh"
for malformed_sla in (True, "3600", float("inf"), float("nan"), 0, -1):
    assert nested_ingest_state(chats(2 * 3600, full_ingest_sla_s=malformed_sla,
                                      full_ingest_state="fresh",
                                      full_ingest_stale=False)) == "unknown"
# Consumers fail closed when a rolling-upgrade feed has raw age but no derived
# state/legacy flag; the producer-only helper may still compute the canonical flag.
h = feed_health(chats(7 * 3600), 1800, NOW)
assert h["nested_state"] == "unknown" and h["nested_stale"] is True, h
# envelope may override with its own completion SLA
assert nested_ingest_stale(chats(2 * 3600, full_ingest_sla_s=3600)) is True
# env override tightens the default
os.environ["MISSION_CONTROL_FULL_INGEST_SLA_S"] = "3600"
assert nested_ingest_stale(chats(2 * 3600)) is True
assert full_ingest_sla_s() == 3600
os.environ["MISSION_CONTROL_FULL_INGEST_SLA_S"] = "-1"
assert full_ingest_sla_s() == 30 * 3600
del os.environ["MISSION_CONTROL_FULL_INGEST_SLA_S"]

# Persisted JSON time fields are strict finite integer seconds. Malformed,
# non-finite, and out-of-platform-range values fail closed without traceback.
for malformed_epoch in (True, "123", float("inf"), float("-inf"), float("nan")):
    h = feed_health(env(generated_epoch=malformed_epoch), CAD, NOW)
    assert h["state"] == "stale" and h["generated_epoch"] is None, h
for malformed_until in (True, "123", float("inf"), float("-inf"), float("nan")):
    h = feed_health(env(generated_epoch=NOW, valid_until=malformed_until), CAD, NOW)
    assert h["valid_until"] is None, h
for extreme in (10 ** 10000, -(10 ** 10000), float("inf"), float("-inf")):
    assert same_local_day(extreme, NOW) is False
    assert next_local_midnight(extreme) is None

# The freshness boundary validates the complete success-envelope wire shape;
# malformed schema/ok/cadence/data values are red and never coerced to green.
for malformed in (
        [], {}, env(schema=True), env(ok="false"), env(cadence_s=True),
        env(cadence_s="300"), env(cadence_s=0), env(cadence_s=300.5),
        env(cadence_s=10 ** 9),
        env(data=[]), env(data=None)):
    h = feed_health(malformed, CAD, NOW)
    assert h["red"] is True and h["state"] in ("missing", "error"), (malformed, h)

# --- install stamp covers deployment assets (index.html, vendor/*) -----------
home = tempfile.mkdtemp()
bin_dir = os.path.join(home, "bin"); os.makedirs(bin_dir)
for runtime in ["dashboard", "morning-brief", "morning-brief-deadman",
                "decision-alert", "mission_control_common.py"]:
    open(os.path.join(bin_dir, runtime), "w").write("runtime %s\n" % runtime)
    if runtime != "mission_control_common.py":
        os.chmod(os.path.join(bin_dir, runtime), 0o700)
open(os.path.join(home, "index.html"), "w").write("<html>shell</html>\n")
os.makedirs(os.path.join(home, "vendor"))
open(os.path.join(home, "vendor", "cytoscape.min.js"), "w").write("//vendor\n")
assets = {"index.html": os.path.join(home, "index.html"),
          "vendor/cytoscape.min.js": os.path.join(home, "vendor", "cytoscape.min.js")}
write_install_stamp(bin_dir, OID, "head",
                    ["dashboard", "morning-brief", "morning-brief-deadman",
                     "decision-alert", "mission_control_common.py"],
                    NOW, assets=assets)
v = verify_install_stamp(bin_dir)
assert v["present"] and v["ok"], v
# omitted required keys must fail verification; an underspecified stamp is not proof.
stamp_path = os.path.join(bin_dir, "install-stamp.json")
with open(stamp_path, "w") as handle:
    json.dump({"schema": 1, "installed_at": NOW, "head_sha": OID,
               "provenance": "head", "files": {"dashboard": "x"},
               "assets": {"index.html": "x"}}, handle)
v = verify_install_stamp(bin_dir)
assert not v["ok"] and "decision-alert" in v["missing"] and "vendor/cytoscape.min.js" in v["missing"], v
write_install_stamp(bin_dir, OID, "head",
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
open(os.path.join(home, "vendor", "cytoscape.min.js"), "w").write("//vendor\n")
# The verifier is total over valid JSON and returns a stable content-free reason.
for malformed in ([], {"files": [], "assets": {}},
                  {"files": {}, "assets": []}):
    with open(stamp_path, "w") as handle:
        json.dump(malformed, handle)
    v = verify_install_stamp(bin_dir)
    assert v["present"] and not v["ok"] and v["reason"] == "malformed", v
    assert all(k in v for k in ("mismatches", "missing", "unexpected")), v
for field, value in (("head_sha", []), ("provenance", {})):
    write_install_stamp(bin_dir, OID, "head",
                        ["dashboard", "morning-brief", "morning-brief-deadman",
                         "decision-alert", "mission_control_common.py"],
                        NOW, assets=assets)
    stamp = json.load(open(stamp_path)); stamp[field] = value
    json.dump(stamp, open(stamp_path, "w"))
    v = verify_install_stamp(bin_dir)
    assert v["present"] and not v["ok"] and v["reason"] == "malformed", v
# Boolean schemas, non-positive/boolean install times, and display labels are
# not commit provenance even when every current file hash happens to match.
for field, value in (("schema", True), ("installed_at", True),
                     ("installed_at", 0), ("head_sha", "abc123"),
                     ("provenance", "other")):
    write_install_stamp(bin_dir, OID, "head",
                        ["dashboard", "morning-brief", "morning-brief-deadman",
                         "decision-alert", "mission_control_common.py"],
                        NOW, assets=assets)
    stamp = json.load(open(stamp_path)); stamp[field] = value
    json.dump(stamp, open(stamp_path, "w"))
    v = verify_install_stamp(bin_dir)
    assert v["present"] and not v["ok"] and v["reason"] == "malformed", (field, v)
# Malformed attacker-controlled metadata and unexpected map keys never echo into
# status/deadman verdicts; only fixed reason/category labels leave the verifier.
write_install_stamp(bin_dir, OID, "head",
                    ["dashboard", "morning-brief", "morning-brief-deadman",
                     "decision-alert", "mission_control_common.py"],
                    NOW, assets=assets)
stamp = json.load(open(stamp_path)); stamp["head_sha"] = "secret-head-label"
json.dump(stamp, open(stamp_path, "w")); v = verify_install_stamp(bin_dir)
assert v["head_sha"] is None and "secret-head-label" not in repr(v), v
write_install_stamp(bin_dir, OID, "head",
                    ["dashboard", "morning-brief", "morning-brief-deadman",
                     "decision-alert", "mission_control_common.py"],
                    NOW, assets=assets)
stamp = json.load(open(stamp_path)); stamp["files"]["sk-secret-key-name"] = "0" * 64
json.dump(stamp, open(stamp_path, "w")); v = verify_install_stamp(bin_dir)
assert v["unexpected"] == ["unexpected-runtime"] and "sk-secret" not in repr(v), v
os.remove(stamp_path)
v = verify_install_stamp(bin_dir)
assert not v["present"] and not v["ok"] and v["reason"] == "missing", v
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
