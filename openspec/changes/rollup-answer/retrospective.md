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
14. Receipt shape is not receipt identity. A complete counter and 64-hex-looking chunk list can still be invented; bind it to the full source Markdown, the exact chunking parameter, every ordered chunk digest, and then pin the immutable receipt bytes across later local rewrites.
15. Canonical conflicts are entries, not only directories. Receipt-backed quarantine eligibility must follow an exact held regular-file, directory, or symlink inode without following symlink targets; first-answer orphan conflicts remain untouched.
16. Prevalidation plus a path rename is not an identity-conditional move. When the platform cannot rename by descriptor, post-rename verification needs a tested descriptor-bound rollback that restores any raced replacement before failure is returned.
17. Identity-bearing receipt fields are mandatory authority, not backward-compatible hints. Missing Markdown or chunk-limit identity must fail closed rather than borrow current defaults.
18. A global Home headline must use combined Home attention. A reassuring decision-subdomain label cannot mask actionable failures in chats, repositories, usage, automation, or brief health.
19. SQLite `mode=ro` is not a no-filesystem-write guarantee: a WAL-mode database can create `-shm` on the first reader. Prewrite validation must use an immutable view only when no WAL exists, require an existing safe shared-memory entry for WAL reads, and bind the result to unchanged database/WAL identities.

## Remaining boundary

Fresh terminal audit of the current-main candidate caught one last false green: ordinary SQLite read-only planning created a new `decisions.db-shm` entry after a valid fixture existed. Repair `9e07ee528fafe5f7672f8df3843b37102e67490a` adds stable DB/WAL binding plus a regression that compares the whole temporary state before and after valid planning. Rollup 30/30 and the authoritative `SUITES PASS=26 FAIL=0` gate are green; PR #11 is open, approved, non-draft, and mergeable. PR merge, installation, live-store use, provider delivery, plist, and launchd actions remain outside this branch-only change.
