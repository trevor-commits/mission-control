# 2026-10-01 — Deeper clone-to-verify survey (draft-only)

**Scope:** reliability and documentation only. No live external writes, no merge.

## Open draft PRs surveyed

- **PR #31** — clone-to-verify contributor guide, offline verifier, CI pin tests.
- **PR #30** — Linux dashboard harness (`stat` identity, dashboard.test.sh naming).

**Consolidation:** PR #30 changes merged into the PR #31 branch for one draft landing
path. Recommend closing PR #30 after PR #31 lands to avoid duplicate commits.

## Evidence (Linux cloud agent, offline profile)

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
- prerequisites offline — PASS
- `verify-offline.sh` — `SKIP=4`; dashboard suite runs full case block (`PASS=90 FAIL=5` nested);
  top-level FAIL from macOS-only install/Morning Brief/usage-snapshot contracts;
  post-suite `__pycache__` artifact gate addressed in verify hygiene commit.

## Artifacts

- Deep reference: `docs/verification/clone-to-verify.md`
- Contributor entry: `CONTRIBUTING.md`

## Rollback

Revert the PR branch; no runtime install or scheduler changes involved.
