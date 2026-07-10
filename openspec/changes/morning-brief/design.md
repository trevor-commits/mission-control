## Context

Mission Control is a local static dashboard backed by shell and standard-library Python collectors. It already has a SQLite chat graph, a unified `open_ends` ledger, Git and automation feeds, usage state, and a five-minute installed collector. The missing product layer is a concise, trustworthy explanation of fleet work and decisions. Existing transcript data can contain secrets and personal data; launchd has a sparse environment; multiple processes may touch decision and graph state; and model calls can block or fail under the OAuth lock.

Trevor approved the Fable plan and the U1-U7 audit upgrades. This design treats the work as one outcome on one Mission Control branch with granular commits and independent review. Cross-repo Phase 0 repairs and source cards use their own repos and commits, but do not fragment the Mission Control product into six merge branches.

## Goals / Non-Goals

**Goals:**

- Ship a deterministic thin brief before session-outcome enrichment.
- Preserve a useful brief when LLM extraction is disabled, deferred, over budget, or unavailable.
- Extract session outcomes without blocking ingest/export and with visible provenance.
- Keep unanswered decisions open until positive evidence proves resolution.
- Make stale inputs and failed delivery visible.
- Provide structured Git facts and a conservative default-dry-run safe tier.
- Prove the product through tests, installed runtime evidence, independent audit, and real mornings.

**Non-Goals:**

- Building a new tool, server, framework, or general memory layer.
- Rewriting nightly review, delegation audit, or other notification systems.
- Claiming lineage for providers without allowlisted graph evidence.
- LLM-driven decision resolution or autonomous branch judgment.
- Merging, force-pushing, deleting, editing human documents, or spawning repair workers.
- Enabling non-dry-run runner actions before separate reviewed evidence and an activation decision.

## Decisions

### D1: Deterministic walking skeleton precedes outcome enrichment

- **Choice:** implement job history and the thin composer/delivery contract before session outcomes.
- **Reason:** deterministic inputs already deliver value and independently test the fragile compose/redact/cursor/delivery/deadman chain.
- **Alternative considered:** hold the brief until outcome cards exist. Rejected because it makes the highest-risk component load-bearing and delays user value.
- **Ordering clarification:** Phase 2a must precede only the outcome-enriched composer, not the thin deterministic brief.

### D2: One outcome branch, granular commits

- **Choice:** keep Mission Control work on `codex/morning-brief`, with bounded TDD commits and separate reviewers.
- **Reason:** the feature shares schemas, dashboard, CLI, and runtime installers. Six branches would create integration drift and conflict with the repo's one-outcome branch guidance.
- **Alternative considered:** one branch per phase. Rejected for this repo; cross-repo repairs still land in their owning repos.

### D3: One field-aware egress module

- **Choice:** centralize field classification and sanitization. Secrets, denylisted terms, email, and phone fail closed everywhere. Narrative strips local paths except approved roots; action commands preserve required paths.
- **Reason:** boundary-specific regex copies drift and make it impossible to prove privacy.
- **Alternative considered:** reuse each caller's existing redaction. Rejected because the output fields have different path semantics and multiple egress boundaries.

### D4: Two extraction lanes, never inside collector locks

- **Choice:** Tier 1 parses bounded tails locally; Tier 2 is a separate bounded command that reads candidates, closes the DB, calls the pinned model through the OAuth wrapper, then writes one short WAL transaction per card.
- **Reason:** structured anchors improve truth, the LLM improves readability, and isolation prevents the five-minute collector from wedging.
- **Alternative considered:** model calls during ingest or export. Rejected for latency, lock, reliability, and determinism reasons.

### D5: Explicit resolution evidence, not absence

- **Choice:** `chat_open_end` and unanswered decisions resolve only on an explicit resolved marker, a later answering user turn tied to the item, a downstream continuation that explicitly closes it, or a manual resolution event. A later extraction that merely omits the item is not proof.
- **Reason:** bounded tails, parser changes, and model omissions can make real work disappear. Recall is more important than precision in NEEDS YOU.
- **Alternative considered:** resolve when an item disappears from a finalized extraction. Rejected because absence in a tail is not durable resolution evidence.

### D6: Provider allowlist and honest unknowns

- **Choice:** only `claude`, `codex`, `cursor`, `hermes`, and `copilot` may become provider lineage nodes. Unknown strings never enter lineage; real content may appear only as an explicitly ungrouped unknown-provider card.
- **Reason:** the live DB contains many garbage provider shapes; a blocklist will always lag.

### D7: Distinct job-run identity drives history

