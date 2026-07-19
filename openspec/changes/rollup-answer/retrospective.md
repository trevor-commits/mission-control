# Rollup-answer retrospective

## What changed after first green

The first full verifier was necessary but insufficient. Independent review found that the database transaction and the derived private publication had separate identities: the manifest digest was checked before commit but not persisted, later validation reopened mutable names, and dynamic timestamps prevented exact reproduction. The same review found a second false-success path where a non-writing snapshot command suppressed the real feed collector.

## Durable lessons

1. A recoverable derived artifact needs an immutable identity stored in the authoritative transaction, not only a preflight check.
2. File-descriptor pinning protects a directory only when every later success assertion proves the current name and bytes still match that exact descriptor.
3. Post-commit invalid material should be preserved under a private quarantine name; deletion destroys forensic and replay evidence.
4. A public state-changing CLI must bind success to the consumer surface it promises. A helper returning zero is not proof that the feed file changed.
5. Hermetic no-send tests should install an executable trap sender and assert it remains untouched, not rely only on a configuration flag.
6. Artifact identity cannot be inferred from whether the current invocation staged or published it. Receipt-backed failure cleanup must use the exact name still bound to the held descriptor, including replay of an existing final batch.
7. A public transaction cannot select independently versioned writer and reader implementations. Runtime identity is part of feed-coherence proof.
8. A bounded view must order by domain actionability before slicing; counting actionables across the full list is not enough if the visible prefix contains only receipts.
9. A path-visible parent replacement creates two identities to reconcile: preserve the exact held old-parent object, then independently fd-bind and invalidate any unverified canonical conflict in the current parent before returning.
10. A consumer test run after the public command is not proof of transaction coherence. Persist the consumer view first, invoke only the public command, and require those exact bytes/feed artifacts to advance before zero.
11. Local-view reconciliation and notification delivery are different lifecycles. A delivered brief may update its local action view only while preserving receipt/cursor identity and suppressing resend; in-flight receipt-bound bytes must fail closed instead of being rewritten.
12. Same-runtime claims must cover every ambient selector, including `REPO_ROOT` and explicit feeder overrides, as well as installed-path selection. A state-changing transaction should bind composer and readers to one script directory while ordinary collection may retain overrides.
13. Calendar rollover is presentation state, not delivery authority. Validate the receipt lifecycle first: an incomplete retry stays pinned after midnight, and a sidecar-only delivered claim cannot authorize changing notification-derived local bytes.

## Remaining boundary

The committed replacement authoritative gate is green at `0ce6d3d`. One new exact-head audit by a fresh same-model/max task and hosted PR checks remain. Merge, installation, live-store use, provider delivery, plist, and launchd actions are outside this branch-only change.
