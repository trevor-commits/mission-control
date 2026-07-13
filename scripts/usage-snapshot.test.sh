#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="$SCRIPT_DIR/usage-snapshot"

PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

new_env() {
  T="$(mktemp -d)"
  mkdir -p "$T/codex" "$T/bin"
  cat > "$T/bin/claude-glm" <<'EOF'
#!/bin/sh
exit 0
EOF
  cat > "$T/bin/hermes" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$T/bin/claude-glm" "$T/bin/hermes"
  EXPIRES="$(date -v+1d +%Y-%m-%d)"
  cat > "$T/credits.json" <<EOF
{"credits":[{"provider":"codex","kind":"weekly","count":1,"expires":"$EXPIRES"}]}
EOF
}

c1() {
  new_env
  local marker="$T/pwned"
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
  USAGE_NOTIFY_CMD="/bin/echo ; touch $marker" \
    /bin/bash "$USAGE" --no-ccusage >/dev/null 2>"$T/err"
  if [ ! -e "$marker" ] \
     && grep -q "notify failed" "$T/err" \
     && ! ls "$T/state"/.credit-alert-* >/dev/null 2>&1; then
    ok "notify command shell metacharacters are rejected without stamping"
  else
    no "notify command metacharacters were not rejected safely"
  fi
}

c2() {
  new_env
  cat > "$T/bin/notify" <<'EOF'
#!/bin/sh
printf '%s\n' "$#" "$@" > "$NOTIFY_CAPTURE"
EOF
  chmod +x "$T/bin/notify"
  NOTIFY_CAPTURE="$T/notify.out" \
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
  USAGE_NOTIFY_CMD="$T/bin/notify --fixed" \
    /bin/bash "$USAGE" --no-ccusage >/dev/null 2>"$T/err"
  if [ -s "$T/notify.out" ] \
     && [ "$(sed -n '1p' "$T/notify.out")" = "2" ] \
     && grep -q '^--fixed$' "$T/notify.out" \
     && grep -q '^AI credits: USE IT OR LOSE IT' "$T/notify.out"; then
    ok "notify command receives fixed argv plus one advice message"
  else
    no "notify command argv/message contract failed"
  fi
}

c3() {
  new_env
  cat > "$T/bin/npx" <<'EOF'
#!/bin/sh
printf 'argc=%s\n' "$#" >> "$NPX_CAPTURE"
for arg in "$@"; do printf 'arg=%s\n' "$arg" >> "$NPX_CAPTURE"; done
printf '%s\n' '--' >> "$NPX_CAPTURE"
case " $* " in
  *" blocks "*) printf '%s\n' '{"blocks":[]}' ;;
  *" weekly "*) printf '%s\n' '{"weekly":[]}' ;;
  *) exit 64 ;;
esac
EOF
  chmod +x "$T/bin/npx"
  NPX_CAPTURE="$T/npx.out" \
  PATH="$T/bin:$PATH" \
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" >/dev/null 2>"$T/err"
  cat > "$T/npx.expected" <<'EOF'
argc=6
arg=-y
arg=ccusage@20.0.17
arg=blocks
arg=--json
arg=--active
arg=--offline
--
argc=5
arg=-y
arg=ccusage@20.0.17
arg=weekly
arg=--json
arg=--offline
--
EOF
  if cmp -s "$T/npx.expected" "$T/npx.out"; then
    ok "ccusage execution is version-pinned and offline"
  else
    no "ccusage execution drifted from the pinned offline contract"
  fi
}

c5() {
  new_env
  mkdir -p "$T/codex/2026/07/13"
  local now future
  now=$(date +%s); future=$((now + 3600))
  cat > "$T/codex/2026/07/13/rollout-test.jsonl" <<EOF
{"payload":{"rate_limits":{"primary":{"used_percent":88,"window_minutes":10080,"resets_at":$future},"secondary":{"used_percent":22,"window_minutes":300,"resets_at":$future},"plan_type":"test"}}}
EOF
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out"
  if jq -e '.providers[] | select(.provider=="codex" and .window=="5h") | .used_pct==22' "$T/out" >/dev/null \
     && jq -e '.providers[] | select(.provider=="codex" and .window=="weekly") | .used_pct==88' "$T/out" >/dev/null; then
    ok "Codex rate windows are mapped by duration, not transport slot"
  else
    no "Codex primary/secondary reversal mislabeled rate windows"
  fi
}

