# Independent Codex audit: Morning Brief Tier 2 outcome enrichment

Date: 2026-07-09
Implementation chat: Codex `019f4963-1e75-7600-8a17-1e6f6f8e8ca6`
Reviewer: separate Codex agent `/root/outcome_audit`, with challenger `/root/outcome_audit/tier2_challenger`
Final state: review-clean; every accepted finding below is implemented with a focused regression, and no current P0–P3 finding remains

## Audited Chat

- Audited chat name: Mission Control orchestration priorities
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/global-implementations`
- Provider: Claude/Fable
- Full ID: `35d96de4-9509-4382-b1a0-10b9a4d1777e`
- Transcript: `/Users/gillettes/.claude/projects/-Users-gillettes-Coding-Projects-global-implementations/35d96de4-9509-4382-b1a0-10b9a4d1777e.jsonl`
- Linked plan-author session: `6f306a0b-abbb-4d39-9d64-afa7fb977250`
- Plan: `/Users/gillettes/.claude/plans/019f4550-2a9a-7fe3-9313-9e7a0be10b35-tha-cuddly-hopcroft.md`

## Audit conclusion about Fable's direction

Fable's revised priority was correct: Morning Brief is the product layer that composes session lookup, transcript recall, response clarity, repo state, decisions, and memory into one daily attention surface. Session lookup remains foundational infrastructure rather than the competing primary product.

The free-form Tier 2 rewrite design was not safe enough to accept verbatim. Counterexamples repeatedly showed that a denylist could miss model-invented commands, identifiers, repositories, or authoritative-looking prose. The implemented correction keeps the model useful only as a bounded classifier: it selects closed outcome codes, while deterministic code supplies fixed prose, exact session title, repo, audit/spawn/continuation relationship, commit anchors, and queue trust. This preserves Fable's comprehension goal without letting model-authored facts become actions or source truth.

## Findings and dispositions

### P1 — Free model prose could invent commands and false anchors

Accepted. The response schema is now a fixed taxonomy; exact local validation rejects extra/missing/wrong-type/non-finite/unknown results; the cache stores only canonical codes; deterministic Tier 1 remains current on any failure. Commands, IDs, SHAs, repo names, paths, and counts can only come from deterministic fields.

### P1 — Generic taxonomy lines lost the session-specific meaning Tier 2 existed to recover

Accepted. Outcome export now adds deterministic session-title and repo fields. The brief renders that context, fixed residuals, and allowlisted high-confidence graph lineage. An audit line explicitly names the chat it audited and is grouped beneath the audited outcome when both are present.

### P1 — Sample/test modes could bypass persistent off or call the real wrapper

Accepted. Persistent off dominates production, sample, and test modes. Synthetic test mode requires an explicit executable stub and cannot fall back to the installed Claude wrapper. Only a truly absent config may bootstrap sampling; any present malformed, unreadable, future-schema, incomplete, or unsafe config is uncalibrated and makes zero calls.

### P1 — Extractor and exporter disagreed on calibrated-config validity

Accepted. Both paths now require an exact provider set with boolean values, a literal boolean enable, and non-boolean integer caps within 1–100 calls and 1–10,000,000 tokens. Invalid config immediately restores deterministic Tier 1 in export as well as extraction.

### P1 — Model-only decisions entered the red NEEDS YOU block and could outlive rollback

Accepted. Inferred codes enter the queue with deterministic session/repo context, no action, and no alert eligibility. They render only in `Possible follow-ups — Inferred`. A current same-session Tier 1 rollback or newer Tier 2 omission records reversible `tier2_supersession`; a missing feed causes no state move; provider rollback is session-local; re-enabling an unchanged cached code reopens only this reversible state, never a manual dismissal or structured resolution.

The final counterexample pass additionally proved that title/repo enrichment changes display text without changing semantic model evidence. A human dismissal or manual resolution remains sticky through context changes and intervening Tier 2 omission.

### P2 — Empty explicit ambiguity never reached the Sonnet escalation

Accepted. The first pinned model may return `ambiguity=true` with no `did` code; exactly one budgeted pinned Sonnet call may then resolve it. Nothing persists unless the stronger result returns a valid code with ambiguity cleared.

### P2 — Backlog, lock, timeout, and Automation failure semantics were incomplete

Accepted across the audit iterations. Current Tier 1 is persisted before any model work; attempt-aware ordering avoids starvation; live locks are never stolen while ownerless/corrupt stale locks recover; wrapper defer precedes extractor timeout; bounded output prevents oversized persistence; semantic non-completion produces yellow Automation state and failure history; activation-gated jobs remain uninstalled by default.

## Verification

- `bash scripts/outcome-extractor.test.sh` — all pass, synthetic/local stub only.
- `bash scripts/chat-graph.test.sh` — all pass.
- `bash scripts/decision-alert.test.sh` — all pass.
- `bash scripts/morning-brief.test.sh` — all pass.
- `bash scripts/automation-status.test.sh` — all pass.
- `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell` — `PASS=30 FAIL=0` before the final cold rerun.
- `DO_NOT_TRACK=1 openspec validate morning-brief --strict` — valid.
- HOTL document lint — pass.
- Final reviewer verdict — `review-clean`; no current P0–P3 finding remained after the exact current-tree replay.
- Landing/integration — implementation `df991b4` and audit records `ef281a5` are pushed on `origin/main`; the code-only installer preserved the complete LaunchAgent hash inventory and the installed disabled extractor path made zero model calls.

No real provider sample, transcript egress, Telegram send, LaunchAgent install/bootstrap, or scheduled activation occurred during this audit.

## Residual authorization and elapsed-proof gates

- Run one explicitly authorized, bounded, privacy-screened provider sample and apply observed caps.
- Run one authorized Telegram receipt and safe deadman proof.
- Explicitly decide whether to activate Outcome Extractor, Morning Brief, and deadman schedules.
- Observe approximately five natural mornings, tune ranking/noise, decide which older notification surfaces to subsume, then perform the final verification/archive audit.
