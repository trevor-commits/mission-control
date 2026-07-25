# Evidence: Mission Control attention lane (2026-07-23)

Branch: `cursor/attention-lane`  
Worktree: `/Users/gillettes/Coding Projects/mission-control-attention`  
Baseline: `origin/main` @ `8582e18`  
Executor: Cursor Agent (Composer included tier)  
Session: `1d286402-3c53-4511-aca4-eb08fdcecf7a`

## Why

Menu-bar panel showed top-3 of a noisy 135-item `decisions.pinned` list. Contract: panel top ~5 needs-attention; full dashboard ranked board; git feed was blanking with `feeder timed out after 120s`.

## What landed

1. `dashboard attention add|resolve|list` — append-only `$MISSION_CONTROL_HOME/attention/queue.jsonl`, id `att:` + sha1(title)[:12], dedupe refresh.
2. `attention` feed (cadence 300s) — merges manual + quality-filtered decisions (≤7d, question ≥15, not fallback) + red automation; `board` top 25, `top5`, `counts`.
3. Stale-decision demotion in decisions collect path — pinned unanswered >14d → `data.archived` / `archived_count` (no extractor rewrite).
4. `dashboard/panel.html` — loads `attention.js`, renders top 5, decision `mcDecide` only for `decision:[0-9a-f]{24}`, else copy `dashboard attention resolve`; falls back to decisions if attention absent/stale.
5. `dashboard/index.html` — Attention tab + home glance prefers attention top5.
6. Git feeder — `scan-unfinished-work --json --with-timeouts` with per-repo `SCAN_REPO_TIMEOUT_S` (default 45) and whole-scan `SCAN_TOTAL_DEADLINE_S` (default 280); dashboard whole-feed timeout raised 120→300. Slow units become per-repo error entries inside an `ok:true` feed.

## Git slow unit (root cause)

Whole-feed timeout was **cumulative**, not a single hung process:

- Reproduced: `MISSION_CONTROL_HOME=<tmp> scripts/dashboard collect --force git` → `git.error.json` with `"error": "feeder timed out after 120s"` after ~123s wall clock.
- Profiled ~59 Coding Projects repos; slowest single unit observed: **`3rd Party Git Hub Repo's`** (~7.65s). Sum of per-repo times exceeds 120s (Autonomous Coding Agent ~6.2s, Best Coding Workflows ~5.8s, Everyday Work ~5.3s, …).
- Fix: per-repo sub-timeouts + partial merge + 300s whole-feed budget.

## Commands / outputs (acceptance)

### Attention unit suite

```text
PASS: attention add/resolve/list + title dedupe
PASS: attention merge/rank/filter + stale-decision demotion
PASS: panel top-5 rendering contract
PASS: git feeder partial-result with simulated slow unit (slow-repo)
PASS: e2e attention add → collect → ranked attention.json
attention-lane: PASS=5 FAIL=0
```

### Existing suites (this worktree)

| Suite | Result |
|-------|--------|
| `scripts/attention-lane.test.sh` | PASS=5 FAIL=0 |
| `scripts/dashboard.test.sh` | PASS=67 FAIL=0 |
| `scripts/er134-usability.test.sh` | 60 passed, 0 failed |
| `node scripts/dashboard-browser.test.js` | 253 assertions passed |
| `node scripts/dashboard-render-smoke.js` | all 8 tabs render over fixtures |

Other `scripts/*.test.sh` / `*.test.py` (excluding dashboard/attention/er134 already above): **ALL_OTHER_FAIL=0**
(automation-status, chat-graph, decision-alert, loose-end-runner, mission-control-common, morning-brief*, outcome-*, usage-snapshot, queue_admission, morning-brief-deadman-sender).

### E2E attention collect (temp home)

```bash
MISSION_CONTROL_HOME=<tmp> scripts/dashboard attention add --title "…"
MISSION_CONTROL_HOME=<tmp> scripts/dashboard collect --force attention
# → data/attention.json ok:true, added id present in top5
```

Verified by `t_e2e_attention_collect` in `attention-lane.test.sh`.

### Git collect after fix

```bash
MISSION_CONTROL_HOME=<tmp> scripts/dashboard collect --force git
```

Before (baseline): `git.error.json` → `"error": "feeder timed out after 120s"` (~123s).

After (this branch):

```text
EXIT:0
ok True error None
repos 60 partial False timed_out [] skipped []
# wall ~285s (under 300s whole-feed budget; previously died at 120s)
```

## Claims list

| Claim | Verified? |
|-------|-----------|
| `attention add` prints stable `att:` id and dedupes by title | YES — unit test |
| `attention resolve` + `list` clear open items | YES — unit test |
| Attention feed ranks severity↑, due↑, newest | YES — unit test |
| Junk decision fallback + >7d decisions filtered; red automation included | YES — unit test |
| Decisions >14d demoted to `archived` on collect | YES — unit test |
| Panel source loads attention and caps at 5 with fallback | YES — source contract + er134 |
| Git per-unit timeout yields partial `ok` feed (simulated `slow-repo`) | YES — unit test |
| Real `collect --force git` no longer dies at 120s whole-feed | YES — ok:true, 60 repos, ~285s wall |
| Did not run `dashboard install` / touch `~/.mission-control` / launchd | YES — process policy this session |
| Did not modify `mc-panel.swift` | YES — diff scope |

## Hard rails respected

- Isolated worktree + branch `cursor/attention-lane`
- No push/merge to main; no PR
- No `dashboard install`; no writes under real `~/.mission-control`
- bash-3.2 safe; python3 stdlib only; no new deps / CDN
