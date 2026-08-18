# Usage reset countdowns — uniform clocks on every window

## Goal

Every usage window says when it resets and counts down to that time. Full
windows still show the clock. Empty windows waiting to refill show it in red.
Prepaid balances and unused 5-hour clocks that have not started yet keep the
same line instead of going blank.

- Owner: Cursor `46ba944f-41f8-41c8-8d6b-c0b76bce90bb`
- Execution checkout: `/Users/gillettes/Coding Projects/mission-control` on
  `cursor/usage-reset-countdowns`
- Companion collector change: global-implementations worktree
  `/Users/gillettes/Coding Projects/global-implementations-worktrees/usage-reset-countdowns`

## What changed

- Usage tab and compact panel always render a 12px tabular countdown under each
  window. Copy is one family: `resets in 1h 04m 03s`, `renews in …` for month
  cycles, `empty — resets in …` when remaining is 0, `full — 5-hour clock
  starts on next use` when GLM's 5-hour window is unused, `prepaid — no
  scheduled reset` for API balances.
- Empty and overdue clocks turn red. The panel ticks every second to match the
  Usage tab.
- Signed-out Claude weekly still shows the known Wednesday 5pm PT reset instead
  of hiding the line because remaining percent is null.
- Fixture coverage: empty GLM weekly with a future epoch, unused 5-hour with no
  epoch, signed-out Claude weekly with an epoch.

## Research consult

- `researched-repos/steipete-CodexBar.md` — reset countdown on quota rows.
- `researched-repos/tabler-tabler.md` — one card per provider, labeled window
  lines, scanable meta. Applied the existing Mission Control usage-card pattern,
  not a new visual kit.

## Verification

Recorded in `todo.md` Test Evidence Log for this date.

## Did not verify

- Live Anthropic 5-hour clock. Claude Code's Keychain token is empty, so that
  window keeps the honest "clock unknown until Claude Code reports it" line.
- Inventing a GLM 5-hour reset while unused. z.ai omits `nextResetTime` until
  the window starts.
- Menu-bar title countdown. The bar stays a lowest remaining percent. The
  compact panel and Usage tab carry the clocks.

linear: self-contained. Repo-only.
