---
intent: Implement the stubbed first slice of Mission Control answer dispatch from recorded decision through queue, linted prompt, route, and receipt.
success_criteria: Queue failure does not undo answers; router truth table and stub drain pass; decisions feed exposes receipt state; requested regressions and dry run are green.
risk_level: medium
auto_approve: true
branch: codex/answer-dispatch-slice1
dirty_worktree: allow
report_detail: full
---

## Steps

- [x] **Step 1: Lock contracts and branch state**
action: Record the branch ledger, self-contained tracking disposition, approved design source, and exact acceptance commands.
loop: false
verify: git status --short && test "$(git branch --show-current)" = codex/answer-dispatch-slice1

- [x] **Step 2: Write failing behavior tests**
action: Add focused tests for queue failure isolation, queue fields, router precedence, malformed drain behavior, lint hold, stub receipt, and feed receipt fields.
loop: false
verify: bash scripts/dispatch-runner.test.sh

- [x] **Step 3: Implement the minimum dispatch slice**
action: Extend the existing answer transaction, add the Bash 3.2-safe embedded-Python runner, add Claude-owned template skeletons, and attach receipt state in the decisions collector without editing dashboard/index.html.
loop: until focused tests pass
max_iterations: 3
verify: bash scripts/dispatch-runner.test.sh

- [x] **Step 4: Prove the end-to-end dry run**
action: Answer a synthetic structured decision, drain the queue with the stub sender, and assert the queue packet, linted prompt, route, and receipt.
loop: until dry run passes
max_iterations: 3
verify: bash scripts/dispatch-runner.test.sh --e2e-only

- [x] **Step 5: Run regression gates**
action: Run the requested existing suites plus syntax, whitespace, and focused dispatch checks.
loop: until all checks pass
max_iterations: 3
verify: bash scripts/dispatch-runner.test.sh && REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell && bash scripts/decision-alert.test.sh && git diff --check

- [x] **Step 6: Audit and close out durable state**
action: Run an independent review, resolve accepted findings, perform the Ripple Check, write the Work Record, Completed entry, test evidence, branch status, and honest Self-audit, then commit and push.
loop: until no blocking findings remain
max_iterations: 3
verify: git status --short && git log -1 --oneline
