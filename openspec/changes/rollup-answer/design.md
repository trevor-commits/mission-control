# Rollup-answer design

## Invariants

1. **Selection is fail-closed.** A card is recomputed from current open rows. Only the primary and strict action+owner+target equivalents are targets. Every other member is returned as independent or already pending.
2. **Answer is not completion.** A target remains `open`; the current `answered_pending` event is presentation and suppression metadata, not a new terminal state.
3. **Evidence scopes pending.** A pending event is active only when its `evidence_fingerprint` equals the decision row's current fingerprint. Changed evidence therefore unlocks a new answer without rewriting history.
4. **One current choice.** A deterministic scope key covers card, primary, ordered target IDs, and current fingerprints. The batch key additionally covers the choice. Exact replay is a no-op; any current mismatch fails closed.
5. **All database members move together.** `BEGIN IMMEDIATE` re-plans, checks the expected scope, validates every target, and inserts all `answered_pending` events before one commit. Any exception rolls back all inserts.
6. **Artifacts publish together.** The composer pins the Mission Control home and batch parent by file descriptor, writes mode-600 member files into a private stage directory, fsyncs them, commits queue events, then atomically renames the stage directory to the deterministic batch destination.
7. **Publication is recoverable.** If the database commit succeeds but publication does not, exact replay rebuilds/publishes the same deterministic batch without duplicating events. A conflicting replay never overwrites it.
8. **Only owner evidence completes.** Current pending rows reject manual resolution. Existing graph verification must prove the exact member resolution key and answering/downstream evidence reference.

## Data interpretation

`decision_events.event_type = 'answered_pending'` carries:

- `schema`, `scope_key`, `batch_key`, `card_id`, `primary_decision_id`, and `choice`;
- `source` when supplied;
- the complete target and independent ID lists;
- per-member relative answer and prompt artifact paths.

`_decision_dict()` exposes the latest active event as `answer_pending`; otherwise it returns `null`. Rows remain in `status.data.pinned` because their durable state remains `open`.

## Transaction sequence

1. Validate CLI identifiers and choice before creating any path.
2. Acquire an fd-pinned lock derived from card plus primary.
3. Call read-only `plan-rollup-answer`; build every prompt/answer/manifest in a private stage directory.
4. Revalidate pinned directories and call `answer-rollup --expected-scope-key`.
5. Revalidate again and atomically rename the stage directory to the batch key.
6. Refresh the decision snapshot best-effort; return target, independent, replay, and artifact details.

## Failure behavior

| Boundary | Required result |
|---|---|
| Invalid ID/choice/card/primary | No filesystem or database write |
| Unsafe/symlinked/renamed batch parent | No redirected write; no pre-commit event |
| Failure while staging | Stage removed; no decision changes |
| Plan/evidence/member change before commit | Scope mismatch; full rollback |
| Failure during event insertion | Full SQLite rollback; zero partial pending members |
| Failure after commit before rename | Pending events remain recoverable; exact replay publishes once |
| Exact same scope and choice | No duplicate events; existing or recovered batch returned |
| Different choice/current pending mismatch | Fail closed; no overwrite |
| Changed evidence fingerprint | Old event remains history; row is answerable again |

## Security and privacy

- Artifacts stay below the exact private Mission Control home and are mode 600 inside mode-700 directories.
- No shell interpolation, new dependency, network call, provider send, or live action is added.
- Event metadata stores relative private artifact paths, not prompt bodies.
- Existing narrative sanitization remains the queue ingress boundary.
