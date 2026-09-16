#!/bin/bash
# loose-tree.test.sh — the one runnable check for scripts/loose-tree.
# Fixture-backed: self-test covers the real code paths end-to-end in /tmp;
# the CLI surface checks fail closed; pytest file runs when pytest exists.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/loose-tree" --self-test
# A missing/empty store must produce the green message, not a traceback.
if ! MISSION_CONTROL_HOME="$(mktemp -d)" python3 "$ROOT/scripts/loose-tree" board | grep -q "No loose ends"; then
  echo "FAIL: board with empty store should print the green message" >&2
  exit 1
fi
# json output must be parseable.
MISSION_CONTROL_HOME="$(mktemp -d)" python3 "$ROOT/scripts/loose-tree" json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("version")==1 and d.get("nodes")==[]'
# pytest file runs only where pytest is installed (optional extra signal).
if python3 -c 'import pytest' 2>/dev/null; then
  python3 -m pytest "$ROOT/scripts/loose-tree.test.py" -q
else
  echo "pytest unavailable; self-test is the authoritative check here"
fi
echo "loose-tree.test.sh: ok"
