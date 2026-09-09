# Silence is a state — top bar, reset awareness, and a self-repair pass

## Goal

Three operator complaints, one root cause. The menu bar read `MC ·0%` with
nothing saying what it meant, the panel read `Status incomplete` with nothing
saying what was wrong, and a Codex weekly window reset without anyone knowing.

Underneath all three: **a monitoring surface was rendering "no data" and
"nothing wrong" identically.** A provider that stopped reporting, a validator
that refused to display anything, and a reset that nothing watched for all
produced the same output as a healthy system.

- Owner: Claude `470e8496-967a-4b30-8be5-90c30154042d`
- Execution checkout: `/Users/gillettes/Coding Projects/mission-control` on
  `cursor/usage-reset-countdowns`
- Enforcement capture: `global-implementations/ENFORCEMENT_REQUESTS.md`,
  2026-08-19 entry (uncommitted there — that repo had unrelated work in progress)

## Evidence found on the live machine

Read from `~/.mission-control` and `~/.usage-snapshot`, not inferred:

- `MC ·0%` was the lowest quota percent with no label. It meant *Codex weekly,
  0% left, resets in 7h 13m* — every part of which was already in the feed.
- Claude's rows sat `health:"auth"` / `confidence:"stale"` with `age_s` 650360
  (**7.5 days**) and note `no Claude Code OAuth token`. `trustedQuota()` drops
  untrusted rows silently, so a provider going dark produced no signal at all.
- `unregistered` held **57** launchd labels against **17** registered. A
  non-empty list failed the entire automation feed
  (`dashboard/panel.html:500-502`), hiding a live red job
  (`com.gillettes.mobile-connect`). `dashboard status` already printed
  `automation … fresh (red job)` and exited 1 — only the panel threw it away.
- Alert history held **zero** Codex notifications ever and **zero** Claude
  notifications across the 7.5-day outage. `eval_alerts` only fires crossing
  *down* through 50/25/10/5%, so a reset (value jumps up) and a silent provider
  (no value at all) were both unreachable.
- `~/.usage-snapshot/headroom-history.jsonl` (2.9 MB, 1764 entries) had been
  recording every row every 60s and **nothing read it back**.
  `ai-headroom:919-920` already detected the reset shape and used it only to
  clear burn samples.
- `index.html` parsed **43 MB** of JS per open; `chats.js` alone was 42.3 MB.

## What changed

**Menu bar** (`scripts/mc-panel.swift`) — the number is now a labelled bar:
`MC ▮▮▮▯▯ 41%`, band-coloured, tooltip `Claude weekly 41% · resets in 3h 43m`.
A provider that stops reporting outranks any percentage and shows `MC ⚠ Claude`,
because a number from a different provider implies we are not blind when we are.
Needs-you count still wins outright.

Selection was deliberately **not** narrowed to `active` providers: `active`
means "touched in the last 150 seconds", so filtering on it would make the title
flap every time typing stops and would hide a genuinely exhausted Codex.

**Panel** (`dashboard/panel.html`) — opens on two lines, the tightest 5-hour and
weekly window, each a labelled bar with a live countdown, reusing
`hrWindowLine()`/`hrCountdown()` so the summary cannot drift from the detail.
Stat strip, tabs and provider cards moved behind a persisted caret.
`Status incomplete` now names the failing feed and prints the repair command.
Registry drift became a note instead of blanking every job state.

**Reset and silence detection** (`scripts/usage-watch`, new) — reads the history
file that already existed. A reset is a **downward cliff in `used_pct`** (the
file has no `remaining_pct`; getting the direction wrong yields a detector that
can never fire), reusing the 20-point threshold from `ai-headroom:919` rather
than inventing a second constant. Non-`live` rows are skipped so a backoff
replay is not mistaken for a reset, and a high-water mark keeps it from
re-reporting. A credentialed provider with no trusted row for 6h is itself the
finding. Emits through `dashboard attention add`, whose title-derived id upserts.

**Self-repair** (`scripts/self-repair`, new; `launchd/…-repair.plist.template`)
— 04:10 daily, dry-run by default, `DISABLE` sentinel, every action logged with
its undo. Restarts a red launchd job and re-collects a stale feed. Reports and
never touches auth, unloaded jobs, repeated failures, and anything near code or
git. Writes a heartbeat that `automation-status` publishes as
`data.self_check` and the panel renders as `Self-check 2h ago`, so a dead repair
pass is visible — the morning-brief deadman logged `install-unverified
(missing)` for weeks precisely because nothing showed its absence.

**Keepalive exit semantics** (`scripts/automation-status`) — a keepalive job's
`last_exit` describes the incarnation launchd already replaced (`-15` on logout
is routine), so a live, producing keepalive is no longer permanently red. One
with a live pid and **stale** evidence stays red: that is the real silent
failure. This made `mc-panel` green and left `mobile-connect` red.

**Payload** (`scripts/dashboard`) — the `.js` browser transport now omits keys
the page never reads (`grep -c outcome dashboard/index.html` → 0), counted in
`browser_omitted` rather than silently vanishing. `chats` transport 42.3 MB →
27.5 MB (35%). The canonical `.json` is unchanged; sibling collectors still
consume chat outcomes.

**Registry** — registered `ai-headroom`, `mc-panel`, and the repair pass, the
three jobs Mission Control itself depends on, each with an evidence path
confirmed present on this machine. The other 54 stay reported as drift: a job
whose evidence path is guessed manufactures a permanent false yellow.

**Test wiring** — `attention-lane.test.sh` and `queue_admission.test.py` existed
but were never in `scripts/verify.sh`.

## A bug caught before it shipped

The first draft of `self-repair` cleared "stale" feed lockfiles — and on a
healthy machine proposed deleting all seven, aged 37 days. The feed locks are
advisory `flock()` locks on persistent files
(`scripts/dashboard:1126-1135`): the kernel releases the lock when the collector
exits, including on SIGKILL, and the file is *meant* to outlive the run. Its
mtime says nothing. Deleting one while a collector held it would let a second
collector take a second lock — the exact concurrency the lock prevents. The
whole repair was removed and the reasoning left in place so it is not re-added.

## Deliberately not done

- **`loose_ends` / `nodes` / `edges` (27.5 MB remaining).** These *are*
  rendered, and `loose_ends` joins to `nodes` by `source_node`, so a cap needs
  referential integrity plus a visible "showing N of M". Half-doing it would
  silently show less than everything — the defect this change set exists to
  remove. Needs its own pass. Note: all 16,393 loose ends report as open, 11,137
  of them one kind (`register_unverified`); that is a product question, not a
  mechanical cap.
- **Pinned-collector drift.** The running `ai-headroom` is
  `gi-runtime/usage-routing/dd17d6a2cc29/`, **+1497/-1255 lines** behind the
  `global-implementations` source, so fixing that collector's repo does not
  change what runs. A checker would couple this repo to two others; reported
  instead of built.
- **Push alerting.** Operator chose the menu bar as the channel; nothing is
  pushed. The trade-off is explicit: nothing reaches him while away.

## Verification

Recorded in `todo.md` Test Evidence Log for this date.
