# Morning Brief brainstorm — approved decision capture

This is the raw design decision capture for the already-approved Morning Brief initiative. Trevor approved the Fable plan on 2026-07-09; the current Codex task is implementation plus adversarial audit, so this artifact records the settled choices rather than reopening them.

## Background

Trevor's coding work is distributed across many Claude, Codex, Cursor, Hermes, and Copilot tasks. Mission Control can already find tasks, relationships, open ends, Git state, job health, and usage, but it does not explain what the fleet accomplished or present one trustworthy morning decision surface. The practical failure is comprehension: valuable overnight work exists, yet Trevor must reopen transcripts and reconcile several Telegram messages to understand it.

## Decision chain

### Q1 — New product or extend Mission Control?

Options considered:

1. Build a standalone daily-digest tool.
2. Extend nightly review.
3. Extend Mission Control and compose existing feeds.

Decision: extend Mission Control. It already owns the local data spine and dashboard. A new tool would add another source of truth and another notification surface.

### Q2 — What ships first?

Options considered:

1. Wait for LLM outcome extraction before delivering anything.
2. Ship a thin brief from existing deterministic inputs, then enrich it.
3. Ship only the outcome extractor and leave presentation for later.

Decision: ship the thin brief first. Existing Git, open-end, automation, usage, nightly-review, and delegation inputs are enough to relieve part of the problem and independently prove compose, redaction, delivery, cursor, and deadman behavior. Outcome cards remain an enrichment, never a load-bearing dependency.

### Q3 — How is transcript content extracted?

Options considered:

1. Structured parsing only.
2. LLM summarization only.
3. Two lanes: deterministic anchors plus bounded LLM rewriting for high-value sessions.

Decision: two lanes. Tier 1 parses bounded tails for reply-v5, Codex closeout, audit-report, packet/handoff, provenance, status, and commit shapes. Tier 2 runs separately from ingest, closes the database before any model call, uses the OAuth-lock wrapper, is cached and budget-capped, and fails open to Tier 1.

### Q4 — What may leave the machine?

Decision: a single field-aware egress policy applies before LLM calls, storage, decision writes, error capture, and Telegram chunks. Secrets, denylisted terms, emails, and phones fail closed everywhere. Transcript-derived narrative removes local filesystem paths except known repo/tool roots; exact action commands may keep necessary local paths. Low-confidence inference never enters NEEDS YOU.

### Q5 — How are unfinished work and decisions resolved?

Decision: evidence-gated state. `chat_open_end` and unanswered decisions remain open through parser misses, budget skips, privacy skips, non-finalized tails, and restarts. They clear only when a finalized extraction or answering/downstream evidence proves resolution. Stable IDs and transactional storage make repeat collection idempotent.

### Q6 — What is the notification model?

Decision: one short NEEDS-YOU-first 5:00 AM Telegram push plus the full local brief and dashboard view. The brief asserts every input's freshness. A separate 5:20 delivery deadman checks send-status, not file existence. Existing notification surfaces coexist during proof, but live-proof must end with an explicit subsume/keep/fold decision for each one. The original 7:00/7:20 design was superseded by the operator-ordered 5:00/5:20 schedule in commit `1eeb45d`.

### Q7 — How much autonomy ships?

Decision: only the conservative safe tier. The runner recomputes Git facts at action time, defaults to dry-run, has a DISABLE file, never merges, never force-pushes, never deletes, never edits human docs, never acts on recent work, and logs before/after evidence. The delegate tier stays out.

## Product success

- NEEDS YOU is the only must-read block and fits on one phone screen.
- A cold reader can state what happened, what needs action, and whether the machinery is healthy in at most 60 seconds without opening a transcript.
- Every visible line answers either "so what?" or "do I act?" and carries enough provenance to calibrate trust.
- Five real mornings measure whether Trevor read and acted, not merely whether extraction coverage was high.

## Binding constraints

- Local/offline Mission Control remains the source and UI; no framework/server rewrite.
- Claude and Codex receive lineage grouping; other providers render honestly as flat/ungrouped until their lineage is real.
- Provider lineage uses an allowlist; unknown providers never become graph nodes.
- Cursor advances only after compose, local write, and delivery-status persistence succeed.
- No LLM call occurs while a chat-graph write transaction or collector lock is held.
- Bash remains macOS 3.2 compatible; Python remains standard-library only.
- Existing nightly-review and delegation-audit implementations remain upstream inputs, not rewrite targets.

## Approval and review evidence

- Trevor approved the source plan and explicitly chose LLM fallback on day one, Telegram delivery, the safe auto-fix tier, and coexistence during live proof.
- The plan was audited by Opus, Codex 5.5 xhigh, a focused Codex re-audit, and a product-fit Opus audit. The current task adds an implementation-time Codex audit loop.
