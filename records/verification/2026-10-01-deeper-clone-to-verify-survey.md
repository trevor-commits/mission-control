# 2026-10-01 — Deeper clone-to-verify survey (draft-only)

**Scope:** reliability and documentation only. No live external writes, no merge.

## Open draft PRs surveyed

- **PR #31** — clone-to-verify contributor guide, offline verifier, CI pin tests.
- **PR #30** — Linux dashboard harness (`stat` identity, dashboard.test.sh naming).

**Consolidation:** PR #30 changes merged into the PR #31 branch for one draft landing
path. Recommend closing PR #30 after PR #31 lands to avoid duplicate commits.

## Evidence (Linux cloud agent, offline profile)

Cloud agent session: `bc-d9c9a757-d38f-5df4-ac47-5780d11930aa` (2026-10-01).

Commands:

```bash
python3 scripts/ci-workflow.test.py
scripts/check-verify-prerequisites.sh offline
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-save --no-package-lock --ignore-scripts \
  @fission-ai/openspec@1.5.0 playwright@1.62.0
PYTHONDONTWRITEBYTECODE=1 scripts/verify-offline.sh
```

Observed (representative):

- `ci-workflow.test.py` — PASS
- prerequisites offline — PASS (after `apt install shellcheck` + repo-local `npm install` CLIs)
- `verify-offline.sh` — `SKIP=4`; `SUITES PASS=31 FAIL=7` top-level on Linux
  (dashboard `PASS=90 FAIL=5`, ER-134, `mission-control-common`, three Morning Brief
  delivery suites, `usage snapshot` `PASS=25 FAIL=9` nested); macOS install/launchd/Keychain
  and BSD `date -j` inside `scripts/usage-snapshot` drive the gap pattern
- `usage-watch --self-test` — 21 passed; `headroom-refresh --self-test` — 15 passed
- `verify.sh --self-test` — includes portable `mission_test_date_ymd_offset_days` check

## Artifacts

- Deep reference: `docs/verification/clone-to-verify.md`
- Contributor entry: `CONTRIBUTING.md`

## Rollback

Revert the PR branch; no runtime install or scheduler changes involved.
