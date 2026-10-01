# Clone-to-verify (deep reference)

This document supplements `CONTRIBUTING.md` with **CI parity**, **open-draft survey**,
and **how to read verifier output** on non-macOS hosts. It does not change product
runtime behavior.

## Authoritative CI gate

GitHub Actions workflow `.github/workflows/verify.yml`:

- **Runner:** `macos-15` only (no Linux CI matrix today).
- **Command:** `/bin/bash scripts/verify.sh` (full matrix, no skip flags).
- **Concurrency:** one verify run per ref; `cancel-in-progress: true`.
- **Permissions:** `contents: read` only.

Local **full** verify must match that job. Local **offline** verify is a deliberate
subset for Linux cloud agents and quick iteration; a green offline run is **not**
a substitute for macOS CI.

## Verification profiles (summary)

| Profile | Entry | Browser + Swift | CI equivalent |
| --- | --- | --- | --- |
| Full | `scripts/verify.sh` | Required | Yes (`macos-15`) |
| Offline | `scripts/verify-offline.sh` or `VERIFY_OFFLINE=1` | Skipped (4 suites) | No |
| Preflight | `scripts/check-verify-prerequisites.sh full\|offline` | Checks only | — |

Toolchain pins live in `CONTRIBUTING.md` and are asserted by
`scripts/ci-workflow.test.py` (OpenSpec `1.5.0`, Playwright client `1.62.0`,
Node `22`, Python floor `3.11+`, SHA-pinned Actions, offline script present).

## Suite inventory (aggregator order)

`scripts/verify.sh` runs suites in a fixed order. Offline profile **skips** the
rows marked “offline skip”.

| # | Label | Offline skip | macOS-only contracts (typical) |
| --- | --- | --- | --- |
| — | source tree artifacts (pre) | | no `__pycache__` / `.pyc` under `scripts/` |
| 1 | Python floor | | |
| 2 | verify self-test | | temp-root + GNU `stat` identity |
| 3–29 | shell/Python unit suites | | see suite file for launchd/Keychain/plist |
| 30 | dashboard browser | yes | real Chrome file:// gate |
| 31 | panel browser | yes | real Chrome file:// gate |
| 32 | native panel headroom | yes | `swiftc` compile |
| 33 | native panel core feeds | yes | `swiftc` compile |
| 34+ | scanner, jobs, vendor, OpenSpec, syntax, ShellCheck | | |
| — | source tree artifacts (post) | | same as pre-suite |

**Usage / headroom-related suites** (always run in offline profile):

- `usage snapshot` — `scripts/usage-snapshot.test.sh` (ccusage pin + JSON shape).
- `usage watch (reset + silence)` — `scripts/usage-watch --self-test`.
- `headroom on-demand refresh` — `scripts/headroom-refresh --self-test`.

These are lightweight and do not call external provider APIs in self-test mode.
Some cases assume macOS notification or Keychain semantics; on Linux they may
contribute to suite FAIL counts inside `usage-snapshot.test.sh` even when the
harness itself is healthy.

## Open draft PR survey (2026-10-01)

Survey before this pass (no merges performed by automation):

| PR | Branch | Focus | Disposition in this pass |
| --- | --- | --- | --- |
| [#31](https://github.com/trevor-commits/mission-control/pull/31) | `cursor/reliability-docs-verify-ba49` | `CONTRIBUTING.md`, offline verify, CI pin tests, Linux Chrome autodetect | **Extended** — deep doc + Linux harness merge |
| [#30](https://github.com/trevor-commits/mission-control/pull/30) | `cursor/linux-test-harness-stat-4de4` | GNU `stat` temp identity, dashboard.test.sh bash naming | **Absorbed** — merged into #31 branch; close #30 to avoid duplicate landings |

Other open PRs (non-draft) were out of scope for this reliability/docs burn.

### Gaps closed or documented here

1. **Harness no-op on Linux** — dashboard suite stopped after ~6 checks (function
   names shadowing `bash`/`env`; multiline GNU `stat -f` stdout). Fixed on merged
   harness branch; offline verify now exercises the full case block (~90 checks).
2. **Missing contributor path** — `CONTRIBUTING.md` + preflight script + README
   pointers.
3. **Implicit Node pin** — `.node-version` (`22`).
4. **CI drift guard** — `ci-workflow.test.py` asserts OpenSpec/Playwright pins and
   contributor artifacts.
5. **Misleading Chrome errors** — browser tests autodetect Linux Chrome/Chromium;
   offline profile skips them with explicit SKIP lines.
6. **Agent entry on cloud** — `AGENTS.md` states repo docs are authoritative when
   `~/.codex/AGENTS.md` is absent.
7. **Post-suite bytecode hygiene** — verify removes accidental `scripts/__pycache__`
   trees before the final artifact gate (suites should still run with
   `PYTHONDONTWRITEBYTECODE=1`).

## Verify steps (copy/paste)

### 1. Preflight

```bash
scripts/check-verify-prerequisites.sh offline   # Linux / cloud
scripts/check-verify-prerequisites.sh full      # before full matrix on macOS
```

### 2. Install repo-local CLI deps (no global npm write required)

```bash
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-save --no-package-lock --ignore-scripts \
  @fission-ai/openspec@1.5.0 playwright@1.62.0
```

### 3. Portable matrix (Linux cloud agent)

```bash
PYTHONDONTWRITEBYTECODE=1 scripts/verify-offline.sh
```

Expect **`SKIP=4`** (browser + Swift panel suites). Expect **`FAIL>0`** on Linux
for macOS install/launchd/Keychain/Morning-Brief delivery contracts inside nested
suites (dashboard `FAIL=5`, ER-134 panel build, Morning Brief delivery/deadman,
parts of `usage-snapshot`). That pattern is **environment gap**, not a silent harness
no-op. Release truth remains **`SUITES FAIL=0`** on `macos-15` CI.

### 4. Full matrix (macOS, CI parity)

```bash
PYTHONDONTWRITEBYTECODE=1 scripts/verify.sh
```

### 5. Focused iteration

```bash
REPO_ROOT="$PWD" /bin/bash scripts/dashboard.test.sh --require-shell
python3 scripts/ci-workflow.test.py
/bin/bash scripts/verify.sh --self-test
```

## Reading aggregator output

- **`PASS` / `FAIL`** — one line per top-level suite in `verify.sh`.
- **`SKIP`** — offline or explicit `VERIFY_SKIP_*` (skipped suites count as success
  for the aggregator).
- Nested **`PASS=n FAIL=m`** inside a suite (e.g. dashboard) — failure of that suite
  if `m>0`, even when most cases passed.

## Safety (unchanged)

- No secrets in commits; synthetic fixtures only.
- No live external writes from this documentation pass.
- Do not merge or force-push `main` from automation without operator approval.
