# Morning Brief — Strategic Design

**Status:** Accepted
**Date:** 2026-07-09
**Owner:** Trevor Gillette
**Co-authors:** Fable plan author; Opus and Codex adversarial reviewers; Codex implementation governor
**Related:** `/Users/gillettes/.claude/plans/019f4550-2a9a-7fe3-9313-9e7a0be10b35-tha-cuddly-hopcroft.md`; `openspec/changes/morning-brief/`; ER-107

This is the parent design for a multi-phase initiative. Tactical requirements and execution evidence live in `openspec/changes/morning-brief/` and the dated phase plans referenced below.

---

## 1. Problem statement

Trevor cannot quickly reconstruct what his AI fleet accomplished overnight, what remains unfinished, what needs his decision, and whether the supporting jobs are healthy. Mission Control has most of the raw facts, but the facts are split across dashboard feeds, transcripts, nightly review, delegation reports, and several Telegram surfaces.

The evidence is direct: a heavily orchestrated session completed substantial work that did not appear in the nightly message, work crossing midnight fell between calendar-day views, job failures could remain silent, and current chat parsing records relationships but not plain-language outcomes. The result is repeated transcript reopening and unreliable mental state reconstruction.

## 2. Vision / intent

When this ships, Trevor can open one local brief or its short Telegram lead, identify what happened, what needs him, and whether the fleet is healthy in 60 seconds or less, with every action-bearing item grounded in structured evidence or clearly marked high-confidence inference. The system remains useful when LLM extraction is disabled or deferred.

## 3. Non-goals

- Not a new dashboard or replacement for Mission Control.
- Not a rewrite of nightly review, delegation audit, Screenpipe brief, or repo-state watcher; they are inputs until consolidation decisions are proven.
- Not semantic search or a general transcript-memory rebuild.
- Not full lineage support for providers whose graph evidence does not exist.
- Not autonomous merging, force-pushing, deletion, branch cleanup, document editing, or worker delegation.
- Not a remote/cloud service; runtime state remains local and permission-restricted.
- Not a framework or dependency expansion; shell, standard-library Python, SQLite, and the existing static dashboard remain the stack.

## 4. Stakeholders

| Role | Interest | Interface |
|---|---|---|
| Primary user | Fast, trustworthy fleet comprehension | Telegram lead, dashboard Home, `dashboard brief`, local markdown brief |
| Operator | Reliable scheduling, privacy, diagnosis, rollback | launchd jobs, send-status, health/deadman logs, doctor/test commands |
| Reviewers | Spec fit, privacy, safety boundaries, user proof | OpenSpec verify record, test evidence, real dry-run, independent audit |
| Future coding agents | Discoverable continuation and stable contracts | `AGENTS.md`, `todo.md`, `PROJECT_MEMORY.md`, `openspec/specs/` |

## 5. Architecture / module-level changes

```
Existing deterministic feeds ───────┐
chat transcript tails ─> Tier 1 ─┐  │
                         Tier 2 ─┤  ├─> Morning Brief composer
decision evidence ─> decisions DB┘  │       ├─> local markdown + Home
job history / Git facts / usage ────┘       ├─> short Telegram lead
                                             └─> delivery status
                                                       │
                                               independent deadman

Open-ends ledger <─ evidence-gated outcomes/decisions
Safe runner ── recompute Git facts ── dry-run/log only until reviewed
```

New modules: shared field-aware egress policy, session-outcome schema/extractor, transactional decision queue, Morning Brief composer, delivery deadman, conservative loose-end runner, and their tests/plists.

Extended modules: `chat-graph`, `automation-status`, `scan-unfinished-work`, `dashboard`, Home/Automation renderers, job registry, durable records, and installed runtime.

Left untouched except for named repair: nightly-review, delegation-audit, provider authentication, and unrelated Telegram surfaces.

**Key invariant:** Mission Control composes and reflects source evidence; it never converts uncertain transcript interpretation or stale cached state into an unmarked must-act instruction.

## 6. Maturity stages

| Stage | Description | Effort level | Exit criteria for next stage |
|---|---|---|---|
| **L1** | Deterministic thin brief, local file/dashboard, stubbed delivery | Low | All deterministic inputs render with freshness, cursor, redaction, and delivery-state tests |
| **L2** | Scheduled brief with bounded outcome enrichment and decision queue | Medium | Real compose succeeds; extraction coverage/cost measured; low-confidence items excluded from NEEDS YOU |
| **L3** | Five-morning proof with notification consolidation decision | Medium | Comprehension criteria and receipt/action evidence hold; noise tuned |
| **L4** | Reviewed safe runner allowed beyond dry-run | High | A live-ledger dry-run is independently reviewed clean and Trevor explicitly accepts activation |

**Current state:** before L1.
**Target for this initiative:** L3; L4 remains gated even though the dry-run implementation is in scope.

## 7. Phase breakdown

