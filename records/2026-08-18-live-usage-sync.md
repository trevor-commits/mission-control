# Live usage sync — menu bar, Usage tab, and routing

## Goal

Stop forcing Trevor to open Chrome for current AI remaining percent. The
60-second collector already had live Codex, Cursor, and GLM numbers. The
glance surfaces treated a signed-out Claude row as the lowest remaining
quota, then hid every live percent.

- Owner: Cursor `b60f025b-cb97-4a82-8f55-866893c361c6`
- Execution checkout: `/Users/gillettes/Coding Projects/mission-control` on
  `cursor/usage-sync-live-headroom`
- Companion collector/router change: global-implementations
  `cursor/usage-sync-live-headroom`

## What changed

- Native menu bar and compact panel pick the lowest **ok + live + fresh**
  quota row. A stale Claude summary can no longer blank the `MC ·N%` readout.
- Usage tab cards say `signed out` for `health=auth` instead of painting a
  last-known 0% / 100% bar, and signed-out groups sort after live low-headroom
  providers.
- Vendored `usage-snapshot --html` banner points at
  `~/.mission-control/index.html#usage`.
- Hermes ops tick and backup-verify registry rows land with this change.

## Verification

Recorded in `todo.md` Test Evidence Log for this date.
Authoritative matrix: `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh` returned
`SUITES PASS=26 FAIL=0`.

## Did not verify

- Live Anthropic percent. Claude Code's Keychain OAuth token is empty on this
  Mac, so Claude stays a labeled local estimate until Trevor opens Claude Code.
- Turning the always-on-top corner card back on. That stays operator choice.
- Telegram Mobile Connect red. Unrelated to token tracking.

linear: self-contained. Repo-only.
