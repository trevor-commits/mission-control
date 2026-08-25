#!/bin/bash
# One authoritative, dependency-light verification path for Mission Control.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export REPO_ROOT="$ROOT"
export PYTHONDONTWRITEBYTECODE=1
# shellcheck source=scripts/test-temp-root.sh
source "$ROOT/scripts/test-temp-root.sh"
mission_test_temp_init mission-control-verify || exit 1
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

python_floor() {
  python3 - <<'PY'
import sys
floor = (3, 11)
if sys.version_info < floor:
    print("Mission Control requires Python %d.%d+; found %d.%d" % (
        *floor, sys.version_info.major, sys.version_info.minor), file=sys.stderr)
    raise SystemExit(1)
PY
}

source_tree_artifacts() {
  local artifact
  artifact="$(find "$ROOT/scripts" \( -type d -name '__pycache__' -o -type f \( -name '*.pyc' -o -name '*.pyo' \) \) -print -quit)"
  if [ -n "$artifact" ]; then
    printf 'unexpected source-tree artifact: %s\n' "$artifact" >&2
    return 1
  fi
}

python_syntax() {
  python3 - "$ROOT/scripts" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
errors = []
for path in sorted(root.iterdir()):
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    first = text.splitlines()[0] if text else ""
    if path.suffix == ".py" or (first.startswith("#!") and "python" in first):
        try:
            compile(text, str(path), "exec")
        except SyntaxError as exc:
            errors.append("%s:%s:%s: %s" % (
                path, exc.lineno, exc.offset, exc.msg))
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY
}

shell_syntax() {
  local path first
  while IFS= read -r -d '' path; do
    first=""
    IFS= read -r first < "$path" || true
    case "$path:$first" in
      *.sh:*|*:'#!'*bash*) /bin/bash -n "$path" || return 1 ;;
    esac
  done < <(find "$ROOT/scripts" -maxdepth 1 -type f -print0)
}

shellcheck_sources() {
  local path first
  command -v shellcheck >/dev/null 2>&1 || {
    printf 'ShellCheck is required; install shellcheck and retry\n' >&2
    return 1
  }
  while IFS= read -r -d '' path; do
    first=""
    IFS= read -r first < "$path" || true
    case "$path:$first" in
      *.sh:*|*:'#!'*bash*) shellcheck -S error --external-sources "$path" || return 1 ;;
    esac
  done < <(find "$ROOT/scripts" -maxdepth 1 -type f -print0)
}

self_test() {
  local t rc helper regression_root
  t="$(mktemp -d)"
  case "$t" in
    "$MISSION_TEST_TMPDIR"/*) ;;
    *) printf 'verify self-test: bare mktemp escaped %s: %s\n' "$MISSION_TEST_TMPDIR" "$t" >&2; return 1 ;;
  esac
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

  helper="$ROOT/scripts/test-temp-root.sh"
  regression_root="$MISSION_TEST_TMPDIR/helper-regressions"
  mkdir -p "$regression_root/relative/parent" "$regression_root/relative/elsewhere" \
    "$regression_root/replacement"

  # Resolve a relative TMPDIR before the suite later changes directories.
  /bin/bash - "$helper" "$regression_root/relative" <<'BASH' || return 1
set -u
helper=$1
sandbox=$2
cd "$sandbox" || exit 1
TMPDIR=parent
unset MISSION_TEST_TEMP_ROOT MISSION_TEST_TEMP_ROOT_ID \
  MISSION_TEST_TEMP_CLAIM MISSION_TEST_TEMP_CLAIM_ID MISSION_TEST_TEMP_PARENT \
  MISSION_TEST_TEMP_PREFIX MISSION_TEST_TMPDIR
source "$helper"
mission_test_temp_init relative-parent || exit 1
owned=$MISSION_TEST_TEMP_ROOT
cd elsewhere || exit 1
mission_test_temp_cleanup || exit 1
trap - EXIT HUP INT TERM
[[ ! -e "$owned" && ! -L "$owned" ]]
BASH

  # A same-name replacement inserted immediately before cleanup must survive.
  # The original owned root is also retained when post-claim identity differs.
  /bin/bash - "$helper" "$regression_root/replacement" <<'BASH' || return 1
set -u
helper=$1
sandbox=$2
TMPDIR=$sandbox
unset MISSION_TEST_TEMP_ROOT MISSION_TEST_TEMP_ROOT_ID \
  MISSION_TEST_TEMP_CLAIM MISSION_TEST_TEMP_CLAIM_ID MISSION_TEST_TEMP_PARENT \
  MISSION_TEST_TEMP_PREFIX MISSION_TEST_TMPDIR
source "$helper"
mission_test_temp_init replacement-race || exit 1
owned=$MISSION_TEST_TEMP_ROOT
claim=$MISSION_TEST_TEMP_CLAIM
original="$owned.original"
printf 'owned\n' > "$owned/original-sentinel"
mission_test_temp_before_claim() {
  /bin/mv -- "$MISSION_TEST_TEMP_ROOT" "$original" || return 1
  mkdir -m 700 "$MISSION_TEST_TEMP_ROOT" || return 1
  printf 'replacement\n' > "$MISSION_TEST_TEMP_ROOT/replacement-sentinel"
}
if mission_test_temp_cleanup; then
  exit 1
fi
trap - EXIT HUP INT TERM
[[ -f "$original/original-sentinel" ]] || exit 1
[[ -f "$claim/root/replacement-sentinel" ]] || exit 1
/bin/rm -rf -- "$original" "$claim"
BASH
  printf 'verify self-test: temp cleanup preserves replacements and resolves relative TMPDIR\n'
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
run "Python floor (3.11+)" python_floor
run "verify aggregator self-test" /bin/bash scripts/verify.sh --self-test
run "automation status" /bin/bash scripts/automation-status.test.sh
run "chat graph" /bin/bash scripts/chat-graph.test.sh
run "dashboard" env REPO_ROOT="$ROOT" /bin/bash scripts/dashboard.test.sh --require-shell
run "dashboard demo contracts" python3 scripts/dashboard-demo.test.py
run "state-home expansion" python3 scripts/mission-control-home.test.py
run "CI verifier prerequisites" python3 scripts/ci-workflow.test.py
run "decision alert" /bin/bash scripts/decision-alert.test.sh
run "rollup answer" python3 scripts/rollup-answer.test.py
run "decision operation bounds" python3 scripts/decision-bounds.test.py
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
run "self-repair fail-closed" python3 scripts/self-repair --self-test
run "usage snapshot" /bin/bash scripts/usage-snapshot.test.sh
run "usage watch (reset + silence)" python3 scripts/usage-watch --self-test
run "headroom on-demand refresh" python3 scripts/headroom-refresh --self-test
run "attention lane" /bin/bash scripts/attention-lane.test.sh
run "queue admission" python3 scripts/queue_admission.test.py
run "dashboard browser" node scripts/dashboard-browser.test.js
run "panel browser" node scripts/panel-browser.test.js
run "native panel headroom" python3 scripts/mc-panel-headroom.test.py
run "native panel core feeds" python3 scripts/mc-panel-summary.test.py
run "unfinished-work scanner" scripts/scan-unfinished-work --self-test
run "OpenSpec strict" openspec validate --all --strict
run "Python syntax (auto-discovered)" python_syntax
run "shell syntax (auto-discovered)" shell_syntax
run "ShellCheck" shellcheck_sources
run "source tree artifacts" source_tree_artifacts

printf '\n====\nSUITES PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
