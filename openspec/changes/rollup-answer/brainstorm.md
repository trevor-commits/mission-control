# Rollup-answer brainstorm — approved decision capture

The earlier Lane D review found a real conflict: the existing single-answer path resolves a decision immediately, while the Phase 0 contract says a rollup answer is not completion. Trevor approved the seven-point contract on 2026-07-18, so this artifact records the settled design rather than reopening discovery.

## Settled choices

1. The CLI is `dashboard decide answer-rollup <card-id> <primary-decision-id> <choice>` with the existing source and resume metadata flags.
2. The target set is the primary plus only members admitted by `plan_rollup_supersession(...).supersede`; independent members remain open and visible.
3. Targeted members stay `open`. Each current evidence fingerprint receives one durable `answered_pending` event with card, primary, choice, source, and private artifact references.
4. Current pending members remain visible but cannot be alerted, dismissed, or answered again through the ordinary single-decision path.
5. Only existing graph-verified `answering_user_turn` or `downstream_resolution_key` evidence may resolve a pending member. Manual resolution is rejected while pending.
6. The composer stages all member artifacts, revalidates the current rollup plan, records every pending event in one SQLite transaction, and publishes one private batch by atomic directory rename. Pre-commit failure changes no member; post-commit publication failure is recoverable by exact replay.
7. Exact current scope plus choice is idempotent. A conflicting choice or partial/mismatched pending set fails closed. A new evidence fingerprint clears the pending interpretation and permits a new answer.

## Design constraints

- Python standard library, SQLite WAL, vanilla JavaScript, and macOS Bash 3.2 only.
- No new state enum or schema migration: `answered_pending` is an immutable event interpreted only for the row's current evidence fingerprint while state is `open`.
- No provider call or answer delivery occurs in this slice. Artifacts are private local handoff material only.
- Existing single-answer semantics remain compatible for decisions that are not pending.
- No visual redesign: existing decision cards gain an honest read-only pending state.
