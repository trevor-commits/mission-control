## ADDED Requirements

### Requirement: Additive migration preserves graph state
The graph schema MUST add outcome, stable-item, update, and resolution-evidence fields through an idempotent migration that preserves current sessions, edges, suppressions, open ends, and the future-version guard.

#### Scenario: Current schema migrates twice
- **WHEN** a current v4 fixture is opened and migration runs twice
- **THEN** existing rows remain intact, new structures exist once, and schema version remains valid

### Requirement: Provider and node-kind hygiene
Chat outcome/lineage processing MUST allow only `claude`, `codex`, `cursor`, `hermes`, and `copilot`; it MUST distinguish chat nodes from repo nodes, exclude raw malformed provider values from rendering, and count unknown sources without discarding safe real content.

#### Scenario: Garbage provider and repo node coexist
- **WHEN** the DB contains `${PARENT_PROVIDER}`, `bridge`, and a valid synthetic repo node
- **THEN** garbage values never become lineage/render labels, the repo node remains an Open work source, and safe unknown content is labeled only `Unknown source`

### Requirement: Bounded Tier 1 parsing
Tier 1 MUST parse only bounded assistant-tail content for reply-v5/closeout, Codex closeout, audit-report, provenance/status/commit, and packet/handoff shapes; packet-shaped tails MUST be classified `authored_handoff` rather than accomplishments. One structured `NEEDS YOU` block MUST remain one coherent operator decision, fenced command fragments MUST stay out of narrative, deterministic safe commands MUST remain structured anchors, and a parser-version change MUST invalidate unchanged-source cursors for both file and Hermes inputs.

#### Scenario: Handoff packet does not claim execution
- **WHEN** a tail ends with Goal/Runner/Model and paste-ready instructions
- **THEN** the card records an authored handoff and does not place the requested future work in `did`

#### Scenario: Numbered operator procedure stays coherent
- **WHEN** one `NEEDS YOU` block contains narrative plus a fenced multi-step shell procedure
- **THEN** Tier 1 emits one readable decision, omits fence/command fragments from narrative, and retains allowlisted safe commands only in deterministic anchors

### Requirement: Isolated Tier 2 extraction
Tier 2 MUST run only in `extract-outcomes`, MUST never be invoked by ingest or export, MUST close DB connections and release collector locks before model calls, and MUST write cards in short per-card WAL transactions.

#### Scenario: Slow model overlaps ingest
- **WHEN** a test model blocks while the normal collector ingests
- **THEN** ingest completes within its expected bound and no long write transaction is held by the extractor

### Requirement: Model output is narrative only
Tier 2 MAY generate inferred narrative but MUST discard model-generated commands, IDs, SHAs, and repo names unless they are separately present in deterministic anchors; all action fields MUST originate from structured source text or deterministic code.

#### Scenario: Model invents a command
- **WHEN** the model response contains a command absent from structured anchors
- **THEN** the command is discarded and cannot enter an outcome action or decision queue

### Requirement: Cache, budget, lock, and provider controls
Tier 2 MUST cache by sanitized tail hash, enforce daily call/token caps, use the installed OAuth-lock wrapper, treat exit 75 as a benign defer, honor global and per-source-provider kill switches, and fail open to Tier 1 with health counters.

#### Scenario: Budget is zero
- **WHEN** the daily budget is configured to zero
- **THEN** no model call occurs, structured outcomes remain available, and the budget skip is visible in machinery health

### Requirement: Explicit evidence resolves open work
Each `chat_open_end` MUST have a kind-salted source-derived stable item key and MUST resolve only through an exact same-session resolution marker, an exact downstream `Resolves: <item-key>` on a verified continuation/spawn edge, an explicit manual resolution/suppression, or a versioned deterministic parser supersession that replaces prior `NEEDS YOU` representations from the same selected source message and same sanitized content hash with one coherent item. Parser migration MUST NOT treat a changed, missing, unstructured, rewritten-under-the-same-ID, or merely omitting source message as resolution evidence.

#### Scenario: Finalized extraction omits an item
- **WHEN** a later finalized successful extraction does not contain an existing item
- **THEN** the item remains open with no resolution evidence

#### Scenario: Parser upgrade compacts only the same selected source
- **WHEN** a new parser version reprocesses the same structured source message and replaces multiple prior `NEEDS YOU` fragments with one coherent item
- **THEN** only those superseded fragments resolve with `parser_migration` evidence; a changed or omitted source leaves prior work open

#### Scenario: Exact downstream key resolves
- **WHEN** a verified downstream session contains `Resolves: <item-key>`
- **THEN** the item resolves and persists resolution evidence type and reference

#### Scenario: Same text under two kinds does not collide
- **WHEN** identical text appears under two different open-end kinds
- **THEN** two distinct stable items coexist

### Requirement: Late closeouts re-emit updates
Outcome cards MUST carry tail hash, extraction status, finalized state, updated time, method, confidence, and source span; a changed late closeout after briefing MUST create an update event eligible for the next brief.

#### Scenario: Closeout arrives after first brief
- **WHEN** a non-finalized card was included and a later tail produces a finalized changed card
- **THEN** the next brief can show it as updated since the prior brief

### Requirement: No-call coverage precedes backfill
Coverage planning MUST first compute per-provider sessions, tail sizes, grammar hits, eligible model calls, and projected token/quota load without calling a model; only after privacy tests MAY a bounded provider sample measure real tokens/latency and set caps before backfill.

#### Scenario: Coverage plan mode runs
- **WHEN** `outcome-coverage --days 7 --json` runs in plan mode
- **THEN** it makes zero model calls and reports eligible counts, bytes/tokens, grammar families, packet tails, and unparseable sessions

### Requirement: Cost reporting is honest
Coverage output MUST report observed or projected calls/day, input/output tokens/day, quota/headroom impact, and MAY report dated configurable API-equivalent cost clearly labeled as modeled rather than charged.

#### Scenario: Subscription-backed extraction is projected
- **WHEN** the model route is subscription-backed
- **THEN** the report does not claim API dollars were charged and labels any price calculation as an equivalent model
