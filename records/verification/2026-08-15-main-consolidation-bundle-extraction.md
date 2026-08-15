# Main consolidation bundle extraction — 2026-08-15

Status: PASS

The private recovery bundle has SHA-256 `47be14743e935419cd8a570d0acf2c952c96e5162ea6cab5249118912fab0a17` in both retained copies.

A temporary bare object database received the bundle through `git bundle unbundle`. It contained no `refs/heads/*` after extraction and created no worktree.

Recovery probe:

- tag: `archive/consolidation-20260815/snapshot/unified-health-d37d8e672e11`
- peeled commit: `d37d8e672e117514397866dafba9a61ea2d20a0c`
- recovered path: `scripts/resource-health`
- recovered blob: `268278eb6912deb5d7cbd5d90545a417459a0d7f`
- result: PASS

The same extraction also resolved private-only commit `d9f1a33b4a12b4831264ee3052ce73b0880d6b36`. That chain remains excluded from public tags, `main`, and every push because its history contains credential-shaped fixture content.
