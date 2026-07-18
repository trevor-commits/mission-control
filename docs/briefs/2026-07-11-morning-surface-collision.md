# Morning Surface Collision Brief - 2026-07-11

Status: analysis only. No plist, launchd, Telegram, Screenpipe, or Outcome
Extractor state changed for this brief.

## Live Morning Surfaces

| Surface | Local schedule | Channel | Current role | Collision risk |
|---|---:|---|---|---|
| Mission Control dashboard refresh | 05:00 | local file dashboard / LaunchAgent | Refreshes Mission Control feeds before morning review. | Low. It is substrate, not a second narrative brief. |
| Morning Brief deadman | 05:20 | Telegram only if the 05:00 brief did not prove delivery | Safety net for missed Morning Brief delivery. | Low if it remains conditional and direct-transport only. |
| `morning-health-brief` | 07:00 | legacy morning status surface | Currently broken / not trusted as the live primary brief. | High if revived unchanged because it overlaps with Mission Control and Screenpipe summaries. |
| Screenpipe brief | 08:00 | Screenpipe-owned local brief surface | Later context/memory recap from Screenpipe capture. | Medium. Useful as a capture lens, but easy to confuse with the 05:00 Mission Control operator brief. |

## Options

### Option A - Keep Separate

Keep Mission Control at 05:00, deadman at 05:20, and Screenpipe at 08:00. Do
not revive `morning-health-brief` until it has a distinct job.

### Option B - Fold `morning-health-brief` Into Mission Control

Retire or leave broken `morning-health-brief` as non-live, then move any still
valuable checks into Mission Control's `automation`, `brief`, or dashboard
status feeds.

### Option C - Subsume Screenpipe Morning Copy

Keep Screenpipe running, but make its 08:00 brief a source input or later
context appendix rather than a parallel morning call to action.

## Conservative Recommendation

Use Option A now: Mission Control 05:00 remains the primary morning operator
brief; deadman stays conditional; `morning-health-brief` remains non-live until
it has a non-overlapping purpose; Screenpipe remains loaded and separate at
08:00. Revisit after the five-morning proof log shows whether Trevor actually
reads and understands the 05:00 brief.

## Decision (2026-07-11)

Trevor chose folds:
1. Retire `morning-health-brief` as a separate morning ping; keep any still-useful checks visible via Mission Control automation/brief feeds.
2. Retire `com.screenpipe.morning-brief` as a separate 08:00 narrative; Screenpipe **capture** (pilot/watchdog) stays on.
3. Outcome Extractor: **on** (activate after calibration).

Live actions same night: LaunchAgents for (1) and (2) unloaded and renamed `*.folded-*`.
