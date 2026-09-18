# Live loose-ends recovery — September 17, 2026

Owner: Hermes ops, session 20260915_113318_4b3d6c.
Request: finish the quiet live hierarchical board, not a digest.
Takeover: main ac035b9, clean checkout. Installed stamp still 1f158ae.

## Verified findings
- Prior full gate /tmp/verify-final.log ended SUITES PASS=40 FAIL=1, not fully green. The real failure was the live-data guard; self-fail was intentional.
- Isolated browser run passed with zero cloned-state hash changes. Real headroom.json/js changed from the separate collector. Evidence: /tmp/loose-tree-isolation-check.py and its printed artifact directory.
- The guard omitted the new loosetree feed from its existing refresher allowlist. Historical log did not retain changed paths, so attribution of that failure remains uncertain. Added exact changed-path diagnostics and registered the actual new feed.
- Public CLI test reproduced lost updates: 48 simultaneous adds retained 31 items. Other regressions: corrupt store overwritten, cycles accepted, terminal-update bypass, blank decision marked answered.
- Installed store has two distinct auto-source rows with ID T-20260916-1742-de5d. No child points at that ID. Preserve both rows and snapshot before a migration. Do not deploy strict validation without this repair.

## Candidate changes (not installed)
- Shared file lock covers collector/CLI read-modify-write transaction. Atomic replacement remains.
- Corrupt/invalid stores are rejected without overwrite. Longer generated IDs, parent-cycle guards, terminal guards, and nonempty decisions.
- Optional pytest branch referred to a deleted test file. Replaced with stdlib regression suite.
- UI: real expandable hierarchy, collapsed Inbox, waiting before doing, completed hidden with history toggle, explicit capture limit.
- Collector refuses stale/error source pruning.

## Acceptance evidence
- loose-tree self-test and all five public CLI regressions pass; 48/48 writes retained.
- Focused dashboard feed suite: PASS=7 FAIL=0.
- Real Chromium focused UI: seven checks true, no script errors (question visible, Inbox collapsed/expandable, history hidden/visible, correct ordering).
- Full gate finished at exit 0: SUITES PASS=41 FAIL=0 in /tmp/loose-tree-current-verify.log. Its intentional self-fail fixture is not a failing suite. Focused feed check also passed after the final stale-source guard change. Repeated concurrent-write test passed.
- Pre-change source snapshot: /tmp/loose-tree-recovery-20260917-103928.

## Remaining delivery and product gaps
1. Confirm full gate; commit/publication and immutable installation have NOT occurred for this recovery candidate. Preserve foreign work.
2. Snapshot and repair the two unambiguous auto-row IDs before new installed validation; retain both records and verify count unchanged.
3. Natural-cycle acceptance of the new runtime, then live browser check.
4. Universal conversational extraction is NOT implemented. Supported source feeds plus agent recording are available. Arbitrary unanswered questions, informal mentions, and unaccepted suggestions still depend on semantic capture. The existing Outcome Extractor has a separate calibration/activation gate in todo.md; do not silently activate it or add a parallel scheduler.
5. Feed disappearance currently removes auto-only rows; this is not verified completion. A durable archive/reconciliation design and cross-harness capture coverage remain open.

No notification job or model-route change was added. No unrelated runtime or profile was modified in this recovery.
