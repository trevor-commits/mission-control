# Mission Control actionable work loop

Owner: Codex `01a16afb-4d78-7fd2-beec-605a7fd11e64`.
Trevor authorized stale/duplicate reconciliation, routing already-authorized work
to the correct existing owner, and automatic completion verification. This
supersedes the review-only execution limit for that bounded coordination work.
It does not revive cancelled projects, authorize new external effects, change
models, or permit chat archiving.

Source: existing clean Mission Control main, integration `origin/main`.
No branch/worktree is needed: no active source owner or overlapping edits were
found by `lanes check`. Runtime data remains private in the existing store.

## Acceptance

- Keep one ledger and the existing daily08:00 review; no new scheduler.
- Show actionable next steps, current owners, dependencies and closure tests.
- Separate unreviewed candidates from ready tasks; preserve source history.
- Reserve routing before native delivery; uncertain delivery blocks replay.
- Require checked completion artifacts; completed chat/status alone cannot close
  an outcome. Keep human decisions and unknown source state visible.
- Reconcile the live queue from current source evidence, then demonstrate an
  authorized owner delivery and independently checked result.
- Pass source/negative tests, normal publication, installed readback and the
  offline dashboard practical-use check.

## Why reuse Mission Control

The existing store already has transactional locks, atomic updates, source
identity, supported collectors and the selected daily review. Asana provides
trigger/action workflows and Reclaim provides calendar planning, but neither
existing integration supplies this local multi-provider transcript/owner graph.
Reuse avoids migration and another state store; no measured claim of universal
product superiority is made. Reconsider replacement if maintaining these narrow
adapters costs more than a demonstrated supported alternative.

References checked October29: https://help.asana.com/s/article/rule-triggers;
https://help.asana.com/s/article/automation-scope;
https://help.reclaim.ai/en/articles/15280604-reclaim-2-0-faq.

## Baseline findings

- Ready tasks, machine candidates and old prose can be mixed in one list.
- Many distinct repo items have the same `Repo: ...` title because intake
  copies the source title instead of the actual task text. They are not proven
  duplicates; merge by title would lose work.
- The current daily review is deliberately read-only; its verified task
  findings do not automatically deliver work to the owner.
- Existing `done` accepts a status without closure evidence. New managed
  outcomes need a checked verification record while legacy history stays honest.

## Verification and recovery

Trust gate on: this changes an authoritative process. The repaired candidate
reuses the existing locked store and daily review; no dependencies or schedulers
were added. Source intake now uses task text and preserves missing-source rows.
Managed outcomes have separate readiness, reserved delivery and verification.

Independent review in the existing review-owner chat reproduced five failures:
unconfirmed delivery closure, stale owner-plan reuse, superseded-task revival,
parent rollup closure and missing-source deletion. Its later recheck also caught
receipt retargeting. All are repaired with public-CLI/feed regressions. The five
original rejection cases fail against the exact independently hashed pre-fix
snapshot; the retarget case fails against its separately hashed prior revision.
Current focused regression suite:18 passed; collector fixture:7 passed. These
fixtures preserve the live ledger and start no provider or native-chat work.

The first full local verifier completed41 suites with one unchanged panel-browser
load timeout (3 seconds). Dashboard browser checks passed496 assertions. The
unchanged panel suite then passed22/22 in isolation. Normal publication still
runs the required full gate. Exact private review/test receipts are retained
under `~/.codex/automation-state/unfinished-work-review/mc-actionable-20261029-*`.
Independent re-review passed18 repository regressions and8additional public
contract checks on the exact eight bound source/test/runbook files. It verified
the installed runtime and live prompt were unchanged and the ledger had no
managed/dispatch nodes before releasing the hold at17:40UTC. Publication,
installation and live acceptance remain separate next gates.

## Installed acceptance

At17:42UTC the normal installer copied committed implementation753d151 into the
existing runtime, with launchd installation disabled. The installed stamp passed
with no missing, unexpected or mismatched files. The actual installed dashboard
was opened in an isolated test browser: both active work items, next actions and
exact owner links rendered correctly; the browser exited after the check.

The existing08:00 review was updated through the native app and read back with
its original ID, owner, cadence and settings. Its next nominal wake is October30
08:00 America/Los_Angeles. The independent Gmail07:00/Friday16:00 jobs were read
back unchanged. There is no new monitor or schedule.

The first live eight-item source reconciliation is reserved and delivered to the
existing review owner, bound to native turn01a188c4-8719-74f1-aa9b-23543cca674a.
It remains Doing until the integrator checks its exact terminal result and all
acceptance artifacts. Its proof is recorded under the private existing state
directory `mc-actionable-20261029-live/`; publication and final acceptance are
recorded in `mc-actionable-20261029-closeout.json`. These receipts are the current
operational continuation of this source record. A later manual check never
stands in for the next natural daily review.

## Complete frozen candidate review

Trevor's later October29 request explicitly covered the remaining414 candidates.
The frozen cohort has414 unique reviewed IDs:146 stale/non-task/answered captures
retired,16 duplicates linked to canonical outcomes,18 accepted items assigned,
and234 evidence gaps retained with agent next actions. Three exact old choices
were answered in later user messages. This is review coverage, not completion
of the underlying projects or a claim of corpus-wide capture.

