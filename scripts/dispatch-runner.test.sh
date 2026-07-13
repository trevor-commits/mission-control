#!/bin/bash
# Answer-dispatch slice 1: pure routing truth table + stubbed end-to-end drain.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/scripts/dispatch-runner"
DASHBOARD="$ROOT/scripts/dashboard"
DECISIONS="$ROOT/scripts/decision-alert"
TMP="$ROOT/tmp/dispatch-test.$$"
cleanup() {
  if [ "${KEEP_DISPATCH_TEST_TMP:-0}" = "1" ]; then
    printf 'EVIDENCE_DIR=%s\n' "$TMP"
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT
mkdir -p "$TMP"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }

json_assert() {
  python3 - "$@" <<'PY'
import json, sys
path, expression = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
assert eval(expression, {"__builtins__": {}}, {"d": data}), (expression, data)
PY
}

route_case() {
  name="$1" payload="$2" expression="$3"
  out="$TMP/route-$name.json"
  if "$RUNNER" --route-json "$payload" >"$out" && json_assert "$out" "$expression"; then
    pass "router $name"
  else
    fail "router $name"
  fi
}

run_router_truth_table() {
  route_case tier-floor \
    '{"decision_text":"Approve the security auth migration governance gate","source_chat":{"key":"glm:s1","provider":"glm","live":true,"same_repo":true},"usage":{"glm":"Can use","codex":"Can use","claude":"Can use"},"preferred_platform":"glm"}' \
    'd["route"] == "new-platform" and d["platform"] == "codex" and d["model"] == "gpt-5.6-sol" and d["reason"] == "tier-floor override"'
  route_case tier-floor-live-codex \
    '{"decision_text":"Approve the security migration","source_chat":{"key":"codex:s1b","provider":"codex","live":true,"same_repo":true},"usage":{"codex":"Can use","claude":"Can use"},"preferred_platform":"codex"}' \
    'd["route"] == "new-chat" and d["platform"] == "codex" and d["model"] == "gpt-5.6-sol" and d["reason"] == "tier-floor override"'
  route_case live-same-chat \
    '{"decision_text":"Continue the bounded implementation","source_chat":{"key":"codex:s2","provider":"codex","live":true,"same_repo":true},"usage":{"codex":"Wait","claude":"Can use"},"preferred_platform":"codex"}' \
    'd["route"] == "same-chat" and d["platform"] == "codex" and d["model"] == "gpt-5.6-sol"'
  route_case stale-source \
    '{"decision_text":"Continue the bounded implementation","source_chat":{"key":"codex:s3","provider":"codex","live":false,"same_repo":true},"usage":{"codex":"Can use","claude":"Can use"},"preferred_platform":"codex"}' \
    'd["route"] == "new-chat" and d["platform"] == "codex"'
  route_case headroom-switch \
    '{"decision_text":"Continue the bounded implementation","source_chat":{"key":"codex:s4","provider":"codex","live":false,"same_repo":true},"usage":{"codex":"Wait","claude":"Can use"},"preferred_platform":"codex"}' \
    'd["route"] == "new-platform" and d["platform"] == "claude" and d["model"] == "claude-fable-5"'
  route_case no-target \
    '{"decision_text":"Continue the bounded implementation","source_chat":{"key":"codex:s5","provider":"codex","live":false,"same_repo":true},"usage":{"codex":"Wait","claude":"Wait"},"preferred_platform":"codex"}' \
    'd["route"] == "hold" and d["platform"] is None and d["model"] is None'
  route_case unsupported-source \
    '{"decision_text":"Continue the bounded implementation","source_chat":{"key":"hermes:s6","provider":"hermes","live":true,"same_repo":true},"usage":{"codex":"Can use","claude":"Wait"},"preferred_platform":"hermes"}' \
    'd["route"] == "new-platform" and d["platform"] == "codex"'
}

write_feeds() {
  home="$1" session_id="$2" live="$3" repo="$4"
  mkdir -p "$home/data"
  python3 - "$home/data/chats.json" "$session_id" "$live" "$repo" <<'PY'
import json, sys
path, sid, live, repo = sys.argv[1:]
json.dump({"data":{"nodes":[{"id":sid,"provider":"codex","repo":repo,
          "live":live == "true"}]}}, open(path,"w",encoding="utf-8"))
PY
  cat >"$home/data/usage.json" <<'JSON'
{"data":{"providers":[
  {"provider":"codex","used_pct":20,"health":"ok"},
  {"provider":"claude","used_pct":40,"health":"ok"}
]}}
JSON
}

