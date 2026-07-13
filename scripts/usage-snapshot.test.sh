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
  chmod +x "$T/bin/claude-glm"
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
  HERMES_BIN="$T/missing-hermes" \
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
  HERMES_BIN="$T/missing-hermes" \
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
  HERMES_BIN="$T/missing-hermes" \
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
  HERMES_BIN="$T/missing-hermes" \
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
  HERMES_BIN="$T/missing-hermes" \
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
  HERMES_BIN="$T/missing-hermes" \
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
  HERMES_BIN="$T/missing-hermes" \
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
  HERMES_BIN="$T/missing-hermes" \
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

c1
c2
c3
c4
c5
c6
c7
c8

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