| Phase | Intent | Dated plan filename |
|---|---|---|
| Phase 0 | Repair immediate monitoring gaps and finish source provenance | `docs/plans/2026-07-09-phase-0-morning-brief-foundations-plan.md` |
| Phase 1 | Add job history and ship the deterministic thin brief | `docs/plans/2026-07-09-phase-1-thin-morning-brief-plan.md` |
| Phase 2 | Add private, bounded, evidence-gated session outcomes and coverage/cost measurement | `docs/plans/2026-07-09-phase-2-session-outcomes-plan.md` |
| Phase 3 | Add the high-recall transactional decision queue and alerts | `docs/plans/2026-07-09-phase-3-decision-queue-plan.md` |
| Phase 4 | Enrich the brief, install scheduled delivery, and prove the deadman | `docs/plans/2026-07-09-phase-4-delivery-and-proof-plan.md` |
| Phase 5 | Add recomputed Git facts and the conservative default-dry-run robot | `docs/plans/2026-07-09-phase-5-safe-runner-plan.md` |
| Phase 6 | Run five-morning comprehension proof and decide notification consolidation | `docs/plans/2026-07-09-phase-6-live-proof-plan.md` |

Phases 0 and parts of 1/2/3/5 may be investigated in parallel, but the primary integrator owns shared schemas and files. Thin brief delivery precedes outcome enrichment. Scheduled live proof follows cold tests and independent review.

## 8. Quality attributes

| Attribute | Goal / measurement |
|---|---|
| Performance | Five-minute collection is never blocked by LLM work; export stays deterministic; extraction is bounded and cached |
| Security/privacy | Secrets/PII fail closed at every egress; narrative/action path policy is field-aware; runtime dirs are mode 700; no token logging |
| Observability | Per-input freshness, job streaks, extraction skip/redaction counters, delivery status, deadman alerts, and runner before/after logs |
| Cost | Seven-day coverage report projects daily/monthly model cost; daily cap derives from observed p95 and fails open to structured-only |
| Backwards compatibility | Existing feed envelopes, dashboard tabs, collector cadence, and `chat-graph export` remain valid; new fields are additive |
| Usability | NEEDS YOU fits one phone screen; state is understood in 60 seconds; every line answers so-what or act-now |

## 9. Risks and open questions

**Risk: trusted-looking hallucination.** An LLM can misstate a session. Mitigation: deterministic anchors, visible inference markers, confidence gating, verbatim structured commands/SHAs, and no low-confidence NEEDS YOU items.

**Risk: privacy egress.** Transcript tails can contain secrets or personal data. Mitigation: one boundary policy before every external/model/send path, fail-closed field drops, redacted counters, fixtures covering every field class, and a threat pass before live scheduling.

**Risk: stale confident brief.** Jobs can run while their data silently stops changing. Mitigation: compose-time recency and non-empty assertions for every input, plus inline stale warnings.

**Risk: duplicate or missed decisions.** Multiple writers and parser misses can corrupt decision state. Mitigation: SQLite WAL, immediate transactions, stable IDs, evidence-gated resolution, idempotent events, and concurrency/restart tests.

**Risk: unsafe automation.** A committed branch may still be intentionally held. Mitigation: recompute facts, require remote/upstream/no-worktree/no-dirt/age guards, remain dry-run until reviewed, log exact commands, and provide a DISABLE file.

**Open question:** which existing Telegram surfaces should be subsumed, kept, or folded? Decided during live proof from real action evidence.

**Open question:** what steady-state model cap is appropriate? Derived from Phase 2 coverage and cost evidence, not guessed in advance.

## 10. Verification and governance contracts

### Intent Contract

```
intent: deliver one trustworthy, comprehensible daily fleet-state brief through Mission Control
constraints: preserve local/offline architecture; no uncertain must-act items; no LLM in collector lock path; safe runner stays conservative and default-dry-run
success_criteria: 60-second comprehension, phone-screen NEEDS YOU, delivery proof, five-morning action evidence, review-clean implementation
risk_level: high
```

### Verification Contract

```
verify_steps:
  - run every existing Mission Control suite plus the new outcome, brief, decision-alert, and runner suites
  - run privacy/threat and bash-3.2/static checks
  - install into an isolated runtime and verify a rendered Home/Automation surface
  - generate one real brief with delivery status and test the deadman failure path safely
  - run a real default-dry-run over the live ledger and independently audit it
  - collect five real mornings before calling comprehension verified
```

### Governance Contract

```
approval_gates:
  - Trevor already approved the plan, delivery lane, LLM-on-day-one, and safe-tier implementation
  - do not enable non-dry-run automation without a reviewed live dry-run and explicit activation decision
  - treat external delivery and secret-bearing config as sensitive; test with stubs before authorized live proof
rollback: unload new launchd labels; restore prior installed Mission Control bundle; keep cursor/send state for diagnosis; revert branch commits
ownership: Trevor owns product and activation decisions; the Codex governor owns implementation, evidence, and integration
```

## 11. References

- Approved Fable plan: `/Users/gillettes/.claude/plans/019f4550-2a9a-7fe3-9313-9e7a0be10b35-tha-cuddly-hopcroft.md`
- U1-U7 upgrade audit: `/Users/gillettes/Coding Projects/global-implementations/records/verification/2026-07-09-morning-brief-plan-upgrade-audit.md`
- Codex handoff: `/Users/gillettes/Coding Projects/global-implementations/records/implementation-packets/2026-07-09-morning-brief-codex-handoff.md`
- Mission Control roadmap: `docs/IMPROVEMENTS.md` P9, P10, P12, P13, P14
- OpenSpec change: `openspec/changes/morning-brief/`
