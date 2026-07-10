# Morning Brief Implementation Plan

> **For agentic workers:** Execute the root `hotl-workflow-morning-brief.md` task by task. The root HOTL workflow is the authoritative micro-plan; this artifact binds it to OpenSpec without duplicating and drifting the step list.

**Goal:** Deliver one trustworthy deterministic-first Morning Brief in Mission Control, then enrich it with privacy-safe session outcomes, high-recall decisions, delivery proof, and a conservative default-dry-run loose-end tier.

**Architecture:** Existing deterministic feeds compose first into atomic Markdown and a structured sidecar. Transcript outcomes run through a shared field-aware boundary and isolated two-lane extraction; decisions use SQLite WAL and explicit resolution evidence. Scheduled delivery is independently checked by a deadman, and state-moving automation recomputes structured Git facts immediately before any proposed action.

**Tech Stack:** macOS bash 3.2, Python 3 standard library, SQLite WAL, vanilla JavaScript/static file dashboard, launchd, existing mobile-connect/Claude OAuth wrappers, OpenSpec, HOTL, and current Mission Control test harnesses.

---

## Authoritative micro-plan

- File: `hotl-workflow-morning-brief.md`
- Risk: high
- Branch/worktree: `codex/morning-brief` at `/Users/gillettes/Coding Projects/mission-control-worktrees/morning-brief`
- Governance: Trevor already approved the product plan and delivery lane; high-risk gates remain before first live cross-provider transcript egress, first live Telegram proof, and any future transition of the loose-end runner away from dry-run.
- TDD: every behavior slice begins with failure evidence, then the minimum implementation, then the affected suite and cold regression set.

## Phase mapping

- HOTL steps 1-8: governance and Phase 0 systemic repairs.
- HOTL steps 9-18: shared privacy, migration, open-work changes, and distinct-run automation history.
- HOTL steps 19-30: deterministic thin brief, sidecar, dashboard, delivery receipts, deadman, and installed proof.
- HOTL steps 31-40: Tier 1/Tier 2 outcomes, no-call calibration, decision queue, and outcome enrichment.
- HOTL steps 41-47: structured Git facts, default-dry-run safe runner, and reviewed live-ledger dry-run.
- HOTL steps 48-55: full verification, independent Codex audit loop, multi-repo landing, and implemented-state closeout.
- HOTL step 56: elapsed five-morning proof and final archive; intentionally remains pending until real time supplies the evidence.

## Commit checkpoints

Commit after each coherent green slice: governance/specs; Phase 0 repair per owning repo; privacy/substrate; automation history; thin brief; delivery/deadman; outcomes; decisions/enrichment; Git facts/runner; audit fixes; and final durable records. Never chain a test command directly to a commit.
