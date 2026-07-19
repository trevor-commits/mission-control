# Rollup-answer verification

## Current candidate

- Code/test repair commit: `34687c9`.
- Second-audit repair commit: `8613d25`.
- Third-audit occupied-parent repair commit: `bfaf10b`.
- Fourth-audit local-view coherence repair: `0ce6d3d7704a8e305159cdbd78965bd34f1b8a02`.
- Fourth-repair receipt head rejected by the next audit: `8b8fa772336239eab812b38e2b152e69dce65a96`.
- Fifth-audit receipt/entry repair: pending code commit.
- Final branch head: pending authoritative gate receipt and fresh exact-head re-audit.
- Environment: hermetic temporary Mission Control homes/stores, synthetic feeds, fake senders, and loopback-only fixtures.

## Evidence

| Gate | Result | Receipt |
|---|---|---|
| Audit-repair red/green | RED 5 failures + 2 errors; GREEN 14/14 | `records/evidence/rollup-answer-audit-repair-red-green.txt` |
| Authoritative verifier | `SUITES PASS=23 FAIL=0` | `records/evidence/rollup-answer-audit-repair-full-green.txt` |
| Browser | 253 assertions | full-green receipt |
| Strict OpenSpec | 2 passed, 0 failed | full-green receipt |
| Source artifacts / syntax | pass | full-green receipt |
| Fourth frozen-head audit | `NOT MERGE-READY`: P1 persisted Morning Brief/public feed stale success; P2 stale records | `records/rollup-answer-independent-codex-audit.md` |
| Second-audit red/green | RED 3 rollup + 1 Home + 1 panel; GREEN rollup 17/17, seven tabs, ER-134 59/0 | `records/evidence/rollup-answer-final-audit-red-green.txt` |
| Third-audit occupied-parent red/green | RED invalid canonical remained visible; GREEN targeted + rollup 18/18 | `records/evidence/rollup-answer-occupied-parent-red-green.txt` |
| Fourth-audit local-view red/green | RED persisted Morning Brief unchanged after zero plus two receipt-state holes; GREEN rollup 23/23, Morning Brief all pass, dashboard 67/0, ER-134 59/0 | `records/evidence/rollup-answer-morning-brief-coherence-red-green.txt` |
| Fourth-repair authoritative verifier | `SUITES PASS=23 FAIL=0`; rollup 23/23; dashboard 67/0; ER-134 59/0; usage 24/0; browser 253; OpenSpec 2/0; artifact predicate pass | `records/evidence/rollup-answer-morning-brief-coherence-full-green.txt` |
| Fifth frozen-head audit | `NOT MERGE-READY`: P1 receipt shape did not bind delivered bytes; P1 path-visible regular file remained canonical after parent replacement | `records/rollup-answer-independent-codex-audit.md` |
| Fifth-audit receipt/entry red-green | RED 2 independently reproduced failures; GREEN targeted 3/3, rollup 25/25, Morning Brief delivery all pass | `records/evidence/rollup-answer-receipt-entry-red-green.txt` |
| Final same-model/max audit | pending | `records/rollup-answer-independent-codex-audit.md` |

## Claims and limits

- Confirmed: strict targeting, pending suppression/visibility, actionable-first bounded views, exact consumption, deterministic digest replay, fd-bound publication/replay quarantine, occupied replacement-parent conflict invalidation, and same-runtime no-send refresh across decisions, persisted Morning Brief, and public brief-feed surfaces are exercised in hermetic tests.
- Confirmed: delivered brief identity/receipt/cursor bytes are preserved only after a complete private receipt binds full Markdown, deterministic chunking, ordered chunk hashes, and exact receipt bytes; pending delivery refresh fails nonzero without rewriting retry content, including after day rollover.
- Confirmed: receipt-backed non-directory canonical collisions are fd/inode-bound and privately quarantined, while first-answer orphan conflicts remain fail-closed and untouched.
- Confirmed: no dependency or schema migration was introduced.
- Did not verify: the fifth repair's authoritative full gate or final audit, hosted PR checks, merge, install, deploy, provider delivery, or live-store behavior.