c6() {
  new_env
  mkdir -p "$T/codex/2026/07/13"
  local now future
  now=$(date +%s); future=$((now + 3600))
  cat > "$T/codex/2026/07/13/rollout-test.jsonl" <<EOF
{"payload":{"rate_limits":{"primary":{"used_percent":88,"window_minutes":10080,"resets_at":$future},"secondary":null,"plan_type":"test"}}}
EOF
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out"
  if jq -e '.providers[] | select(.provider=="codex" and .window=="5h") | .used_pct==null and .confidence=="unknown"' "$T/out" >/dev/null \
     && jq -e '.providers[] | select(.provider=="codex" and .window=="weekly") | .used_pct==88 and .confidence=="live"' "$T/out" >/dev/null; then
    ok "an omitted Codex window stays explicit instead of borrowing another slot"
  else
    no "an omitted Codex window was mislabeled or hidden"
  fi
}

c4() {
  new_env
  cat > "$T/bin/npx" <<'EOF'
#!/bin/sh
exit 42
EOF
  chmod +x "$T/bin/npx"
  NPX_CAPTURE="$T/npx.out" \
  PATH="$T/bin:$PATH" \
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" >"$T/out" 2>"$T/err"
  local rc=$?
  if [ "$rc" -eq 1 ] \
     && jq -e '[.providers[] | select(.provider=="claude")] | length == 2 and all(.health=="down" and .confidence=="unknown")' "$T/out" >/dev/null \
     && jq -e '[.providers[] | select(.provider=="claude") | .notes] | all(contains("failed or returned invalid JSON"))' "$T/out" >/dev/null; then
    ok "ccusage failures are observable and make the snapshot nonzero"
  else
    no "ccusage failure was reported as healthy or exited zero"
  fi
}

c7() {
  new_env
  mkdir -p "$T/codex/2026/07/13"
  cat > "$T/codex/2026/07/13/rollout-test.jsonl" <<'EOF'
{"payload":{"rate_limits":{"primary":{"used_percent":-50,"window_minutes":300,"resets_at":1e300},"secondary":{"used_percent":101,"window_minutes":10080,"resets_at":2000000000},"plan_type":"test"}}}
EOF
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
  local rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$T/err" ] \
     && jq -e '[.providers[] | select(.provider=="codex")] | length==2 and all(.used_pct==null and .confidence=="unknown" and .health=="down")' "$T/out" >/dev/null; then
    ok "impossible Codex percentages and reset epochs fail closed without dropping rows"
  else
    no "malformed numeric Codex windows escaped validation or erased rows"
  fi
}

c8() {
  new_env
  cat > "$T/bin/npx" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >> "$NPX_PID_LOG"
trap '' TERM
while :; do sleep 30; done
EOF
  chmod +x "$T/bin/npx"
  local start elapsed rc leaked=0 pid
  start=$(date +%s)
  NPX_PID_LOG="$T/npx-pids" \
  NPX_BIN="$T/bin/npx" \
  CCUSAGE_TIMEOUT_SECONDS=1 \
  USAGE_SNAPSHOT_DIR="$T/state" \
  USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" \
  CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" \
  HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" >"$T/out" 2>"$T/err"
  rc=$?; elapsed=$(( $(date +%s) - start ))
  while IFS= read -r pid; do
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && leaked=1
  done < "$T/npx-pids"
  if [ "$rc" -eq 1 ] && [ "$elapsed" -le 7 ] && [ "$leaked" -eq 0 ] \
     && jq -e '[.providers[] | select(.provider=="claude")] | length==2 and all(.health=="down")' "$T/out" >/dev/null; then
    ok "hung ccusage commands time out, fail down, and leave no npx process"
  else
    no "hung ccusage work was unbounded, falsely healthy, or leaked a process"
  fi
}

c9() {
  local variant=0 bad_count=0 payload rc
  for payload in \
    '{"primary":{"used_percent":10,"window_minutes":"300","resets_at":2000000000},"secondary":null}' \
    '{"primary":{"used_percent":10,"resets_at":2000000000},"secondary":null}' \
    '{"primary":"broken","secondary":null}'; do
    variant=$((variant+1)); new_env
    mkdir -p "$T/codex/2026/07/13"
    printf '{"payload":{"rate_limits":%s}}\n' "$payload" > "$T/codex/2026/07/13/rollout-test.jsonl"
    USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
      CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
      COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
      /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
    rc=$?
    if [ "$rc" -eq 1 ] && [ ! -s "$T/err" ] \
       && jq -e '[.providers[] | select(.provider=="codex")] | length==2 and all(.health=="down" and .confidence=="unknown")' "$T/out" >/dev/null; then
      bad_count=$((bad_count+1))
    fi
  done
  if [ "$bad_count" -eq 3 ]; then ok "malformed Codex window identifiers fail down instead of looking omitted"
  else no "malformed Codex window metadata escaped structural validation"; fi
}

