# Rollup-answer verification

## Current candidate

- Code/test repair commit: `34687c9`.
- Second-audit repair commit: `8613d25`.
- Third-audit occupied-parent repair commit: `bfaf10b`.
- Fourth-audit local-view coherence repair: `0ce6d3d7704a8e305159cdbd78965bd34f1b8a02`.
- Fourth-repair receipt head rejected by the next audit: `8b8fa772336239eab812b38e2b152e69dce65a96`.
- Fifth-audit receipt/entry repair: `c0d0a5306ae51a81fb7ace3948804e78e810b651`.
- Fifth-repair receipt head rejected by the sixth audit: `0bf1c6905a880bf26233db777d8d35aa3985cf19`.
- Sixth-audit final-boundary repair: `78672c46d94041f974ca97b0d2cfe5596c6b020a` (`fix(decisions): harden symlink quarantine for macOS O_SYMLINK gap`).
- Final branch head: pending fresh exact-head re-audit (authoritative gate is green at the sixth-repair head).
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
| Fifth-repair authoritative verifier | `SUITES PASS=23 FAIL=0`; rollup 25/25; dashboard 67/0; ER-134 59/0; usage 24/0; browser 253; OpenSpec 2/0; syntax/artifact pass | `records/evidence/rollup-answer-receipt-entry-full-green.txt` |
| Sixth frozen-head audit | `NOT REVIEW-CLEAN`: P1 optional receipt identity fields; P1 receipt-backed symlink replay wedge; P2 quarantine name-swap mutation; P2 global Home H1 ignored non-decision attention | `records/rollup-answer-independent-codex-audit.md` |
| Sixth-audit final-boundary red/green | RED 2 P1 + 2 P2; GREEN targeted 4/4, rollup 29/29, browser 254, static checks | `records/evidence/rollup-answer-final-boundaries-red-green.txt` |
| Sixth-repair authoritative verifier | `SUITES PASS=23 FAIL=0` at exact head `78672c4` (macOS 26.5); rollup 29/29; browser 254; OpenSpec 2/0; syntax/artifact pass | `records/evidence/rollup-answer-final-boundaries-full-green.txt` |
| Final same-model/max audit | pending | `records/rollup-answer-independent-codex-audit.md` |

## Claims and limits

- Confirmed: strict targeting, pending suppression/visibility, actionable-first bounded views, exact consumption, deterministic digest replay, fd-bound publication/replay quarantine, occupied replacement-parent conflict invalidation, and same-runtime no-send refresh across decisions, persisted Morning Brief, and public brief-feed surfaces are exercised in hermetic tests.
- Confirmed: delivered brief identity/receipt/cursor bytes are preserved only after a complete private receipt contains and binds full Markdown, deterministic chunking, ordered chunk hashes, and exact receipt bytes; either missing identity field fails nonzero before rewrite, and pending delivery refresh fails nonzero without rewriting retry content, including after day rollover.
- Confirmed: receipt-backed regular-file and symlink canonical collisions are fd/inode-bound and privately quarantined without symlink target traversal, while first-answer orphan conflicts remain fail-closed and untouched; a deterministic quarantine name swap restores the unbound replacement before failure.
- Confirmed: Home's global H1 uses combined feed attention while pending decision rows retain their separate awaiting-consumption presentation.
- Confirmed: exact sixth-repair head `78672c4` passes the authoritative `SUITES PASS=23 FAIL=0` gate live on macOS 26.5.
- Confirmed: no dependency or schema migration was introduced.
- Did not verify: a fresh independent (same-model/max) frozen-head audit at `78672c4`; hosted PR checks/merge; install, deploy, provider delivery, live-store behavior, plist/launchd; merged-main.
