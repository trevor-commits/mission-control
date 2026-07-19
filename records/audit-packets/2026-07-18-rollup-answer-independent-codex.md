# Goal

Independently audit the Phase 0 Lane D `answered_pending` rollup-answer implementation and determine whether the frozen branch is merge-ready without trusting its implementation or test summaries.

Runner: Codex
Model: `gpt-5.6-sol`
Reasoning: `max`

## Frozen review target

- Repository/worktree: `/Users/gillettes/Coding Projects/mission-control-worktrees/rollup-answer-wiring`
- Branch: `codex/rollup-answer-wiring`
- Base: `53e91392dcef3d2deeedf748c14159320a8572e0`
- Candidate before this packet: `953de86`
- Review the exact committed `BASE..HEAD` range present when the audit begins; record the full resolved HEAD SHA before analysis.
- Canonical requirements: `openspec/changes/rollup-answer/`, `hotl-workflow-rollup-answer.md`, `STATE.md`, and the approved seven points in those files.

## Governance and hard boundaries

- Read repo `AGENTS.md`, `AGENTS.project.md`, `PROJECT_INTENT.md`, `CONTINUITY.md`, `COHERENCE.md`, and `LINEAR.md` before conclusions.
- Audit only. Do not edit files, stage, commit, push, merge, install, deploy, cut releases, touch plists/launchctl, write live Mission Control/chat-graph/usage stores, or send Telegram/provider/network messages.
- Use only temporary homes/stores, synthetic fixtures, stubs, and loopback test transport.
- Treat all branch summaries and receipts as claims to verify against source, diff, and fresh commands.
- Do not use subagents or create additional chats; this fresh task is the independent reviewer.

## Required analysis

1. Resolve and record exact base/head/status; inspect `git diff --check` and the full production/test/spec diff.
2. Verify each approved semantic independently:
   - public `dashboard decide answer-rollup` interface and source/resume metadata;
   - primary plus strict action+owner+target equivalents only, with independent/already-pending members visible and unchanged;
   - targets remain `open` with current-fingerprint `answered_pending` and private artifact references;
   - local visibility plus suppression of alert, dismiss, single-answer, and Morning Brief duplication;
   - only exact graph-verified per-member consumption resolves pending; manual resolution rejects;
   - all artifacts staged/verified before one SQLite transaction, atomic private publication, exact post-commit recovery;
   - exact scope+choice idempotency; conflict/partial/malformed/changed-scope failure; changed evidence unlock.
3. Adversarially inspect security/privacy and concurrency boundaries: validation before paths, traversal/newline/secret metadata, fd pinning, symlink/rename swaps, modes, manifest/member hashes, TOCTOU, replay, SQLite rollback/locking, partial state, UI truth, and no hidden delivery/live action.
4. Confirm tests exercise real behavior rather than only mocks. Rerun at minimum:
   - `PYTHONDONTWRITEBYTECODE=1 python3 scripts/rollup-answer.test.py`
   - `/bin/bash scripts/decision-alert.test.sh`
   - `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh --self-test`
   - strict rollup OpenSpec, Bash/Python syntax, diff check, and post-run source-artifact check.
   Run additional focused or full tests if needed to substantiate a finding or verdict.
5. Apply Brooks-Lint PR Review principles. A finding must include exact file/line evidence and `Symptom`, `Source`, `Consequence`, and `Remedy`; do not manufacture style findings where the complexity is essential to the safety contract.

## Output contract

- Begin with exact base/head and commands actually rerun.
- List P0/P1/P2/P3 findings with proof. If none remain after structural review, state `REVIEW-CLEAN` explicitly.
- Separate `Confirmed`, `Inferred`, `Needs More Evidence`, and `Do Not Do Yet` claims.
- Include a requirement-by-requirement verdict for all seven points, an explicit `did not verify` line, and residual risk.
- Do not claim merge-ready from tests alone. Give a final `MERGE-READY` or `NOT MERGE-READY` verdict with reasons.
- Return the complete review in the final response to the parent task; make no repository mutation.

## Delegation defaults

- No delegation for this bounded audit. If one command fails, diagnose and retry once with new evidence; after two grounded failures, record the unverified boundary instead of thrashing.
