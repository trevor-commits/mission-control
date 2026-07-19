# Rollup-answer design

## Invariants

1. **Selection is fail-closed.** A card is recomputed from current open rows. Only the primary and strict action+owner+target equivalents are targets. Every other member is returned as independent or already pending.
2. **Answer is not completion.** A target remains `open`; the current `answered_pending` event is presentation and suppression metadata, not a new terminal state.
3. **Evidence scopes pending.** A pending event is active only when its `evidence_fingerprint` equals the decision row's current fingerprint. Changed evidence therefore unlocks a new answer without rewriting history.
4. **One current choice.** A deterministic scope key covers card, primary, ordered target IDs, and current fingerprints. The batch key additionally covers the choice. Exact replay is a no-op; any current mismatch fails closed.
5. **All database members move together.** `BEGIN IMMEDIATE` re-plans, checks the expected scope, validates every target, and inserts all `answered_pending` events before one commit. Any exception rolls back all inserts.
6. **Artifacts stay bound to their receipt.** The composer pins the Mission Control home, batch parent, and staged/published batch by file descriptor; verifies the exact manifest/member bytes before and after the database transition; and stores the canonical manifest SHA-256 in every pending event.
7. **Publication and replay are recoverable.** Rollup prompts and manifests contain no wall-clock identity, so an exact replay reproduces the persisted digest. The artifact name bound to the held fd is authoritative independent of invocation lifecycle; a post-commit mutation, parent replacement, invalid existing/published directory, or non-directory canonical collision is preserved under a private quarantine name and exact replay rebuilds the current deterministic batch without duplicating events.
8. **Only owner evidence completes.** Current pending rows reject manual resolution. Existing graph verification must prove the exact member resolution key and answering/downstream evidence reference.
9. **Public success includes same-runtime local-view coherence.** The dashboard answer command binds its transaction composer and readers to one `SCRIPT_DIR` stack, ignores ambient `REPO_ROOT` and decision/brief feeder selectors for this transaction, runs the strict decisions collector with alert egress disabled, reconciles Morning Brief through that exact runtime, strictly republishes the brief feed, and returns nonzero while preserving the committed receipt for exact replay if any view cannot be refreshed. A delivered rewrite requires a mode-600 non-symlink receipt whose full Markdown digest, recorded chunking limit, and complete ordered chunk digests bind the sidecar-derived delivered bytes. The first rewrite also pins the exact receipt-byte digest for later replay; receipt/cursor bytes remain immutable, and in-flight delivery states fail closed before calendar rollover is considered.
10. **Needs-you bounds preserve actionability.** Home and panel stably order actionable rows before answered-pending receipts before applying their display limits, so an actionable count cannot produce a `Needs you` heading with no visible actionable control.

## Data interpretation

`decision_events.event_type = 'answered_pending'` carries:

- `schema`, `scope_key`, `batch_key`, `card_id`, `primary_decision_id`, and `choice`;
- `source`, resume metadata, and the canonical artifact-manifest SHA-256;
- the complete target and independent ID lists;
- per-member relative answer and prompt artifact paths.

`_decision_dict()` exposes the latest active event as `answer_pending`; otherwise it returns `null`. Rows remain in `status.data.pinned` because their durable state remains `open`.

## Transaction sequence

1. Validate CLI identifiers and choice before creating any path.
2. Acquire an fd-pinned lock derived from card plus primary.
3. Call read-only `plan-rollup-answer`; build deterministic prompt/answer/manifest bytes in a private stage directory and retain its fd.
4. Verify the stage name-to-fd binding plus every digest, then call `answer-rollup --expected-scope-key --artifact-manifest-sha256`; the writer persists that digest and exact replay metadata with every member event.
5. Revalidate the parent, name-to-fd binding, and held bytes after commit; quarantine the exact name bound to the held artifact fd on any receipt-backed failure, including existing-batch replay; atomically rename a verified stage to the batch key and verify that final name against the same held fd.
6. Run `engine collect --force --strict decisions` with `DECISION_ALERT_AUTO=0`, reconcile the local Morning Brief with the exact `SCRIPT_DIR/morning-brief`, then run the strict brief collector; return target, independent, replay, and artifact details only after all three local views are current.

## Failure behavior

| Boundary | Required result |
|---|---|
| Invalid ID/choice/card/primary | No filesystem or database write |
| Unsafe/symlinked/renamed batch parent | No redirected write; no pre-commit event |
| Failure while staging | Stage removed; no decision changes |
| Plan/evidence/member change before commit | Scope mismatch; full rollback |
| Failure during event insertion | Full SQLite rollback; zero partial pending members |
| Failure after commit before rename | Pending events remain recoverable; exact replay publishes once |
| Stage bytes change after commit | Public command fails; suspect stage is quarantined; exact digest replay rebuilds once |
| Batch parent changes after commit | Old-parent artifact is quarantined; reported path never succeeds missing; replay publishes below the current parent |
| Published batch conflicts with persisted digest | Invalid destination is quarantined; deterministic replay rebuilds the exact receipt |
| Existing batch mutates during replay | Public command fails; the held canonical batch is quarantined; exact replay rebuilds once without duplicate events |
| Batch parent changes during existing-batch replay | The exact held batch is quarantined in the descriptor-pinned old parent; replay publishes below the current parent |
| Replacement parent already holds the canonical name | The held old-parent artifact is preserved; the current-parent name is fd-bound and an invalid directory or regular-file conflict is quarantined before returning failure; exact replay rebuilds the receipt-backed bytes |
| Receipt-backed canonical name is a non-directory on later replay | The exact regular file is opened without symlink traversal, inode-bound, and quarantined; an orphan first-answer conflict is never mutated |
| Stale executable reader exists in the state home | It is not selected by a source-runtime transaction; writer and strict collector remain one runtime identity |
| Ambient `REPO_ROOT` or decision/brief override names stale code | Composer and readers stay under exact `SCRIPT_DIR`; answer-only refresh unsets feeder overrides while ordinary non-transaction collection retains override support |
| Persisted not-sent brief predates the answer | Exact-runtime local composition and strict brief collection remove the target before zero is returned |
| Same-day brief is already delivered | Full Markdown and ordered chunk hashes are verified against the complete receipt; the first local rewrite pins the exact receipt digest; local `NEEDS YOU` changes while receipt, cursor, identity, and state remain unchanged; no resend occurs |
| Delivered receipt has planted or later-changed bytes | Local artifacts remain unchanged and the public command returns committed-but-refresh-failed nonzero without a provider call |
| Sidecar claims delivered without a complete valid receipt | Local bytes remain unchanged; command returns nonzero with committed answer receipt |
| Brief delivery is pending, partial, or failed | Receipt-bound bytes remain unchanged across the day boundary; command returns nonzero with committed receipt and exact replay can retry later |
| Any strict local-view refresh fails | Command returns nonzero with committed receipt on stdout; no provider send occurs; exact replay can retry refresh |
| Pending rows fill a bounded Needs-you view | Later actionable rows are stably promoted into the visible prefix before pending receipts |
| Exact same scope and choice | No duplicate events; existing or recovered batch returned |
| Different choice/current pending mismatch | Fail closed; no overwrite |
| Changed evidence fingerprint | Old event remains history; row is answerable again |

## Security and privacy

- Artifacts stay below the exact private Mission Control home and are mode 600 inside mode-700 directories.
- No shell interpolation, new dependency, network call, provider send, or live action is added; the post-answer collector explicitly disables alert egress.
- Event metadata stores relative private artifact paths, not prompt bodies.
- Existing narrative sanitization remains the queue ingress boundary.
