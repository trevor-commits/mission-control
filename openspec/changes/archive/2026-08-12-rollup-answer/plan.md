# Rollup-answer implementation plan

> Execute `hotl-workflow-rollup-answer.md` step by step. This file binds the approved design to OpenSpec without duplicating the executable micro-plan.

**Goal:** Record one operator answer across only strictly equivalent rollup members while keeping each member open until its owning task proves consumption.

**Architecture:** Derive current pending from immutable events scoped to the row's evidence fingerprint. Re-plan inside one SQLite immediate transaction and insert every target event atomically. Stage all private artifacts below an fd-pinned batch parent and publish them with one directory rename; exact replay repairs a post-commit publication failure.

**Tech stack:** Python 3 standard library, SQLite WAL, macOS Bash 3.2, vanilla JavaScript/static HTML, existing Mission Control test harnesses, OpenSpec, and HOTL.

## Commit checkpoints

1. Approved contract, plan, and branch state.
2. Red regression contracts with captured failure evidence.
3. Queue/batch core green.
4. CLI and local render surfaces green.
5. Independent-audit repairs and final evidence.

Every checkpoint stays on `codex/rollup-answer-wiring`. No commit is merged to `main`; no runtime is installed.
