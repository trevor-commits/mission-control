#!/usr/bin/env bash
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
    bash "$USAGE" --no-ccusage >/dev/null 2>"$T/err"
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
    bash "$USAGE" --no-ccusage >/dev/null 2>"$T/err"
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
printf '%s\n' "$*" >> "$NPX_CAPTURE"
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
    bash "$USAGE" >/dev/null 2>"$T/err"
  if [ "$(wc -l < "$T/npx.out" | tr -d ' ')" = "2" ] \
     && grep -Fxq -- '-y ccusage@20.0.17 blocks --json --active --offline' "$T/npx.out" \
     && grep -Fxq -- '-y ccusage@20.0.17 weekly --json --offline' "$T/npx.out" \
     && ! grep -q '@latest' "$T/npx.out"; then
    ok "ccusage execution is version-pinned and offline"
  else
    no "ccusage execution drifted from the pinned offline contract"
  fi
}

c1
c2
c3

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
