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

## Remaining boundary

One new exact-head audit by a fresh same-model/max task and hosted PR checks remain. Merge, installation, live-store use, provider delivery, plist, and launchd actions are outside this branch-only change.
