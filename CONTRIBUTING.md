# Contributing to Mission Control

Mission Control is a local, offline-first macOS product. This document closes the
**clone → install toolchain → verify** gap for humans and cloud agents working
from a Git checkout.

## Clone and layout

```bash
git clone https://github.com/trevor-commits/mission-control.git
cd mission-control
```

- **Agent entry:** `AGENTS.md` (repo-local governance). Trevor's shared Codex contract
  lives outside this repo at `~/.codex/AGENTS.md`; clones do not need that file to
  run tests.
- **Operator runbook:** `docs/runbooks/mission-control.md` (installed runtime).
- **Design authority:** `docs/MISSION_CONTROL_PLAN.md`.
- **`STATE.md` is generated** and can lag `main`; trust Git and `todo.md` for
  current branch/queue state (`AGENTS.md`).

There is no separate `CONTRIBUTING` workflow beyond this file and the verifier
below. GitHub Actions on `main` and PRs runs the same authoritative check as
local full verify.

**Deep reference:** suite inventory, draft-PR survey, and Linux vs macOS
interpretation: [`docs/verification/clone-to-verify.md`](docs/verification/clone-to-verify.md).

## Verification profiles

| Command | When to use |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh` | **Full matrix** — same as CI on `macos-15` (browser + Swift panel suites). |
| `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify-offline.sh` | **Portable matrix** — skips real-browser and `swiftc` panel compile suites; still runs ShellCheck, OpenSpec strict, and all shell/Python/Node unit suites. |
| `scripts/check-verify-prerequisites.sh full` | Preflight before full verify. |
| `scripts/check-verify-prerequisites.sh offline` | Preflight before offline verify. |

Skip flags (advanced): `VERIFY_SKIP_BROWSER=1`, `VERIFY_SKIP_SWIFT=1`, or
`VERIFY_OFFLINE=1` on `scripts/verify.sh` directly.

Focused suites (faster iteration) remain alongside the aggregator, e.g.
`/bin/bash scripts/dashboard.test.sh`, `node scripts/dashboard-browser.test.js`.

## Toolchain pins (CI parity)

Values below are enforced in `.github/workflows/verify.yml` and
`scripts/ci-workflow.test.py`.

| Tool | Pin / floor | Install notes |
| --- | --- | --- |
| Python | **3.11+** (floor checked in `verify.sh`) | `actions/setup-python` uses 3.11 on CI |
| Node.js | **22** (see `.node-version`) | `actions/setup-node` uses 22 on CI |
| ShellCheck | required | CI: `brew install shellcheck`; Linux: `apt install shellcheck`, or a [portable release binary](https://github.com/koalaman/shellcheck/releases) on `PATH` when apt is unavailable (cloud agents) |
| OpenSpec CLI | **@fission-ai/openspec@1.5.0** | CI: global npm install. Local/agents without global write access: from repo root, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-save --no-package-lock --ignore-scripts @fission-ai/openspec@1.5.0 playwright@1.62.0` (adds `node_modules/.bin/openspec`; `verify-offline.sh` prepends that path). |
| Playwright (client only) | **1.62.0** | Same local install as OpenSpec; export `MISSION_CONTROL_PLAYWRIGHT="$PWD/node_modules/playwright"` if `require('playwright')` fails |
| Google Chrome | system browser | CI uses the `macos-15` image Chrome; Linux: set `MISSION_CONTROL_CHROME` to `google-chrome` or Chromium |
| Swift | `swiftc` | Required for full verify panel compile suites (macOS / Xcode) |
| shasum | vendored cytoscape lock | `dashboard/vendor/cytoscape.min.js.sha256` |

## Survey highlights (clone-to-verify gaps addressed here)

1. **README** listed `scripts/verify.sh` without prerequisites or a Linux/cloud path.
2. **No contributor doc** existed; toolchain pins lived only in workflow YAML.
3. **CI runs on `macos-15` only** — Linux clones failed browser/Swift suites with
   misleading “missing Chrome at macOS path” errors; offline profile and Chrome
   autodetection document the split.
4. **`ci-workflow.test.py`** did not assert OpenSpec/Playwright version pins (now
   covered).
5. **Node version** was implicit in workflow only (now `.node-version`).
6. **Linux dashboard harness** stopped after a handful of checks (GNU `stat` + shell
   function naming); absorbed from draft PR #30 into the reliability branch.
7. **Post-verify bytecode** — accidental `scripts/__pycache__` from nested Python
   imports is purged before the final artifact gate.
8. **Usage snapshot on Linux** — test fixtures use portable calendar dates; the
   collector still uses BSD `date -j` (credit notify + window math). Expect nested
   FAIL in `usage-snapshot.test.sh` on GNU/Linux; see
   [`docs/verification/clone-to-verify.md`](docs/verification/clone-to-verify.md).

### Open draft PRs (2026-10-01 survey)

| PR | Topic | Notes |
| --- | --- | --- |
| [#31](https://github.com/trevor-commits/mission-control/pull/31) | Clone-to-verify | Primary draft; includes this deeper pass |
| [#30](https://github.com/trevor-commits/mission-control/pull/30) | Linux harness | Merged into #31 branch; close after #31 lands |

## Safety (all contributors)

- No secrets in commits; fixtures stay synthetic.
- Do not merge or force-push `main` from automation without operator approval.
- No live customer outreach or production sends from test harnesses.