c10() {
  new_env
  cat > "$T/blocks-bad.json" <<'EOF'
{"blocks":[{"isActive":true,"totalTokens":"many","endTime":7,"burnRate":{"tokensPerMinuteForIndicator":"fast"},"costUSD":{},"models":"not-an-array"}]}
EOF
  cat > "$T/weekly-bad.json" <<'EOF'
{"weekly":[{"totalTokens":"many","totalCost":{}}]}
EOF
  CCUSAGE_BLOCKS_JSON="$T/blocks-bad.json" CCUSAGE_WEEKLY_JSON="$T/weekly-bad.json" \
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" >"$T/out" 2>"$T/err"
  local rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$T/err" ] \
     && jq -e '[.providers[] | select(.provider=="claude")] | length==2 and all(.health=="down" and .confidence=="unknown")' "$T/out" >/dev/null; then
    ok "malformed nested ccusage records fail down without jq leakage"
  else
    no "malformed nested ccusage records were partially accepted or noisy"
  fi
}

c11() {
  new_env
  cat > "$T/bin/glm-hang" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" > "$GLM_PID_FILE"
trap '' TERM
while :; do sleep 30; done
EOF
  chmod +x "$T/bin/glm-hang"
  local start rc elapsed pid leaked=0
  start=$(date +%s)
  GLM_PID_FILE="$T/glm.pid" GLM_TIMEOUT_SECONDS=1 \
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/glm-hang" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage --live-probes >"$T/out" 2>"$T/err"
  rc=$?; elapsed=$(( $(date +%s) - start )); pid=$(cat "$T/glm.pid")
  kill -0 "$pid" 2>/dev/null && leaked=1
  if [ "$rc" -eq 1 ] && [ "$elapsed" -le 4 ] && [ "$leaked" -eq 0 ] \
     && jq -e '.providers[] | select(.provider=="glm") | .health=="down"' "$T/out" >/dev/null; then
    ok "hung GLM doctor is bounded, down, and fully reaped"
  else no "hung GLM doctor blocked, leaked, or stayed healthy"; fi
}

c12() {
  new_env
  cat > "$T/bin/notify-hang" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" > "$NOTIFY_PID_FILE"
trap '' TERM
while :; do sleep 30; done
EOF
  chmod +x "$T/bin/notify-hang"
  local start rc elapsed pid leaked=0
  start=$(date +%s)
  NOTIFY_PID_FILE="$T/notify.pid" NOTIFY_TIMEOUT_SECONDS=1 USAGE_NOTIFY_BIN="$T/bin/notify-hang" \
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
  rc=$?; elapsed=$(( $(date +%s) - start )); pid=$(cat "$T/notify.pid")
  kill -0 "$pid" 2>/dev/null && leaked=1
  if [ "$rc" -eq 1 ] && [ "$elapsed" -le 4 ] && [ "$leaked" -eq 0 ] \
     && grep -q 'notify failed' "$T/err" && ! ls "$T/state"/.credit-alert-* >/dev/null 2>&1; then
    ok "hung notification is bounded, reaped, and leaves a retryable failure"
  else no "hung notification blocked, leaked, or consumed its retry stamp"; fi
}

c13() {
  new_env
  mkdir -p "$T/state/.history.lock"
  touch -t 200001010000 "$T/state/.history.lock"
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage --history >"$T/out" 2>"$T/err"
  local rc=$?
  if [ "$rc" -eq 0 ] && [ -s "$T/state/history.jsonl" ] && [ -f "$T/state/.history.lock" ]; then
    ok "a legacy orphaned lock directory migrates to a kernel lock"
  else no "orphaned history lock did not recover autonomously"; fi
}

c14() {
  new_env
  mkdir -p "$T/readonly"; chmod 500 "$T/readonly"
  USAGE_SNAPSHOT_DIR="$T/readonly" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage --history --html >"$T/out" 2>"$T/err"
  local rc=$?; chmod 700 "$T/readonly"
  if [ "$rc" -ne 0 ] && ! grep -q 'another --history writer' "$T/err" \
     && [ ! -e "$T/readonly/history.jsonl" ] && [ ! -e "$T/readonly/dashboard.html" ]; then
    ok "state-output I/O failure is nonzero and not mislabeled as contention"
  else no "state-output failure stayed green or claimed false contention"; fi
}

