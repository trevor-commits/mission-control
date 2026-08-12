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
- Pre-integration branch head: `6a75e879b6b9bd43737edce841d4268453f8a1eb`.
- Current-main integration base: `43bca917871a33f3b4176117df86e15eb80a3472`.
- Current-main source repair: `60577b78fa32b48f10580796f94aacdb16a1fb19`.
- Source no-write repair: `fdb838dd6d7520646541c9bf95e2a7901c8c2d58`.
- Repository convergence integration: source repairs are contained as `bd83a30` and `4453b8e`; rewritten PR review/CI repair is `db40774bbb477326989553cba703c716d857bb80`. Repair `c988153baedfceeae68773072fb3fde032f2a8f9` closes the two cross-platform failures from hosted run `31639362011`. Receipt head `e0b60f7c545c5ec2612e3aa6aa124c59b53c4f7c` passed the ordinary push hook, hosted run `31642058664`, GitGuardian, and CodeRabbit. PR #16 merged as `ddc8700cccab5586663703faab3ac782104085b5`.
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
| Current-main focused integration | dashboard 86/0; rollup 29/29; dashboard browser 309; panel browser 13/0; ER-134 62/0; render smoke 8/8; syntax and diff checks pass | current task transcript |
| Attention-feed compatibility repair | exact RED manual attention and stale Brief both rendered `Answers recorded`; source and integrated GREEN browser 315; render smoke, JavaScript syntax, strict OpenSpec, and diff checks pass | source `60577b78`; convergence `bd83a30` |
| Final repository-convergence verifier | `SUITES PASS=26 FAIL=0` at exact candidate `112757172e640450f73fcd1a69f36745f6882a73`; rollup 29/29; dashboard 90/0; browser 315; OpenSpec 2/0; syntax and artifacts pass | current convergence task transcript |
| PR review and hosted-CI repair | RED stale attention, native pending overcount, ambient abort, stale sidecar health, missing index, and whole-value validation; GREEN dashboard 91/0, rollup 32/32, browser 315, panel 13/0, native 16/0, affected shell/Python suites and static checks | rewritten convergence repair `db40774`; `records/2026-08-11-repository-convergence.md` |
| Post-rewrite authoritative verifier | `SUITES PASS=26 FAIL=0` at exact `e34c2ed23028b31707ef581ba0bc6b1cc9e4a92e`; dashboard 91/0; rollup 32/32; ER-134 63/0; browser 315; panel 13/0; native suites 16/0 each; OpenSpec 2/0; syntax and artifacts pass | current convergence task transcript |
| Second hosted macOS repair | RED read-only invalid-member validation created WAL/shared-memory sidecars; hosted search observed an earlier debounced render. GREEN at `c988153`: rollup 32/32, Decision Alert all pass, browser 315 twice, syntax and diff checks pass | hosted run `31639362011`; convergence record |
| Second-hosted exact verifier | `SUITES PASS=26 FAIL=0` at exact records head `7a2ae1af7264df830b48cfb622c1f71a1b85029a`; dashboard 91/0; rollup 32/32; browser 315; panel 13/0; native suites 16/0 each; OpenSpec 2/0; syntax and artifacts pass | current convergence task transcript |
| Receipt publication and hosted readback | ordinary push hook `SUITES PASS=26 FAIL=0`; hosted run `31642058664` success; CodeRabbit approved; GitGuardian passed at `e0b60f7` | PR #16 provider readback |
| Merge, install, and natural runtime | PR #16 merged as `ddc8700`; install stamp binds 9 runtimes and 4 assets to that exact head; natural launchd runs advanced from 244 to 246 with last exit zero | install stamp, dashboard status, and launchd readback |
| Archive and stale-PR closeout | six remote archive tags read back at exact SHAs; PRs #10 and #11 closed without merge; approved cleanup broker preserved both released source worktrees | convergence record and provider readback |
| Final same-model/max audit | not repeated after the merge; the merge tree is identical to the exact reviewed and hosted-green PR head | `records/rollup-answer-independent-codex-audit.md` |

## Claims and limits

- Confirmed: strict targeting, pending suppression/visibility, actionable-first bounded views, exact consumption, deterministic digest replay, fd-bound publication/replay quarantine, occupied replacement-parent conflict invalidation, and same-runtime no-send refresh across decisions, persisted Morning Brief, and public brief-feed surfaces are exercised in hermetic tests.
- Confirmed: delivered brief identity/receipt/cursor bytes are preserved only after a complete private receipt contains and binds full Markdown, deterministic chunking, ordered chunk hashes, and exact receipt bytes; either missing identity field fails nonzero before rewrite, and pending delivery refresh fails nonzero without rewriting retry content, including after day rollover.
- Confirmed: receipt-backed regular-file and symlink canonical collisions are fd/inode-bound and privately quarantined without symlink target traversal, while first-answer orphan conflicts remain fail-closed and untouched; a deterministic quarantine name swap restores the unbound replacement before failure.
- Confirmed: Home's global H1 uses combined feed attention while pending decision rows retain their separate awaiting-consumption presentation.
- Confirmed: the valid 300-second attention envelope participates in guard validation and combined Home state; exact `attention` and `attention — ...` panel states remain actionable.
- Confirmed: exact sixth-repair head `78672c4` passes the authoritative `SUITES PASS=23 FAIL=0` gate live on macOS 26.5.
- Confirmed: no dependency or schema migration was introduced.
- Confirmed: receipt head `e0b60f7` passed the ordinary push hook and repaired hosted CI. PR #16 merged as `ddc8700`, and that exact source is installed with natural scheduled exit-zero proof.
- Confirmed: no provider delivery or live decision-store mutation was used as verification. The existing collector LaunchAgent retained its label and cadence; activation-gated jobs remained skipped.
- Did not verify: a new post-merge same-model/max audit, provider delivery, or live-store answer behavior. The merge commit contains the exact hosted-green PR tree, so these are recorded limits rather than hidden acceptance claims.
