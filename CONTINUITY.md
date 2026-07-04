# CONTINUITY

## Principle
Your conversation is temporary; the repo is permanent. Nothing that matters survives unless it is written, signed, and pointed to from a durable repo home.

## What Counts As Written And Findable
- It has a file home in this repository.
- It is signed by role or agent via `by:` or equivalent durable attribution.
- It is pointed to from the local surfaces later chats actually read: `/Users/gillettes/Coding Projects/mission-control/AGENTS.md`, `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md`, `/Users/gillettes/Coding Projects/mission-control/LINEAR.md`, or `/Users/gillettes/Coding Projects/mission-control/todo.md`.

## What Dies If Not Recorded
- rejected alternatives and abandoned approaches
- surprise findings and caveats discovered during implementation or audit
- research detours and failed attempts
- Codex output that was discarded and why
- audit conclusions that did not become a follow-up issue
- anything a later chat would have to rediscover by repeating the work

## Pre-exit Reflex
Before ending a bounded task, ask:
- what did I learn, decide, reject, or confirm that is not yet in the repo?
- what ripples did these changes create that Coherence requires me to check?
- what future work surfaced here that is not yet issue-backed or explicitly dispositioned?

## Work Record Format
```md
### YYYY-MM-DD — short title
- Problem:
- Reasoning:
- Diagnosis inputs:
- Implementation inputs:
- Fix:
- Self-audit:
  - method:
  - outcome:
  - did not verify:
- by:
- triggered by:
- led to:
- linear:
```

## Self-audit Honesty
- Self-audit is method-not-claim: say how a check was performed, not just that it passed.
- Every Self-audit includes an explicit `did not verify X because Y` line when anything remains unverified.
- Claude Code spot-checks at least one attestation claim when an audit surface exists.

## Motive
This is legacy protection, not bureaucracy. Hollow attestations are harder to unwind than an honestly reported gap.

## Applies To
| Role | Minimum Continuity requirement |
|---|---|
| Codex | full six-field Work Record with honest Self-audit |
| Claude Code | audit-variant Work Record or audit log entry with named audit method plus at least one spot-check |
| Cowork | durable planning/state-move notes plus confirmation that required Work Record exists before moving state |

## Where The Rules Live
- `/Users/gillettes/Coding Projects/mission-control/AGENTS.md`
- `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md`
- `/Users/gillettes/Coding Projects/mission-control/LINEAR.md`
- `/Users/gillettes/Coding Projects/mission-control/todo.md` `## Work Record Log`
- any repo-local `PROMPTS.md` or `RULES.md` that references these expectations