create_decision() {
  home="$1" session_id="$2" source_kind="${3:-chat}"
  MISSION_CONTROL_HOME="$home" DECISION_ALERT_NOW_EPOCH=1783962000 \
    "$DECISIONS" ingest --source-kind "$source_kind" \
      --source-key "outcome:$session_id:dispatch-case" \
      --text '**DECISION NEEDED:** Continue this work. **`Implement the bounded slice`** — keep the existing scope.' \
      --evidence 'synthetic dispatch decision' --trust structured \
      --provenance 'chat-graph tier1' \
      --anchor "chat-graph:$session_id:dispatch-case" \
      --resolution-key "dispatch:$session_id" --json
}

run_end_to_end() {
  home="$TMP/home"
  session_id="11111111-2222-4333-8444-555555555555"
  write_feeds "$home" "$session_id" true "$ROOT"
  created="$(create_decision "$home" "$session_id")" || created=""
  decision_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$created" 2>/dev/null || true)"
  if [ -z "$decision_id" ]; then fail "synthetic decision created"; return; fi
  MISSION_CONTROL_HOME="$home" "$DECISIONS" status --json >"$home/data/decisions.json"

  answer_out="$TMP/answer.out"
  answer_err="$TMP/answer.err"
  if MISSION_CONTROL_HOME="$home" REPO_ROOT="$ROOT" DECISION_ALERT_AUTO=0 \
      "$DASHBOARD" decide answer "$decision_id" 1 >"$answer_out" 2>"$answer_err"; then
    pass "answer recording succeeds"
  else
    fail "answer recording succeeds"
    return
  fi
  queue="$home/dispatch/queue/$decision_id.json"
  if [ -f "$queue" ] && json_assert "$queue" \
      'd["decision_id"] and d["decision_text"] and d["option_number"] == 1 and d["option_text"] == "Implement the bounded slice" and d["source_chat"] == "codex:11111111-2222-4333-8444-555555555555" and d["repo"] and d["severity"] == "normal" and d["answered_at"]'; then
    pass "answer writes complete dispatch queue entry"
  else
    fail "answer writes complete dispatch queue entry"
  fi
  cp "$queue" "$TMP/queue-copy.json"

  # The runner lock is non-blocking and a second instance exits without draining.
  lock_marker="$TMP/lock-ready"
  python3 - "$home/dispatch/.dispatch-runner.lock" "$lock_marker" <<'PY' &
import fcntl, os, sys, time
fd=os.open(sys.argv[1], os.O_CREAT|os.O_RDWR, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2],"w").close()
time.sleep(3)
PY
  lock_pid=$!
  while [ ! -e "$lock_marker" ]; do sleep 0.02; done
  if MISSION_CONTROL_HOME="$home" DISPATCH_TEMPLATES_DIR="$ROOT/dispatch/templates" \
      "$RUNNER" >"$TMP/locked.json" && json_assert "$TMP/locked.json" \
      'd["status"] == "locked" and d["processed"] == 0' && [ -f "$queue" ]; then
    pass "single-flight lock leaves queue untouched"
  else
    fail "single-flight lock leaves queue untouched"
  fi
  wait "$lock_pid"

  printf '{broken' >"$home/dispatch/queue/decision:ffffffffffffffffffffffff.json"
  run_out="$TMP/run.json"
  if MISSION_CONTROL_HOME="$home" DISPATCH_TEMPLATES_DIR="$ROOT/dispatch/templates" \
      "$RUNNER" >"$run_out" && json_assert "$run_out" \
      'd["processed"] == 1 and d["malformed"] == ["decision:ffffffffffffffffffffffff.json"]'; then
    pass "drain skips and surfaces malformed entries"
  else
    fail "drain skips and surfaces malformed entries"
  fi
  receipt="$home/dispatch/receipts/$decision_id.json"
  prompt="$home/dispatch/prompts/$decision_id.md"
  if [ -f "$receipt" ] && [ -f "$prompt" ] && \
      head -1 "$prompt" | grep -q '^Goal:' && \
      "$HOME/.codex/scripts/prompt-handoff-lint" --response "$prompt" >/dev/null && \
      json_assert "$receipt" \
      'd["state"] == "stubbed" and d["target"]["platform"] == "codex" and d["target"]["model"] == "gpt-5.6-sol" and d["target"]["chat"] == "codex:11111111-2222-4333-8444-555555555555" and d["lint"]["state"] == "passed" and d["attempts"] == 1 and d["stubbed"] is True'; then
    pass "stub sender writes linted prompt and receipt"
  else
    fail "stub sender writes linted prompt and receipt"
  fi
  [ ! -e "$queue" ] && pass "successful stub receipt drains queue" || fail "successful stub receipt drains queue"

  # A receipt is the idempotency key even if a duplicate queue file reappears.
  cp "$TMP/queue-copy.json" "$queue"
  receipt_hash="$(shasum -a 256 "$receipt" | awk '{print $1}')"
  if MISSION_CONTROL_HOME="$home" DISPATCH_TEMPLATES_DIR="$ROOT/dispatch/templates" \
      "$RUNNER" >"$TMP/idempotent.json" && json_assert "$TMP/idempotent.json" \
      'd["processed"] == 0 and d["skipped_receipt"] == ["'"$decision_id"'.json"]' && \
      [ "$receipt_hash" = "$(shasum -a 256 "$receipt" | awk '{print $1}')" ]; then
    pass "receipt existence makes duplicate drain idempotent"
  else
    fail "receipt existence makes duplicate drain idempotent"
  fi
  rm -f "$queue"

  # A broken template must hold, persist the receipt, and leave the queue.
  held_id="decision:eeeeeeeeeeeeeeeeeeeeeeee"
  mkdir -p "$TMP/bad-templates" "$home/dispatch/queue"
  cat >"$TMP/bad-templates/codex.md" <<'EOF'
