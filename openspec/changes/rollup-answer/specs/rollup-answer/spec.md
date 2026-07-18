## ADDED Requirements

### Requirement: Strict rollup targeting
The system MUST accept a rollup answer only for a current open card and primary decision, MUST target the primary plus only action+owner+target equivalents, and MUST return every independent or already-pending member visibly without changing it.

#### Scenario: Same presentation text has a different owner
- **WHEN** two open members share a presentation card but have different originating owners
- **THEN** answering one targets only the primary and returns the other as independent

### Requirement: Durable answered-pending interpretation
Every targeted member MUST remain `open` and MUST expose one current `answered_pending` event containing the choice, source, card, primary, batch, and private artifact references.

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
The system MUST stage every private member artifact before the database transition, MUST record all target events in one transaction, and MUST publish the batch with one atomic directory rename.

#### Scenario: Failure before database commit
- **WHEN** staging, directory validation, or scope revalidation fails
- **THEN** no target receives a pending event and no published batch appears

#### Scenario: Failure after database commit
- **WHEN** publication fails after all pending events commit
- **THEN** no partial published batch appears and exact replay can publish the complete batch without duplicate events

### Requirement: Replay and changed-evidence semantics
Exact current scope plus choice MUST be idempotent; a conflicting choice or partial current pending set MUST fail closed; a new evidence fingerprint MUST make the member answerable again.

#### Scenario: Exact replay
- **WHEN** the same card, primary, target fingerprints, and choice are submitted again
- **THEN** the command succeeds without inserting another pending event or overwriting a different batch

#### Scenario: Evidence changes
- **WHEN** an answered-pending member is re-ingested with a materially different evidence fingerprint
- **THEN** the prior pending event remains in history but is no longer active and a new answer may be recorded
