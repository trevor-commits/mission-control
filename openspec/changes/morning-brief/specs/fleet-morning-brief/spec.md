## ADDED Requirements

### Requirement: Deterministic thin brief ships independently
The composer MUST produce a useful brief from deterministic Mission Control feeds before session-outcome enrichment and MUST continue to do so when LLM extraction is disabled, over budget, deferred, or failed.

#### Scenario: Outcomes are unavailable
- **WHEN** no session outcome cards exist or `MORNING_BRIEF_LLM=0`
- **THEN** the brief still contains decisions from structured sources, Git changes, open-work deltas, machinery health, usage headroom, and explicit source-quality labels

### Requirement: Structured and human outputs
Each compose MUST write an atomic human Markdown file and an atomic structured `latest.json` sidecar containing the brief ID, selection high-water marks, timestamps, input freshness, ordered section lines, trust labels, decisions, and delivery state; the dashboard MUST consume the sidecar rather than parse Markdown.

#### Scenario: Dashboard reads a composed brief
- **WHEN** the collector processes a valid `latest.json`
- **THEN** it emits the normal local feed envelope and Home renders the summary without parsing Markdown

### Requirement: Input freshness is asserted
At compose time the system MUST check recency and non-emptiness for every configured input using its declared cadence and required/optional status, and MUST display a top-level stale-data warning for any violation.

#### Scenario: Weekly input is not judged by a daily cadence
- **WHEN** a weekly delegation digest is six days old and its configured cadence is weekly
- **THEN** it is not falsely marked stale while a missing required daily input is marked stale

### Requirement: Compound snapshot cursor
The composer MUST select source events from a stable snapshot using compound high-water keys such as `(updated_at, stable_id)`, MUST persist the selected marks with the brief, and MUST NOT advance delivery cursors for preview or failed/partial delivery.

#### Scenario: Equal timestamps are not lost
- **WHEN** two source events share an `updated_at` value but have different stable IDs
- **THEN** both appear exactly once across successful briefs

#### Scenario: Preview does not consume work
- **WHEN** `--print` or preview mode renders a brief
- **THEN** the scheduled delivery cursor remains unchanged

### Requirement: NEEDS YOU trust and size
The red NEEDS YOU block MUST contain only manual/structured facts or inference independently anchored to deterministic evidence, MUST use visible `Confirmed` trust wording, MUST fit one phone screen under the configured cap, and MUST preserve exact structured commands, IDs, repo names, and SHAs.

#### Scenario: LLM-only follow-up is not actionable
- **WHEN** an outcome contains a model-only decision or command suggestion without a deterministic anchor
- **THEN** the command is discarded and the narrative appears only under `Possible follow-ups — Inferred`, never NEEDS YOU

### Requirement: Brief organization and volume
The brief MUST order NEEDS YOU, What happened, Open work changes, Machinery health, and Usage headroom; MUST rank a configurable top-N; MUST collapse lower-value items; and MUST label inferred lines with the word `Inferred` rather than a subtle symbol.

#### Scenario: High-volume morning remains bounded
- **WHEN** more than the configured number of outcome lines qualify
- **THEN** only the ranked top-N render and the remainder is summarized by count without dropping NEEDS YOU items

### Requirement: Honest provider presentation
Only allowlisted chat providers may be lineage-grouped; repo nodes remain valid Open work sources; malformed/unknown source labels MUST NOT render raw and MAY contribute a safe `Unknown source` flat card plus a machinery-health count.

#### Scenario: Synthetic repo node is preserved
- **WHEN** a `repo:<name>` node contributes open work
- **THEN** it remains in Open work but never becomes a chat lineage node

### Requirement: Chunk delivery is resumable and idempotent
Each notification chunk MUST carry brief ID, chunk index, total, and content hash; confirmed chunks MUST be recorded; partial retry MUST send only unconfirmed chunks; and resending an already completed brief MUST be a no-op.

#### Scenario: Second chunk fails
- **WHEN** chunk one is confirmed and chunk two fails
- **THEN** delivery remains failed, the cursor does not advance, the deadman treats it as unsent, and retry starts with chunk two

### Requirement: Independent delivery deadman
The deadman MUST check missing, stale, empty, failed, and partially delivered status independently from the composer, MUST throttle alerts, and MUST not log or expose tokens.

#### Scenario: Brief file exists but send is partial
- **WHEN** Markdown exists and send status shows fewer confirmed chunks than total
- **THEN** the deadman emits one throttled failure alert and does not consider the brief delivered

### Requirement: Implemented and verified states differ
The project MUST record `implemented` after code/tests/install/manual delivery/dry-run evidence and MUST reserve `verified` for approximately five real mornings that meet comprehension/action criteria and produce a notification consolidation decision.

#### Scenario: Same-day build passes all tests
- **WHEN** implementation-day checks pass but five morning observations do not yet exist
- **THEN** ER-107 and the OpenSpec change remain implemented/pending-proof rather than verified/archived-complete
