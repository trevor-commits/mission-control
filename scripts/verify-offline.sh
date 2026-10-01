#!/bin/bash
# Portable verifier: shell/Python/Node suites without browser or Swift panel compile gates.
# Matches what Linux cloud agents and quick local iteration need once CONTRIBUTING deps are installed.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export REPO_ROOT="$ROOT"
export PYTHONDONTWRITEBYTECODE=1
export VERIFY_OFFLINE=1
if [ -d "$ROOT/node_modules/.bin" ]; then
  PATH="$ROOT/node_modules/.bin:$PATH"
fi

if ! "$ROOT/scripts/check-verify-prerequisites.sh" offline; then
  printf 'Install the missing offline prerequisites (see CONTRIBUTING.md), then retry.\n' >&2
  exit 1
fi

exec /bin/bash "$ROOT/scripts/verify.sh"