- **Choice:** append job history only when a job's observable run identity changes, using the best available tuple such as last-run timestamp/evidence mtime plus exit state. Repeated five-minute observations of the same failed run update `last_seen` but do not create extra failures.
- **Reason:** otherwise one failed run sampled repeatedly becomes a fake failure streak.
- **Alternative considered:** append every collector pass. Rejected as semantically wrong.

### D8: Transactional decision events

- **Choice:** use SQLite WAL and immediate short transactions for stable decision IDs, observations, dismissals, resolutions, and alert receipts.
- **Reason:** collector, ticker, dashboard CLI, and restarts can overlap. A mutable JSONL snapshot cannot guarantee idempotence or atomicity.

### D9: Cursor commits on successful local compose plus delivery-state persistence

- **Choice:** write the full local brief and a delivery-status record atomically; advance the selection cursor only when the requested delivery mode completes successfully. A failed send remains retryable without losing rows.
- **Reason:** file existence is not delivery, and a cursor must not swallow failed sends.
- **Clarification:** `--print`/local-only mode records local success separately and does not impersonate a delivered scheduled brief.

### D10: Independent delivery deadman

- **Choice:** a separate minimal entrypoint checks missing/stale/empty/unsent status and uses a direct, redacted Telegram failure path with throttling.
- **Reason:** reusing the full composer or mobile-connect stack would create common-mode failure.

### D11: Recomputed Git facts gate the runner

- **Choice:** the scanner emits facts and `push_eligible` reasons; the runner recomputes at execution time and never acts from dashboard text or cached open ends.
- **Reason:** safety decisions require current structured state.

### D12: Safe runner remains default-dry-run

- **Choice:** implement only the mechanical tier, with a DISABLE file, six-hour activity guard, no checked-out worktree, no dirt, remote/upstream checks, exact logs, and no live activation during initial implementation.
- **Reason:** committed work can still be intentionally held. A reviewed real dry-run is a minimum gate, not proof that every future branch is safe.

## Risks / Trade-offs

[Risk] LLM output can look more certain than its evidence → Mitigation: structured anchors, method/confidence fields, light inferred markers, and a hard NEEDS-YOU confidence floor.

[Risk] Model input can expose private transcript content → Mitigation: fail-closed shared egress policy before model calls and exhaustive field-class tests.

[Risk] Distinct-run detection varies by job evidence quality → Mitigation: registry-level identity fallback, explicit `history_confidence`, and no synthetic streak inflation when identity is unknown.

[Risk] High-recall decisions can become noisy → Mitigation: stable IDs, source/provenance, manual dismiss, explicit resolution evidence, and live-proof tuning; never trade away recall silently.

[Risk] Notification #6 reproduces fragmentation → Mitigation: the five-morning proof must produce a written subsume/keep/fold decision for every existing surface.

[Risk] Scheduled proof depends on secrets and external delivery → Mitigation: all behavior is first proven with stubs and isolated runtime; live receipt is recorded separately and failures do not advance the cursor.

[Trade-off] A default-dry-run robot does not immediately reduce all loose ends → Accepted because proof and trust are more valuable than broad unattended authority.

## Migration Plan

1. Baseline all existing suites and record branch/worktree state.
2. Land OpenSpec/HOTL artifacts and TDD contracts.
3. Complete Phase 0 repairs in owning repos and register the health job.
4. Add distinct-run job history and the deterministic thin brief with stubbed delivery/deadman.
5. Add the shared egress policy and two-lane outcome schema/extractor; run seven-day coverage and cost measurement before enabling enriched output.
6. Add the transactional decision queue and high-recall explicit-resolution behavior.
7. Add outcome enrichment to the already-working brief, install isolated runtime, and verify UI/CLI/rendering.
8. Add structured Git facts and the default-dry-run safe runner; review one real dry-run.
9. Run independent Codex audits against the diff and cold verification until no material novel finding remains.
10. Push the branch and either merge after gates or leave an explicit review-ready handoff.
11. Run five-morning proof; update consolidation decision and ER-107 lifecycle only when evidence exists.

Rollback:

- Unload/remove only the two new launchd labels and restore the prior installed Mission Control bundle.
- Preserve brief/decision/send-status state for diagnosis before any cleanup.
- Revert phase commits in reverse order; schema changes are additive and older code ignores new tables/fields.
- Keep the safe runner disabled/default-dry-run throughout initial rollout.

## Open Questions

- The steady-state LLM call/token cap is set only after the seven-day coverage report provides observed p95 volume and projected cost.
- Existing notification surfaces receive a subsume/keep/fold disposition during live proof, not before user behavior is measured.
- Non-dry-run safe-runner activation is a separate post-review decision; implementation completion does not imply activation.
