# Rollup-answer proposal

## Why

Mission Control can group duplicate-looking open decisions, but it cannot safely apply one operator answer to strictly equivalent members. Reusing the existing `resolve()` path would close work before its owning task consumed the answer. Leaving rows merely open would permit duplicate alerts and contradictory answers. The approved contract needs a durable, recoverable intermediate interpretation.

## What changes

- Add read-only rollup-answer planning and transactional `answered_pending` event recording to `scripts/decision-alert`.
- Add a private, fd-pinned, atomic batch publisher to `scripts/compose-decision-prompt.py`.
- Add `dashboard decide answer-rollup` with the existing source/resume metadata flags.
- Suppress current pending members from ordinary alerts, dismissals, and single answers while preserving open-state visibility.
- Render pending rows as awaiting owner consumption in Home and the menu-bar panel, and omit them from the Morning Brief `NEEDS YOU` block.
- Add hermetic regressions for equivalence, atomicity, replay/conflict, recovery, exact consumption, changed evidence, filesystem races, and renderer truth.

## Impact

- Code: decision queue, answer composer, dashboard CLI, Morning Brief, Home renderer, panel renderer, and focused tests.
- State: immutable `answered_pending` events plus private `$MISSION_CONTROL_HOME/answer-batches/<batch-key>/` directories. No schema migration.
- Runtime: none in this branch. No install, launchd, notification, provider, or live-store action.
- Compatibility: existing non-pending single answers keep their current terminal manual-resolution behavior.