Goal: {{goal}}
Model: {{model}}
Reasoning: {{reasoning}}
EOF
  python3 - "$home/dispatch/queue/$held_id.json" "$held_id" "$ROOT" <<'PY'
import json, sys
path, did, repo = sys.argv[1:]
json.dump({"decision_id":did,"decision_text":"Continue work","option_number":1,
  "option_text":"Continue","source_chat":None,"repo":repo,"severity":"normal",
  "answered_at":"2026-07-13T16:00:00Z"}, open(path,"w",encoding="utf-8"))
PY
  if MISSION_CONTROL_HOME="$home" DISPATCH_TEMPLATES_DIR="$TMP/bad-templates" \
      "$RUNNER" >"$TMP/held-run.json" && \
      [ -f "$home/dispatch/queue/$held_id.json" ] && \
      json_assert "$home/dispatch/receipts/$held_id.json" \
      'd["state"] == "held-lint" and d["lint"]["state"] == "failed" and d["stubbed"] is True'; then
    pass "lint failure holds receipt and queue"
  else
    fail "lint failure holds receipt and queue"
  fi

  # Queue publication is best-effort after the answer transaction commits.
  fail_home="$TMP/home-queue-failure"
  fail_sid="22222222-3333-4444-8555-666666666666"
  write_feeds "$fail_home" "$fail_sid" false "$ROOT"
  fail_created="$(create_decision "$fail_home" "$fail_sid")" || fail_created=""
  fail_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$fail_created" 2>/dev/null || true)"
  MISSION_CONTROL_HOME="$fail_home" "$DECISIONS" status --json >"$fail_home/data/decisions.json"
  printf 'not a directory\n' >"$fail_home/dispatch"
  if MISSION_CONTROL_HOME="$fail_home" REPO_ROOT="$ROOT" DECISION_ALERT_AUTO=0 \
      "$DASHBOARD" decide answer "$fail_id" 1 >"$TMP/fail-answer.out" 2>"$TMP/fail-answer.err" && \
      [ -f "$fail_home/answers/$fail_id.json" ] && \
      grep -q 'dispatch queue failed' "$TMP/fail-answer.err"; then
    pass "dispatch queue failure preserves and surfaces answer"
  else
    fail "dispatch queue failure preserves and surfaces answer"
  fi

  # Collector adds receipt state to decision feed objects only.
  feed_home="$TMP/home-feed"
  feed_sid="33333333-4444-4555-8666-777777777777"
  write_feeds "$feed_home" "$feed_sid" false "$ROOT"
  feed_created="$(create_decision "$feed_home" "$feed_sid" git)" || feed_created=""
  feed_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["decision"]["id"])' "$feed_created" 2>/dev/null || true)"
  mkdir -p "$feed_home/dispatch/receipts"
  python3 - "$feed_home/dispatch/receipts/$feed_id.json" "$feed_id" <<'PY'
import json, sys
json.dump({"decision_id":sys.argv[2],"state":"stubbed","route":"new-chat",
  "target":{"platform":"codex","model":"gpt-5.6-sol","chat":None},
  "prompt_path":"/synthetic/prompt.md","lint":{"state":"passed"},
  "routing_reason":"preferred platform has headroom","attempts":1,"stubbed":True},
  open(sys.argv[1],"w",encoding="utf-8"))
PY
  if MISSION_CONTROL_HOME="$feed_home" REPO_ROOT="$ROOT" DECISION_ALERT_AUTO=0 \
      "$DASHBOARD" collect --force decisions >/dev/null && \
      python3 - "$feed_home/data/decisions.json" "$feed_id" <<'PY'
import json, sys
d=json.load(open(sys.argv[1],encoding="utf-8")); did=sys.argv[2]
row=next(item for item in d["data"]["pinned"] if item["id"]==did)
assert row["dispatch"]["state"]=="stubbed"
assert row["dispatch"]["target_platform"]=="codex"
assert row["dispatch"]["target_model"]=="gpt-5.6-sol"
PY
  then
    pass "decisions collector attaches receipt fields"
  else
    fail "decisions collector attaches receipt fields"
  fi
}

if [ "${1:-}" != "--e2e-only" ]; then
  run_router_truth_table
fi
run_end_to_end

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
