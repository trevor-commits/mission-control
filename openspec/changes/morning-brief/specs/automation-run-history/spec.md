## ADDED Requirements

### Requirement: Polls are not runs
Automation history MUST append an event only when a distinct trusted `run_key` changes; repeated collector observations of one run MUST update observation metadata without adding events.

#### Scenario: Repeated failed polls do not inflate a streak
- **WHEN** the collector observes the same failed run twelve times with unchanged evidence
- **THEN** history contains one failed event and `failure_streak` equals one

### Requirement: Trusted distinct-run identity
The collector MUST derive `run_key` from the job label, exit state, and newest trustworthy run evidence or error-log `mtime_ns`; if no trustworthy marker exists it MUST report `history_unknown` and MUST NOT invent an event.

#### Scenario: New error evidence creates a new failed run
- **WHEN** exit status remains nonzero but the trusted error evidence advances to a new `mtime_ns`
- **THEN** a second distinct failed event is appended and the failure streak becomes two

#### Scenario: Unparseable state preserves history
- **WHEN** launchctl output is unparseable and no trustworthy run evidence exists
- **THEN** existing history remains unchanged and history confidence is unknown

### Requirement: Failure streak semantics
Failure streaks MUST count consecutive distinct failed runs, MUST reset after a distinct successful run, and MUST NOT classify stale, yellow, offline-media, degraded, or repeated keepalive observations as new failures.

#### Scenario: Success resets the streak
- **WHEN** a distinct success event follows failed events
- **THEN** the reported failure streak is zero

#### Scenario: Persistent keepalive failure is one episode
- **WHEN** a keepalive job remains red across multiple polls without a state transition
- **THEN** the history records one failure episode rather than one event per poll

### Requirement: Atomic bounded persistence
History updates MUST be protected by a lock and atomic replacement, MUST deduplicate after restart and concurrent collection, and MUST retain at most twenty unique events per job.

#### Scenario: Concurrent writers preserve unique events
- **WHEN** two collectors update the same job history concurrently
- **THEN** the file remains valid, contains no duplicate run keys, and enforces the twenty-event cap

### Requirement: Schedule and evidence honesty
Automation status MUST resolve the newest matching evidence when a registry path uses a supported glob, and MUST calculate next-run estimates for `HH:MM daily` and `every Ns` using an injectable current time.

#### Scenario: Daily and interval schedules produce future estimates
- **WHEN** fake time and evidence are supplied for both supported schedule forms
- **THEN** each next-run estimate is the next valid occurrence and the newest glob match determines freshness

### Requirement: Operator rendering
The automation feed MUST expose history confidence, failure streak, recent distinct events, next-run estimate, and a copyable `launchctl kickstart` command; the dashboard MUST render them without executing shell commands.

#### Scenario: Automation card renders honest history
- **WHEN** a fixture includes distinct success/failure events and a next-run estimate
- **THEN** the Automation card shows the streak, recent-run strip, next run, and a copyable run command
