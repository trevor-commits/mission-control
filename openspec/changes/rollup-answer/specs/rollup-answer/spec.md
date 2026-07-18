## ADDED Requirements

### Requirement: Strict rollup targeting
The system MUST accept a rollup answer only for a current open card and primary decision, MUST target the primary plus only action+owner+target equivalents, and MUST return every independent or already-pending member visibly without changing it.

#### Scenario: Same presentation text has a different owner
- **WHEN** two open members share a presentation card but have different originating owners
- **THEN** answering one targets only the primary and returns the other as independent

### Requirement: Durable answered-pending interpretation
Every targeted member MUST remain `open` and MUST expose one current `answered_pending` event containing the choice, source/resume metadata, card, primary, batch, canonical manifest digest, member sets, and private artifact references.

#### Scenario: A rollup answer is recorded
- **WHEN** the operator answers a valid card
- **THEN** all eligible targets remain open, show awaiting owner consumption, and receive no terminal resolution event

### Requirement: Pending suppression and visibility
Current pending members MUST remain visible in local decision surfaces but MUST be excluded from ordinary alerts, Morning Brief `NEEDS YOU`, dismissal, and single-answer commands.

#### Scenario: Alert ticker sees a pending member
- **WHEN** normal or targeted alert eligibility is evaluated
- **THEN** the member is skipped with an explicit `answered_pending_consumption` reason and no send is attempted

### Requirement: Verified per-member consumption
Current pending members MUST resolve only through existing graph-verified answering-user-turn or downstream-resolution-key evidence for that exact member.

#### Scenario: Manual resolution is attempted
- **WHEN** a caller tries `manual_resolution` on a current pending member
- **THEN** the command fails and the member remains open and pending

#### Scenario: Exact owner evidence is verified
- **WHEN** chat graph proves the member's exact resolution key and evidence reference
- **THEN** only that member resolves and other batch members remain open pending

### Requirement: Atomic and recoverable batch publication
The system MUST stage every private member artifact before the database transition, MUST record all target events plus the canonical manifest digest in one transaction, MUST bind pre/post-commit verification to the same held batch directory, and MUST publish the batch with one atomic directory rename.

#### Scenario: Failure before database commit
- **WHEN** staging, directory validation, or scope revalidation fails
- **THEN** no target receives a pending event and no published batch appears

#### Scenario: Failure after database commit
- **WHEN** publication fails after all pending events commit
- **THEN** no partial published batch appears and exact replay can publish the complete batch without duplicate events

#### Scenario: Staged bytes change after commit
- **WHEN** a staged prompt or manifest changes after the database receipt commits
- **THEN** the public command fails, preserves the suspect directory under a private quarantine name, and exact replay reconstructs the persisted digest without a duplicate event

#### Scenario: Batch parent is replaced after commit
- **WHEN** the path-visible batch parent stops naming the descriptor-pinned parent after the database receipt commits
- **THEN** the command does not report a missing or redirected batch path, preserves the old-parent artifact, and exact replay publishes below the current parent

#### Scenario: Existing published batch changes during replay
- **WHEN** an exact replay has opened a receipt-backed published batch and its held bytes or path-visible parent changes before replay completes
- **THEN** the command fails, quarantines the exact directory still bound to the held descriptor under its pinned parent, removes invalid canonical visibility, and a later exact replay rebuilds without duplicate events

### Requirement: Replay and changed-evidence semantics
Exact current scope plus choice MUST be idempotent; a conflicting choice or partial current pending set MUST fail closed; a new evidence fingerprint MUST make the member answerable again.

#### Scenario: Exact replay
- **WHEN** the same card, primary, target fingerprints, and choice are submitted again
- **THEN** the command reproduces the persisted manifest digest and succeeds without inserting another pending event or overwriting a valid different batch

#### Scenario: Evidence changes
- **WHEN** an answered-pending member is re-ingested with a materially different evidence fingerprint
- **THEN** the prior pending event remains in history but is no longer active and a new answer may be recorded

### Requirement: Public decision-feed coherence without egress
The public dashboard answer and rollup-answer commands MUST run the strict decisions collector with automatic alerts disabled, MUST update Home and Morning Brief before reporting full success, and MUST surface a committed-but-refresh-failed result without sending to any provider.

#### Scenario: Feed refresh succeeds
- **WHEN** a rollup answer commits and the local decisions collector succeeds
- **THEN** the feed exposes every target as answered-pending, Morning Brief omits those exact targets from `NEEDS YOU`, and no provider sender is invoked

#### Scenario: A stale installed decision reader exists
- **WHEN** the source dashboard command writes a rollup answer while an older executable decision reader exists under the temporary Mission Control state home
- **THEN** the strict collector uses the same runtime implementation as the writer, exposes `answer_pending`, and does not invoke the stale installed reader

#### Scenario: Feed refresh fails after commit
- **WHEN** the database and private artifacts commit but the strict decisions collector fails
- **THEN** the command returns nonzero, prints the committed structured receipt, identifies the degraded refresh on stderr, and permits an exact idempotent replay

### Requirement: Bounded decision views preserve actionable work
Home and panel MUST stably order actionable decisions before answered-pending receipts before applying display limits, while preserving relative order within both groups.

#### Scenario: Pending rows precede the only actionable row
- **WHEN** more pending rows than the visible limit precede a later actionable decision
- **THEN** a `Needs you` view displays the actionable decision and its control before pending receipt rows
