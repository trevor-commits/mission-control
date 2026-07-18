# Rollup-answer verification

## Current candidate

- Code/test repair commit: `34687c9`.
- Final branch head: pending records commit and fresh final audit.
- Environment: hermetic temporary Mission Control homes/stores, synthetic feeds, fake senders, and loopback-only fixtures.

## Evidence

| Gate | Result | Receipt |
|---|---|---|
| Audit-repair red/green | RED 5 failures + 2 errors; GREEN 14/14 | `records/evidence/rollup-answer-audit-repair-red-green.txt` |
| Authoritative verifier | `SUITES PASS=23 FAIL=0` | `records/evidence/rollup-answer-audit-repair-full-green.txt` |
| Browser | 253 assertions | full-green receipt |
| Strict OpenSpec | 2 passed, 0 failed | full-green receipt |
| Source artifacts / syntax | pass | full-green receipt |
| Final same-model/max audit | pending | `records/rollup-answer-independent-codex-audit.md` |

## Claims and limits

- Confirmed: strict targeting, pending suppression/visibility, exact consumption, deterministic digest replay, fd-bound publication, quarantine, strict feed refresh, and no-send behavior are exercised in hermetic tests.
- Confirmed: no dependency or schema migration was introduced.
- Did not verify: final audit, hosted PR checks, merge, install, deploy, provider delivery, or live-store behavior.
