#!/bin/bash
# Report whether the local toolchain matches what scripts/verify.sh expects.
# Usage: scripts/check-verify-prerequisites.sh [full|offline]
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-full}"
FAIL=0

note() { printf '%s\n' "$*"; }
ok() { note "ok: $*"; }
missing() { note "missing: $*" >&2; FAIL=1; }

python_floor() {
  python3 - <<'PY'
import sys
floor = (3, 11)
if sys.version_info < floor:
    print("Python %d.%d+ required; found %d.%d" % (
        *floor, sys.version_info.major, sys.version_info.minor), file=sys.stderr)
    raise SystemExit(1)
PY
}

if python_floor; then
  ok "python3 $(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
else
  missing "python3 (3.11+)"
fi

if command -v node >/dev/null 2>&1; then
  ok "node $(node -p 'process.versions.node')"
else
  missing "node (CI pins Node 22; see .node-version)"
fi

if command -v shellcheck >/dev/null 2>&1; then
  ok "shellcheck $(shellcheck --version | awk '/version:/{print $2; exit}')"
else
  missing "shellcheck (macOS CI: brew install shellcheck; Debian/Ubuntu: apt install shellcheck)"
fi

openspec_bin=""
if command -v openspec >/dev/null 2>&1; then
  openspec_bin="$(command -v openspec)"
elif [ -x "$ROOT/node_modules/.bin/openspec" ]; then
  openspec_bin="$ROOT/node_modules/.bin/openspec"
fi
if [ -n "$openspec_bin" ]; then
  ok "openspec $("$openspec_bin" --version 2>/dev/null || echo '(version unknown)')"
else
  missing "openspec CLI (@fission-ai/openspec@1.5.0 — see CONTRIBUTING.md)"
fi

playwright_ok() {
  if [ -n "${MISSION_CONTROL_PLAYWRIGHT:-}" ] && node -e "require(process.env.MISSION_CONTROL_PLAYWRIGHT)" 2>/dev/null; then
    ok "playwright (MISSION_CONTROL_PLAYWRIGHT)"
    return 0
  fi
  if node -e "require('playwright')" 2>/dev/null; then
    ok "playwright (node module on NODE_PATH or global)"
    return 0
  fi
  local vendor="$ROOT/node_modules/playwright"
  if [ -f "$vendor/package.json" ] && MISSION_CONTROL_PLAYWRIGHT="$vendor" node -e "require(process.env.MISSION_CONTROL_PLAYWRIGHT)" 2>/dev/null; then
    ok "playwright ($vendor)"
    return 0
  fi
  return 1
}

if [ "$PROFILE" = offline ]; then
  note "profile: offline (browser/Swift suites skipped by scripts/verify-offline.sh)"
else
  note "profile: full (matches .github/workflows/verify.yml on macOS)"
  if playwright_ok; then
    :
  else
    missing "playwright@1.62.0 (npm install --no-save --no-package-lock playwright@1.62.0; set MISSION_CONTROL_PLAYWRIGHT if needed)"
  fi
  chrome_candidates=(
    "${MISSION_CONTROL_CHROME:-}"
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    /usr/local/bin/google-chrome
    /usr/bin/google-chrome
    /usr/bin/chromium
    /usr/bin/chromium-browser
  )
  chrome_found=""
  for candidate in "${chrome_candidates[@]}"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && chrome_found="$candidate" && break
  done
  if [ -n "$chrome_found" ]; then
    ok "chrome ($chrome_found)"
  else
    missing "Google Chrome (set MISSION_CONTROL_CHROME or install Chrome/Chromium)"
  fi
  if command -v swiftc >/dev/null 2>&1; then
    ok "swiftc $(swiftc --version 2>/dev/null | head -1)"
  else
    missing "swiftc (Xcode / Swift toolchain — macOS panel compile suites)"
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  note "prerequisites: PASS ($PROFILE)"
else
  note "prerequisites: FAIL ($PROFILE) — install missing tools, then rerun"
fi
exit "$FAIL"
