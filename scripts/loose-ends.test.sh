#!/bin/bash
# loose-ends.test.sh — the one runnable check for scripts/loose-ends (fixture-backed self-test).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/loose-ends" --self-test
# CLI surface: a missing listing must fail closed, not guess.
if MISSION_CONTROL_HOME="$(mktemp -d)" python3 "$ROOT/scripts/loose-ends" show 1 >/dev/null 2>&1; then
  echo "FAIL: show without a listing should exit non-zero" >&2
  exit 1
fi
echo "loose-ends.test.sh: ok"
