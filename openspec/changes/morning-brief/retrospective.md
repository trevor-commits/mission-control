# Morning Brief implementation retrospective

Date: 2026-07-09
State: implementation closeout; final live-proof retrospective remains pending

## What changed the plan

Fable correctly recognized that Mission Control should be the leverage point, but its initial ordering treated the already-shipped improvement loop as unfinished. Live evidence changed the priority: build Morning Brief as the composed product surface, while session lookup, response clarity, and durable memory serve as its substrate.

The implementation therefore shipped a deterministic, zero-call spine first. That choice made the product useful without waiting for model extraction, exposed source-quality failures early, and kept transcript egress behind an explicit gate.

## What worked

- Repairing source reliability before summarization prevented stale LaunchAgent and correction-loop state from being amplified.
- Granular commits and independent audits converted concurrency, privacy, parser, decision, and Git-safety counterexamples into regression tests.
- Installing code without installing LaunchAgents allowed realistic browser proof without authorizing delivery or schedules.
- The real fleet dry-run demonstrated the runner's conservative boundary on actual messy repositories, not only fixtures.
- Browser verification materially improved response clarity by catching fragmented operator procedures and misleading activation status that source tests alone had not exposed.
- Reinstalling from canonical `main` after a real rollback proved the shipped runtime path and prevented worktree-only success from being mistaken for final installation.

## What needed correction

- Early outcome parsing split a single operator procedure into multiple decisions and admitted fenced shell text into narrative.
- Parser upgrades initially lacked a sufficiently strong same-source-content identity for safe deterministic supersession.
- Decision trust needed a closed structured-origin registry and graph-backed resolution rather than caller assertions.
- Git facts needed to fail closed on empty, malformed, and wrong-path worktree output, and human output needed the same privacy discipline as JSON logs.
- An uninstalled scheduled job is not a failed job; the dashboard now distinguishes awaiting activation from runtime failure.
- Prefix-only credential documentation still carries sensitive identity. The final UI review caught both partial token redaction and a stale next-run precedence bug; adversarial render fixtures now retain the dangerous suffix/timestamp so regressions cannot normalize the cases away.
- The first immutable final-gate audit found that independently reasonable freshness checks had drifted at ordinary age boundaries, unchanged plist bytes concealed mode drift, and nested tests silently switched from macOS Bash 3.2 to Homebrew Bash. A cross-runtime boundary table, same-interpreter test harness, isolated-HOME fixtures, and unchanged/retry permission regressions now make those guarantees structural.
- The second code audit proved that a correct guard is insufficient if named Home surfaces still derive color only from payload contents, and that a smoke test can hide a malformed committed fixture by normalizing it first. The shared guard tone now feeds every visible summary surface, the boundary table asserts those surfaces, and the demo test consumes the exact production cadence.
- An ad hoc launchd counterexample reached real launchctl when its intended stub was absent, temporarily disrupting the live collector registration before immediate repair. Future state-moving counterexamples must prove the stub exists and fail closed before any real launchctl command is reachable; a temporary HOME alone is not isolation from a per-user launchd domain.

## Durable lessons

- Product priority should follow the surface that composes and tests the underlying capabilities, not whichever substrate is most technically interesting in isolation.
- A transcript-derived decision needs stable source identity, sanitized-content identity, explicit trust, and exact closure evidence.
- Installed UI proof is part of correctness when the goal is operator comprehension.
- “Implemented” and “verified” must remain separate when authorization, external delivery, or elapsed natural use is still outstanding.

## Next retrospective trigger

Authorized delivery and the isolated deadman failure proof completed on 2026-07-10. Extend this record after the 2026-07-11 final gate lands, the bounded Tier 2 calibration/Outcome Extractor disposition is explicit, and approximately five natural mornings have elapsed. At that point record noise/comprehension results and the final notification consolidation decisions before archiving the OpenSpec change.
