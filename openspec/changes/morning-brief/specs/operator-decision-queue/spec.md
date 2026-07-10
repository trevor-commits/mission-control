## ADDED Requirements

### Requirement: Transactional decision identity and events
The decision queue MUST use SQLite WAL with short immediate transactions and stable identity from `source_kind + source_key`, plus evidence fingerprint, trust state, provenance, first/last seen, state, alert receipt, and structured action command.

#### Scenario: Concurrent ingest, dismiss, and alert
- **WHEN** sync, dismissal, and alert processes operate on one item concurrently
- **THEN** the DB remains valid and produces one deterministic state and at most one alert receipt for the evidence fingerprint

### Requirement: Confirmed and inferred decisions are separate
Confirmed decisions MUST originate from manual/structured evidence or independently anchored high-confidence inference; model-only candidates MUST be labeled inferred and MUST NOT enter the red NEEDS YOU queue or carry commands.

#### Scenario: Low-confidence LLM decision is observed
- **WHEN** a model-only decision has no deterministic anchor
- **THEN** it is stored/rendered only as an inferred possible follow-up and no alert/action command is produced

### Requirement: Cross-session high-recall persistence
A structured decision MUST remain open until an exact answering user turn, an exact downstream resolution key on a verified edge, or a manual resolution proves closure; parser absence, generic downstream completion, and model omission MUST NOT resolve it.

#### Scenario: Downstream task says done without the key
- **WHEN** a child session contains generic completion language but no exact decision/item key
- **THEN** the parent decision remains open

### Requirement: Dismissal, resolution, and recurrence differ
A dismissal MUST remain dismissed for the same evidence fingerprint, resolution MUST record proof, and materially new evidence MUST create a recurrence/reopen transition rather than silently overwriting history.

#### Scenario: Same dismissed evidence is re-ingested
- **WHEN** an unchanged source item is collected after dismissal
- **THEN** it remains dismissed and does not alert again

#### Scenario: Evidence materially changes
- **WHEN** the source fingerprint changes after dismissal or resolution
- **THEN** a recurrence event reopens the item with preserved history

### Requirement: Alerting is deduplicated and observable
The alert command MUST send each new confirmed open item at most once per 24 hours through a stub-capable fixed-argv path, MUST record success/failure, and MUST not stamp failed sends as alerted.

#### Scenario: Process restarts after successful alert
- **WHEN** the alert ticker restarts within 24 hours
- **THEN** it does not resend the same evidence fingerprint

### Requirement: Dashboard and CLI share the queue
Home MUST pin confirmed open decisions above other attention rows, and `dashboard decide dismiss <id>` MUST write the same transactional event store without executing the proposed action.

#### Scenario: Dismiss round-trip
- **WHEN** the operator copies/runs the dismiss command
- **THEN** the item leaves the pinned open view and remains auditable in decision history
