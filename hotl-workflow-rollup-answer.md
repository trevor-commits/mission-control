---
intent: Wire the approved answered-pending rollup-answer contract into Mission Control without resolving work before verified owner consumption.
success_criteria: Strict targeting, durable open pending state, suppression, verified exact consumption, atomic recoverable private batches, idempotent replay, changed-evidence unlock, truthful local rendering, full verification, and an independent same-model audit are green on the topic branch.
risk_level: medium
auto_approve: true
branch: codex/rollup-answer-wiring
worktree: false
dirty_worktree: allow
---

## Steps

- [x] **Step 1: Re-establish isolated branch truth**
action: Verify the dedicated linked worktree, branch, base, upstream, clean status, and no live/deploy action.
loop: false
max_iterations: 1
verify: git status --short --branch
gate: auto

- [x] **Step 2: Capture untouched baseline**
action: Run the authoritative verifier before edits and retain the full 21-suite result.
loop: until the baseline completes
max_iterations: 2
verify: /bin/bash scripts/verify.sh
gate: auto

- [x] **Step 3: Bind the approved contract**
action: Record the seven approved semantics, invariants, failure matrix, OpenSpec scenarios, task map, Trust Gate status, and repo-only work disposition.
loop: until strict spec and document lint pass
max_iterations: 2
verify: openspec validate rollup-answer --strict
gate: auto

- [x] **Step 4: Write red queue and batch contracts**
action: Add hermetic tests for targeting, pending derivation, suppression, exact consumption, changed evidence, atomic events, replay conflicts, recoverable publication, permissions, and path races; save the expected pre-implementation failures.
loop: false
max_iterations: 1
verify: test -s records/evidence/rollup-answer-red.txt
gate: auto

- [x] **Step 5: Implement queue semantics**
action: Add active-pending interpretation, read-only current planning, one-transaction event recording, alert/dismiss/single-answer suppression, and exact graph-verified consumption.
loop: until focused queue tests pass
max_iterations: 2
verify: /bin/bash scripts/decision-alert.test.sh && python3 scripts/queue_admission.test.py
gate: auto

- [x] **Step 6: Implement recoverable private batches**
action: Add fd-pinned staging, deterministic scope/batch identity, mode-600 member artifacts, atomic directory publication, post-commit exact recovery, and conflicting-choice refusal.
loop: until rollup-answer batch tests pass
max_iterations: 2
verify: python3 scripts/rollup-answer.test.py
gate: auto

- [x] **Step 7: Wire CLI and truthful local presentation**
action: Add `dashboard decide answer-rollup`, preserve independent-member output, skip pending in Morning Brief NEEDS YOU, and render pending without action buttons in Home and the menu-bar panel.
loop: until CLI, dashboard, usability, render, and Bash 3.2 checks pass
max_iterations: 2
verify: /bin/bash scripts/dashboard.test.sh --require-shell && /bin/bash scripts/er134-usability.test.sh && node scripts/dashboard-render-smoke.js . && /bin/bash -n scripts/dashboard
gate: auto

- [x] **Step 8: Verify the complete branch candidate**
action: Run focused negative/mutation checks, strict OpenSpec, HOTL lint, syntax, diff check, and the authoritative full verifier; write immutable evidence and claims.
loop: until every in-scope gate is green
max_iterations: 2
verify: /bin/bash scripts/verify.sh
gate: auto

- [ ] **Step 9: Run independent same-model audit**
action: Five audit rounds rejected earlier candidates at publication, replay, runtime, presentation, occupied-parent, persisted-view, receipt-identity, and canonical-entry boundaries. Frozen `8b8fa77` reopened two P1s: complete-looking receipt fields did not bind delivered bytes, and a regular-file canonical conflict survived parent replacement. Exact repair `c0d0a53` binds full Markdown/chunk/receipt identity, quarantines exact fd/inode-bound receipt-backed entries, and passes the authoritative 23/0 gate; commit its receipt, freeze the successor, and require a fresh review-clean verdict before closeout.
loop: until no material novel finding remains
max_iterations: 2
verify: test -s records/rollup-answer-independent-codex-audit.md
gate: auto

- [ ] **Step 10: Close the branch without landing runtime**
action: Update OpenSpec verification/retrospective, STATE, todo, Work Record, branch ledger, audit coverage disposition, claims, rollback, dirty-state proof, commits, push, and PR; stop before merge or deploy.
loop: until branch closeout is coherent
max_iterations: 2
verify: git status --short --branch
gate: auto