c15() {
  new_env
  printf '%s\n' '{"credits":[{"count":"many"}]}' > "$T/credits-bad.json"
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/credits-bad.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
  local rc=$?
  if [ "$rc" -eq 1 ] && jq -e '.providers[] | select(.provider=="credits" and .window=="config") | .health=="down"' "$T/out" >/dev/null; then
    ok "malformed credits configuration is explicit and nonzero"
  else no "malformed credits configuration disappeared silently"; fi
}

c16() {
  local missing ok_count=0
  for missing in primary secondary; do
    new_env; mkdir -p "$T/codex/2026/07/13"
    cat > "$T/codex/2026/07/13/rollout-test.jsonl" <<'EOF'
{"payload":{"rate_limits":{"primary":{"used_percent":11,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":22,"window_minutes":10080,"resets_at":2000000000},"plan_type":"old"}}}
EOF
    if [ "$missing" = "secondary" ]; then
      printf '%s\n' '{"payload":{"rate_limits":{"primary":{"used_percent":33,"window_minutes":300,"resets_at":2000000000},"plan_type":"new-corrupt"}}}' >> "$T/codex/2026/07/13/rollout-test.jsonl"
    else
      printf '%s\n' '{"payload":{"rate_limits":{"secondary":{"used_percent":44,"window_minutes":10080,"resets_at":2000000000},"plan_type":"new-corrupt"}}}' >> "$T/codex/2026/07/13/rollout-test.jsonl"
    fi
    USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
    CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
    COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
      /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
    if [ $? -eq 1 ] && jq -e '[.providers[] | select(.provider=="codex")] | length==2 and all(.health=="down" and .used_pct==null)' "$T/out" >/dev/null; then
      ok_count=$((ok_count+1))
    fi
  done
  if [ "$ok_count" -eq 2 ]; then ok "newest rate event with a missing slot cannot reuse older live values"
  else no "missing transport slot fell back to an older rate event"; fi
}

c17() {
  new_env
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/missing-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/missing-hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
  local rc=$?
  if [ "$rc" -eq 1 ] \
     && jq -e 'any(.providers[]; .provider=="glm" and .health=="down") and any(.providers[]; .provider=="hermes" and .health=="down")' "$T/out" >/dev/null; then
    ok "configured missing provider executables are down and nonzero"
  else no "configured missing provider executables were treated as optional absence"; fi
}

c18() {
  new_env
  mkdir -p "$T/state/.history.lock" "$T/results"
  touch -t 200001010000 "$T/state/.history.lock"
  local i success=0 lines=0 residue=0
  for i in $(seq 1 16); do
    ( USAGE_SNAPSHOT_TESTING=1 USAGE_SNAPSHOT_TEST_HOLD_LOCK_SECONDS=1 \
      USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
      CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
      COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
      /bin/bash "$USAGE" --no-ccusage --history >"$T/results/$i.out" 2>"$T/results/$i.err"; \
      printf '%s\n' "$?" > "$T/results/$i.rc" ) &
  done
  wait
  for i in $(seq 1 16); do [ "$(cat "$T/results/$i.rc")" -eq 0 ] && success=$((success+1)); done
  [ -f "$T/state/history.jsonl" ] && lines=$(wc -l < "$T/state/history.jsonl" | tr -d ' ')
  [ -f "$T/state/.history.lock" ] || residue=1
  if [ "$success" -eq 1 ] && [ "$lines" -eq 1 ] && [ "$residue" -eq 0 ]; then
    ok "high-contention migration permits exactly one kernel-locked writer"
  else no "orphan-lock recovery split into multiple writers or left residue"; fi
}

c19() {
  new_env
  mkdir -p "$T/state/.history.lock/.recovery"
  touch -t 200001010000 "$T/state/.history.lock" "$T/state/.history.lock/.recovery"
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage --history >"$T/out" 2>"$T/err"
  if [ $? -eq 0 ] && [ -s "$T/state/history.jsonl" ] && [ -f "$T/state/.history.lock" ]; then
    ok "crashed legacy recovery marker migrates without stranding history"
  else no "legacy .recovery crash residue permanently blocked history"; fi
}

c20() {
  local variant ok_count=0
  for variant in nonobject future; do
    new_env; mkdir -p "$T/codex/2026/07/13"
    printf '%s\n' '{"payload":{"rate_limits":{"primary":{"used_percent":11,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":22,"window_minutes":10080,"resets_at":2000000000}}}}' > "$T/codex/2026/07/13/rollout-test.jsonl"
    if [ "$variant" = "nonobject" ]; then
      printf '%s\n' '{"payload":{"rate_limits":"corrupt-newest-value"}}' >> "$T/codex/2026/07/13/rollout-test.jsonl"
    else
      touch -t 209901010000 "$T/codex/2026/07/13/rollout-test.jsonl"
    fi
    USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
    CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
    COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
      /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
    if [ $? -eq 1 ] && jq -e '[.providers[] | select(.provider=="codex")] | length==2 and all(.health=="down" and .used_pct==null)' "$T/out" >/dev/null; then
      ok_count=$((ok_count+1))
    fi
  done
  if [ "$ok_count" -eq 2 ]; then ok "newest non-object rates and future rollouts fail closed"
  else no "corrupt newest rate value or future rollout produced live usage"; fi
}

c21() {
  new_env
  cat > "$T/bin/glm-marker" <<EOF
#!/bin/sh
touch "$T/glm-invoked"
exit 99
EOF
  chmod +x "$T/bin/glm-marker"
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/glm-marker" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
  if [ $? -eq 0 ] && [ ! -e "$T/glm-invoked" ] \
     && jq -e 'any(.providers[]; .provider=="glm" and .health=="present" and .source=="binary")' "$T/out" >/dev/null; then
    ok "default scheduled path performs no provider-backed GLM probe"
  else no "default snapshot invoked a model-backed provider probe"; fi
}

c22() {
  new_env
  mkdir -p "$T/state/.history.lock"
  touch -t 209901010000 "$T/state/.history.lock"
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage --history >"$T/out" 2>"$T/err"
  if [ $? -eq 0 ] && [ -s "$T/state/history.jsonl" ] && [ -f "$T/state/.history.lock" ]; then
    ok "future-dated ownerless legacy lock migrates without permanent stranding"
  else no "future legacy lock was misclassified as a permanent live owner"; fi
}

c23() {
  new_env; mkdir -p "$T/codex/2026/07/13"
  printf '%s\n' '{"payload":{"rate_limits":{"primary":{"used_percent":12,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":34,"window_minutes":10080,"resets_at":2000000000}}}}' > "$T/codex/2026/07/13/rollout-test.jsonl"
  printf '%s' '{"payload":{"rate_limits":' >> "$T/codex/2026/07/13/rollout-test.jsonl"
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
  if [ $? -eq 1 ] && jq -e '[.providers[] | select(.provider=="codex")] | length==2 and all(.health=="down" and .used_pct==null)' "$T/out" >/dev/null; then
    ok "truncated newest JSONL record cannot preserve an older live rate event"
  else no "malformed final JSONL reused older Codex usage as live"; fi
}

c24() {
  new_env; mkdir -p "$T/codex/2026/07/13"
  printf '%s\n' '{"payload":{"rate_limits":{"primary":{"used_percent":12,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":34,"window_minutes":10080,"resets_at":2000000000}}}}' > "$T/codex/2026/07/13/rollout-test.jsonl"
  chmod 000 "$T/codex/2026/07/13/rollout-test.jsonl"
  USAGE_SNAPSHOT_DIR="$T/state" USAGE_CREDITS_FILE="$T/missing-credits.json" \
  CODEX_SESSIONS_DIR="$T/codex" CLAUDE_GLM_BIN="$T/bin/claude-glm" \
  COPILOT_DB="$T/missing-copilot.db" HERMES_BIN="$T/bin/hermes" \
    /bin/bash "$USAGE" --no-ccusage >"$T/out" 2>"$T/err"
  local rc=$?; chmod 600 "$T/codex/2026/07/13/rollout-test.jsonl"
  if [ "$rc" -eq 1 ] && jq -e '[.providers[] | select(.provider=="codex")] | length==2 and all(.health=="down" and .used_pct==null)' "$T/out" >/dev/null; then
    ok "unreadable selected rollout fails down instead of looking honestly empty"
  else no "selected rollout read failure returned a green unknown snapshot"; fi
}

c1
c2
c3
c4
c5
c6
c7
c8
c9
c10
c11
c12
c13
c14
c15
c16
c17
c18
c19
c20
c21
c22
c23
c24

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
