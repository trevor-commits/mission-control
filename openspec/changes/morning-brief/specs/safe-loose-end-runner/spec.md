## ADDED Requirements

### Requirement: Default dry-run and hard disable
The loose-end runner MUST default to dry-run, MUST make no repo/ref/remote changes in that mode, and MUST stop before planning or action when `$MISSION_CONTROL_HOME/loose-end-runner/DISABLE` exists.

#### Scenario: Default invocation
- **WHEN** the runner is invoked without an enable flag
- **THEN** it reports proposed tiers/actions and changes no files, refs, or remotes

### Requirement: Hard prohibitions
The runner MUST never merge, force-push, delete, edit human documents, act on a default/protected branch, act on recent or unknown-activity work, or spawn delegate-tier workers in this implementation.

#### Scenario: Prohibited item is encountered
- **WHEN** an open end would require a prohibited action
- **THEN** the runner refuses it, records the reason, and routes it only as a proposal/decision

### Requirement: Safe push uses live facts
The runner MUST recompute structured Git facts immediately before any proposed or future enabled push and MUST require every eligibility guard; it MUST use the exact fixed argv/refspec emitted from structured facts.

#### Scenario: Branch is behind upstream
- **WHEN** a branch is ahead and behind
- **THEN** the runner refuses push and records divergence as a human decision

### Requirement: Only named safe-tier behavior is implemented
The runner MUST limit itself to proposing an eligible explicit branch push, invoking the existing safe open-end reconciliation pass, and detecting already-satisfied todo items without editing them.

#### Scenario: Satisfied todo item is found
- **WHEN** deterministic evidence suggests an unchecked item is already satisfied
- **THEN** the runner reports a proposal and does not modify `todo.md`

### Requirement: Exact before-and-after audit log
Every considered action MUST append an atomic permission-restricted JSONL record with timestamp, item ID, tier, reason, exact safe argv or proposal, and redacted before/after fact snapshots; credentials and raw sensitive content MUST never appear.

#### Scenario: Dry-run proposal is logged
- **WHEN** dry-run evaluates an eligible branch
- **THEN** the report records the proposed explicit refspec and unchanged before/after facts

### Requirement: Live enablement is outside implementation completion
The initial implementation MUST NOT enable automatic pushing; one live-ledger dry-run MUST receive a separate independent review and a later explicit activation decision before any non-dry-run scheduler or flag is accepted.

#### Scenario: Implementation is otherwise complete
- **WHEN** code, tests, and a reviewed dry-run exist but no activation decision exists
- **THEN** the runner remains default-dry-run and no live auto-push launchd job is enabled
