## ADDED Requirements

### Requirement: Shared field-aware policy
Mission Control MUST use one shared egress policy to classify and sanitize every field before model input, outcome storage, decision storage, error persistence, structured sidecar output, and notification chunk delivery.

#### Scenario: Every boundary uses the same policy
- **WHEN** a narrative, action, identifier, error, or notification field crosses one of the defined boundaries
- **THEN** the shared policy is invoked with an explicit field class and returns sanitized content or a fail-closed drop result

### Requirement: Sensitive content fails closed
The policy MUST drop or replace secrets, credentials, denylisted terms, email addresses, and phone numbers for every field class, and MUST increment non-content health counters without logging the rejected value.

#### Scenario: Sensitive action command is rejected
- **WHEN** an otherwise valid action command contains a token, email address, or phone number
- **THEN** the command is excluded, a redaction counter increases, and neither logs nor errors contain the sensitive value

### Requirement: Narrative and action paths differ
The policy MUST remove raw host paths from transcript-derived narrative except approved repo roots and known tool paths, while action fields MAY preserve exact local paths that are necessary to execute a deterministic command.

#### Scenario: Same path receives field-specific treatment
- **WHEN** the same local path appears in `did` narrative and in a structured `action_cmd`
- **THEN** the narrative is sanitized and the deterministic action retains the necessary path after sensitive-content screening

### Requirement: Cross-provider model egress is explicit
Before any transcript tail is sent to a model from another provider, the system MUST sanitize it, exclude raw tool output by default, enforce byte/message bounds, honor per-source-provider kill switches, and record only provider, size, method, timing, and result status metadata.

#### Scenario: Codex tail is prepared for Anthropic model call
- **WHEN** a bounded Codex transcript tail is selected for Tier 2 extraction
- **THEN** raw tool results and prohibited fields are absent, the provider-specific kill switch is honored, and logs contain counts/status but no transcript text

### Requirement: Synthetic privacy fixtures
Committed tests MUST use synthetic fixtures and MUST cover prompts, tails, argv, temporary files, errors, logs, sidecar fields, and notification chunks for prohibited content leakage.

#### Scenario: Privacy matrix is executed
- **WHEN** the field-matrix test suite runs
- **THEN** every egress class is tested and no prohibited token, email, phone, or raw path appears in any captured output where it is disallowed
