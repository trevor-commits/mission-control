#!/bin/bash
# One authoritative, dependency-light verification path for Mission Control.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export REPO_ROOT="$ROOT"
export PYTHONDONTWRITEBYTECODE=1
PASS=0
FAIL=0

run() {
  local label="$1"; shift
  printf '\n== %s ==\n' "$label"
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAILED: %s\n' "$label" >&2
  fi
}

self_test() {
  local t rc
  t="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "$t/pass"
  printf '#!/bin/sh\nexit 7\n' > "$t/fail"
  chmod +x "$t/pass" "$t/fail"
  PASS=0; FAIL=0
  run "self-pass" "$t/pass"
  run "self-fail" "$t/fail"
  rc=0; [ "$PASS" -eq 1 ] && [ "$FAIL" -eq 1 ] || rc=1
  rm -rf "$t"
  [ "$rc" -eq 0 ] || return "$rc"
  printf 'verify self-test: aggregator retained the failing result\n'
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi
if [ $# -ne 0 ]; then
  echo "usage: scripts/verify.sh [--self-test]" >&2
  exit 2
fi

cd "$ROOT" || exit 1
run "verify aggregator self-test" /bin/bash scripts/verify.sh --self-test
run "automation status" /bin/bash scripts/automation-status.test.sh
run "chat graph" /bin/bash scripts/chat-graph.test.sh
run "dashboard" env REPO_ROOT="$ROOT" /bin/bash scripts/dashboard.test.sh --require-shell
run "decision alert" /bin/bash scripts/decision-alert.test.sh
run "rollup answer" python3 scripts/rollup-answer.test.py
run "ER-134 usability" /bin/bash scripts/er134-usability.test.sh
run "loose-end runner" /bin/bash scripts/loose-end-runner.test.sh
run "shared Mission Control policy" /bin/bash scripts/mission-control-common.test.sh
run "Morning Brief" /bin/bash scripts/morning-brief.test.sh
run "Morning Brief proof harvester" scripts/harvest-morning-brief-proof --self-test
run "Morning Brief delivery" /bin/bash scripts/morning-brief-delivery.test.sh
run "Morning Brief deadman" /bin/bash scripts/morning-brief-deadman.test.sh
run "Morning Brief sender" python3 scripts/morning-brief-deadman-sender.test.py
run "outcome coverage" /bin/bash scripts/outcome-coverage.test.sh
run "outcome extractor" /bin/bash scripts/outcome-extractor.test.sh
run "usage snapshot" /bin/bash scripts/usage-snapshot.test.sh
run "dashboard browser" node scripts/dashboard-browser.test.js
run "unfinished-work scanner" scripts/scan-unfinished-work --self-test
run "OpenSpec strict" openspec validate --all --strict
run "Python syntax" python3 -c 'import pathlib; files=["scripts/chat-graph","scripts/decision-alert","scripts/mission_control_common.py","scripts/outcome_extractor.py","scripts/compose-decision-prompt.py","scripts/harvest-morning-brief-proof"]; [compile(pathlib.Path(p).read_text(),p,"exec") for p in files]'
run "shell syntax" /bin/bash -n scripts/dashboard scripts/*.test.sh scripts/verify.sh

printf '\n====\nSUITES PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
