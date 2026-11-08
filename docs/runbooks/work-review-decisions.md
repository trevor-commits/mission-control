# Per-outcome decision worksheet

This is the small-model review contract. It supplements `actionable-work.md`;
it grants no new authority. A valid worksheet is still only a proposal.

## Keep these distinctions explicit

- **One selected outcome, one row.** Return every `accepted_selected` and rotating
  selected ID exactly once. Do not combine utilities, Support or other tasks
  merely because they share an owner. Keep each authority, timing restriction,
  uncertain-send state and remaining action attached to its exact outcome.
- **Accepted work stays accepted.** An approved task waiting for a worker,
  deadline or evidence is not a candidate. An assistant suggestion is a
  candidate; it was not cancelled or paused unless it first became accepted.
- **A question is not the whole task.** Use a question ID only for a real human
  question. “Request understood” does not mean a question was answered. An
  approval may resolve the question while implementation remains Waiting.
  `closure_target` must name the exact selected outcome. If that outcome is
  broader than the answered question, record the answer without closing work.
- **Do not recertify unchanged completed items.** The packet excludes them.
  Keep the saved verified state unless new evidence actually challenges it.
- **Closure needs independent verification.** Every closure candidate requires
  `independent_verification_required:true`. Customer, financial, production,
  credential, destructive, installed-runtime or unknown-risk closure also needs
  `stronger_review_required:true`. Luna collects and proposes; an existing
  stronger reviewer or its exact immutable proof must cover all criteria before
  a consequential `verify passed`. Do not create another reviewer/monitor or
  switch models automatically. `closure_candidate` proposes an independent
  verification; it does not mark the underlying ledger done. Keep that ledger
  item Waiting until every required verification has actually passed.
- **Unknown access is not an unanswered question.** A question may appear only
  after its relevant newer-answer check is complete. An answered, deferred,
  cancelled or unknown question is not repeated. Exact current replies outrank
  a later assistant summary repeating an old NEEDS YOU line.

## Worksheet shape

Save a private JSON object containing only `outcomes`. Each selected row has:

```json
{
  "task_id": "exact-selected-ledger-id",
  "accepted": true,
  "work_state": "waiting",
  "question_id": "exact-question-id-or-null",
  "question_state": "answered",
  "question_to_user": null,
  "newer_answer_coverage": "complete",
  "evidence_ids": ["exact-latest-user-message-id", "checked-artifact-id"],
  "operation": "record_answer",
  "closure_target": null,
  "risk_class": "internal",
  "independent_verification_required": false,
  "stronger_review_required": false,
  "cursor_advance_to": null,
  "route_owner": null,
  "reason": "Approval is answered; the separately requested implementation is still unfinished."
}
```

Use JSON null, not a string, when no question or target exists. Allowed values:

Every row requires a concise `reason`: the concrete next action or closure
check, plus its applicable restrictions. Evidence IDs alone do not preserve an
actionable handoff. For outbound work, explicitly retain the exact approved body
and recipient reference, allowed time window, and any no-resend/unknown-send
restriction. For path-bound work, retain the exact allowed path and exclusions.
The guard rejects an absent/empty reason; independent review checks its meaning.

| Field | Values |
| --- | --- |
| work_state | candidate, held, ready, doing, waiting, closure_candidate |
| question_state | not_applicable, unanswered, unknown, answered, deferred, cancelled |
| newer_answer_coverage | complete, partial, unknown, not_applicable |
| operation | no_change, record_answer, record_state, preserve_candidate, preserve_hold, prepare_dispatch, propose_closure |
| risk_class | internal, customer, financial, production, credential, destructive, installed_runtime, unknown |

Operations have exact state meanings. Use `record_state` for accepted Waiting,
Doing or Ready progress, including missing evidence and an uncertain send.
`preserve_hold` is only for `held` work with an actual pause/hold; it is not a
synonym for Waiting. `preserve_candidate` is only for unaccepted candidates.
`prepare_dispatch` is only Ready, and `propose_closure` is only a closure candidate.
`record_answer` requires a real answered/deferred/cancelled question; it does not
close unfinished implementation. `no_change` preserves a nonterminal state.

`internal` is for clearly reversible local outcomes, not a default for unclear
scope. No real question means `question_id:null` and
`question_state:not_applicable`. A source candidate promoted by an actual user
request also needs `authority_evidence_ids`; those IDs still need semantic
review. Newly discovered outcomes outside the selected IDs are separate
proposals. Resolve/admit them under the existing runbook and obtain a fresh
packet before proposing selected-item updates. Do not smuggle them into a
validated worksheet as extra execution instructions.

## Mechanical guard and remaining human/model judgment

Run the same packet command with `--decisions /absolute/private/worksheet.json`.
It checks exact selected-ID coverage, accepted/candidate separation, question
state consistency, explicit closure scope and verification flags, unread-cursor
preservation, obvious routing blockers and delivery limits. The printed result
is `execution_authorized:false` even when valid.

If the guard rejects the worksheet, preserve it and correct the actual reason;
do not relax a check, drop an outcome or advance state to obtain a pass. No
dependent ledger mutation follows a failed worksheet. The guard cannot certify
the truth of a message, self-declared coverage/risk, valid consent or artifact
semantics. Review those independently. The installed CLI still requires the
full current plan, fresh native preflight, authority, dependencies and bound
dispatch/receipt/verification evidence.

Native status needs its actual observation timestamp, not a source's last edit
or a copied file's modification time. Record the capture time at the native
call in snapshot `at` or per-row `observed_at`; merged rows keep their own ages.
Missing, future or older-than-five-minute observations cannot support routing.
Conflicting absolute timestamps and prose such as “fresh20seconds ago” require
a fresh native read; never trust the prose. A new capture time alone is not a
source-content change.

The metadata packet proves no new continuous transcript range, so worksheet
cursor advances remain null. Any later direct-source cursor update needs its
own exact contiguous read evidence; neither selection nor a title match counts.

## Calibration

The November 7 initial Luna/High trial found newer answers and avoided duplicate
sends, but omitted a production-review gate, demoted accepted work, merged away
a Support obligation and labelled an unaccepted suggestion cancelled. These
rules and the focused guard regressions address those observed failures.
The original case oracle also conflated question closure with task closure;
preserve that qualification instead of counting harmless label differences as
unsafe actions. Frozen retests and genuinely new held-out cases remain necessary.