Four bounded continuations reached existing native owners: Hermes reliability,
storage, Gillette form requirements, and website consolidation. Each reserves
one attempt and binds its marker to the actual native turn. The storage candidate
links the already existing canonical task. Fifteen Claude/Cursor items remain
assigned but blocked on current owner/access proof. No retired workflow, Gmail
writer, external communication, model selection or schedule was changed.

The existing private review directory is
`~/.codex/automation-state/unfinished-work-review/candidate-review-20261029-01a16afb/`.
Its inventory, four per-source reports, independent review, application journal,
reconciliation plan and native receipts retain the exact proof. The existing
daily08:00 reviewer owns later artifact-backed completion verification.

Capture repairs use one repository integration ref for branch ancestry; a stale
local main no longer makes published tips look unmerged. Unknown integration
stays explicit. Closeouts now distinguish actual fields from quotes, code and
empty Markdown values. Register status is parsed from its status column; landed
is not verified, and unreadable input preserves both register capture paths.
Todo continuation context and dated nightly provenance survive intake. Parser6
uses the existing bounded cursor invalidation rather than an additional scanner.

Independent reviewers challenged the exact patches and all414 dispositions.
One retained external-drive worktree was correctly kept unknown: later Hermes
release evidence did not close that different outcome. The first full gate
exposed inherited Python3.9 selection and a redacted nightly source-date test;
both were corrected without weakening checks. A later gate found the browser
probe waiting twice for one reload. The redundant deprecated navigation waits
were removed; all reload and UI persistence assertions remain.

Source validation, publication, installed parity and later natural operation
remain separate receipts. The final closeout artifact records each completed
gate and every remaining limit. Reverting the owned source commit and restoring
the prior checked runtime is the code rollback; do not undo reviewed ledger
history or replay any reserved delivery.

## Evidence Checked

Confirmed: source and negative regressions, independent exact-snapshot review,
installed hashes, rendered owner links, native delivery marker/turn and saved
schedule. The live reconciliation is a bounded batch, not full corpus coverage.

## Decision Status

Confirmed: reuse meets the demonstrated local coordination requirements without
another dependency or scheduler. Inferred: this is the best practical fit for
Trevor's current setup. Needs More Evidence: sustained usefulness and the next
natural review under the new contract. Do Not Do Yet: claim the whole candidate
inventory is audited or any partial project is completed.

## Challenge Findings

The first review found real false-closure paths despite passing initial tests.
Independent negative cases were necessary. Same-title rows were not exact
duplicates, and source omission was not completion. The code checks proof
bindings, not the truth of arbitrary prose; source judgment remains necessary.

## Unresolved

Candidate coverage and owner-adapter availability remain explicit limitations.
Daily coordination is not instant event processing for every provider. The next
natural08:00 review verifies original terminal outcomes and continues its saved
candidate cursor; no extra watchdog is warranted by this implementation.

Private live before-images and native delivery/evidence receipts belong in the
existing unfinished-work-review state. Rollback uses the owned source commit,
checked runtime preimages and original review prompt; never erases later task
history or repeats an uncertain dispatch.

## Live findings and focused follow-up

The exact delivered reconciliation turn completed with no native error. Its
eight selected nodes, retained source identities/notes, source-answer evidence,
artifact hashes and current queue were independently checked by the integrator.
The dispatched outcome is now Verified done. One cancelled Telegram question was
retired; no duplicate merge was supported. Finance retains its already-active
owner, Gmail waits for its existing worker, and unresolved questions stay open.
The batch did not source-audit416 machine candidates and59 other curated rows.

Live use exposed a stale cached `work_queue` in JSON exports after CLI changes.
The export now computes its in-memory view through the same pure function as
`queue`; reads never rewrite the store. The regression fails on the old helper
and passes through Ready/Doing/Waiting/retired transitions with unchanged nodes,
history and persisted bytes. Independent review passed19 repository tests and
35 additional checks; the old installed helper failed9 freshness checks. Its
exact runtime/review hashes are in `mc-json-queue-20261029-independent/` under the
same private review state. That fix was held out of installation until PASS.

Normal publication initially stopped at the unchanged panel test suite. Besides
three-second fixture navigation deadlines, synthetic fresh data aged against
real time during slow browser setup. Test setup now fixes Date to the fixture's
NOW while real timers run, and gives navigation15seconds separately from the
unchanged3second assertions. Production panel code and all rejection cases are
unchanged. A bounded aging reproduction fails on the prior fixture clock and
passes after the correction; the complete repaired panel suite passes22/22.
Independent source review found no issue in the five setup lines. The first
over-broad aging probe timed out and is not acceptance evidence; its exact owned
orphan browser was identified by start time and fixture cwd, stopped and reaped.

Final publication/installation and the next natural review still require their
own evidence in `mc-actionable-20261029-closeout.json`; none is inferred from this
focused follow-up. No additional live routing demonstration is needed.
