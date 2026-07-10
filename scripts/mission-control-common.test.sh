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

printf '%s\n' "----"
if [ "$FAIL" -eq 0 ]; then
  printf 'PASS=%s FAIL=0\n' "$PASS"
  exit 0
fi
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
exit 1
