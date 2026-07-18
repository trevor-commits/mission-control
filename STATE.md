# Lane D state — rollup-answer CLI wiring

- Status: BLOCKED by a binding state-contract ambiguity; no production code changed
- Branch: `codex/rollup-answer-wiring`
- Base: `origin/main@8582e182d5db3b8964ec21738a82806d94c78a55`
- Worktree: `/Users/gillettes/Coding Projects/mission-control-worktrees/rollup-answer-wiring`
- Live/deploy actions: none

## What is unambiguous

- Presentation rollup groups exact normalized text.
- Answer fan-out may include another member only when `same_equivalence()` proves the same action, originating owner/session, and backtick-identified target.
- Missing or different action/owner/target fails closed; that member stays independent.
- The binding packet requires members to remain pending until each owning task consumes the answer.
- Tests must use temporary Mission Control homes/stores only.

## Blocking contradiction

| Source | Current contract |
|---|---|
| Binding overnight packet, Lane D | Apply the answer to eligible members but keep them pending until each consumes it; do not guess if ambiguous. |
| Canonical minimal-input plan, row 0.2 | An answer is not completion; it enters answered-pending-consumption and closes only after the owning task consumes it and reports an outcome. |
| `scripts/queue_admission.py:433-439` | Says the missing write path should call existing `resolve()` for every superseded member. |
| `scripts/decision-alert:613-646` | Existing `resolve()` immediately sets `state='resolved'`. |
| `scripts/compose-decision-prompt.py:197-316` | Existing single-answer transaction immediately calls `resolve manual_resolution` before publishing answer/prompt artifacts. |
| Current schema | Allows only `open`, `dismissed`, or `resolved`; it has no answered-pending state or consumption-receipt field. |

Calling `resolve()` for rollup members would satisfy the stale helper docstring but directly violate the binding packet and canonical plan. Leaving rows `open` without a new durable pending marker would also be unsafe: the rows could be re-alerted/re-answered, the UI could not distinguish unanswered from answered-pending, and a multi-member failure could partially publish answers with no coherent recovery contract.

## Design decision needed

Confirm or replace this recommended minimal contract before implementation:

1. CLI: `dashboard decide answer-rollup <card-id> <primary-decision-id> <choice> [existing source/resume flags]`.
2. Member set: primary plus only `plan_rollup_supersession(...).supersede`; `independent` members are untouched and returned visibly.
3. State: every targeted member remains `open`; record a durable `answered_pending` event carrying choice, source, card ID, and primary ID, and publish a private answer/prompt artifact per member.
4. Visibility/dedup: answered-pending members remain visible as pending but are excluded from ordinary re-alert/re-answer until consumption or changed evidence.
5. Completion: only existing verified downstream/answering-turn evidence from each owning task may call `resolve()` for that exact member.
6. Atomicity: preflight and stage every member artifact, then record all pending events and publish all artifacts as one recoverable batch; any pre-commit failure changes no member.
7. Replay: same card/member set + choice is idempotent; a different choice fails closed until an explicit supersession rule is specified.

This is the smallest design that appears to satisfy the binding semantics, but it adds a new durable event/state interpretation and batch transaction. The packet explicitly forbids guessing that contract into the production queue, so implementation stopped here.

## Evidence transcript

```text
$ git grep / source inspection
queue_admission.py plan_rollup_supersession -> supersede / independent
queue_admission.py docstring -> calls EXISTING resolve() per superseded member
decision-alert resolve() -> UPDATE decisions SET state='resolved'
compose-decision-prompt.py answer_transaction() -> resolve manual_resolution
decision schema CHECK(state IN ('open','dismissed','resolved'))
canonical plan row 0.2 -> answered-pending-consumption until owning task receipt
```

The packet-author audit transcript (`6b78e170-f063-47e2-92f8-48e6f5ce0600`, `Audit prompt implementation work`) was resolved with `chat-source`; it repeats the packet requirement but does not define the missing durable representation, CLI shape, or batch atomicity.

## Diff summary

- `STATE.md`: this blocking design question, evidence, claims, and resume pointer.
- `todo.md`: active next step, branch ledger, bounded Work Record, and test-evidence disposition.
- Production/runtime/test files changed: none.

## Claims

- The action + owner + target equivalence rule is clear and mechanically testable.
- The current write-path guidance conflicts with the binding answered-pending requirement.
- Implementing immediate `resolve()` fan-out would incorrectly close members before consumption.
- No main branch, live decision store, Telegram/API, install, deploy, release, plist, or launchd surface was touched.
- did not verify: rollup-answer behavior, because no unambiguous durable pending/consumption contract exists and no production code was changed.
- did not verify: tests beyond static/source inspection and `git diff --check`, because the binding stop condition fired before implementation.

## Done / next / exact resume

- Done: read the exact queue/answer paths, canonical plan, packet-author transcript, schema, and existing hermetic test seams; isolated the contradiction without mutating code.
- Next: confirm the recommended seven-point contract above or provide the intended alternative.
- Exact resume: `cd '/Users/gillettes/Coding Projects/mission-control-worktrees/rollup-answer-wiring' && git status -sb && sed -n '1,260p' STATE.md && sed -n '300,455p' scripts/queue_admission.py && sed -n '197,320p' scripts/compose-decision-prompt.py`
