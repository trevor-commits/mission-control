# Rollup-answer retrospective

## What changed after first green

The first full verifier was necessary but insufficient. Independent review found that the database transaction and the derived private publication had separate identities: the manifest digest was checked before commit but not persisted, later validation reopened mutable names, and dynamic timestamps prevented exact reproduction. The same review found a second false-success path where a non-writing snapshot command suppressed the real feed collector.

## Durable lessons

1. A recoverable derived artifact needs an immutable identity stored in the authoritative transaction, not only a preflight check.
2. File-descriptor pinning protects a directory only when every later success assertion proves the current name and bytes still match that exact descriptor.
3. Post-commit invalid material should be preserved under a private quarantine name; deletion destroys forensic and replay evidence.
4. A public state-changing CLI must bind success to the consumer surface it promises. A helper returning zero is not proof that the feed file changed.
5. Hermetic no-send tests should install an executable trap sender and assert it remains untouched, not rely only on a configuration flag.

## Remaining boundary

One new same-model/max frozen-head audit and hosted PR checks remain. Merge, installation, live-store use, provider delivery, plist, and launchd actions are outside this branch-only change.
