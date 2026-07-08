# Mission Control — Improvement Packets (authored 2026-07-08, session 1ef98716)

Spec for implementing agents (Opus / Codex / GLM). Each packet is self-contained:
why (Trevor's actual complaint), exact changes with file anchors, acceptance
criteria, and the verify commands the auditing session will re-run. Do NOT mark a
packet done unless its verify commands pass on the real machine.

## Global invariants (bind every packet)

- Repo: `~/Coding Projects/mission-control` (branch per packet or grouped; never commit to main directly if the change is >1 packet — use a branch + leave it for audit).
- Single-file dashboard stays: `dashboard/index.html` opens via `file://`, offline. No build step, no CDN, no external fonts, no fetch of sibling JSON (data ships as `data/*.js`). New JS libs only as local files under `dashboard/vendor/` loaded by relative `<script src>`.
- python3 stdlib only; bash-3.2-safe shell. Tests: `scripts/<name>.test.sh`, mktemp fixtures, env overrides (`MISSION_CONTROL_HOME`, `CHAT_GRAPH_HOME`, `DASHBOARD_CMD_*`, `AUTOMATION_STATUS_LAUNCHCTL`), never real `$HOME` in tests, suite <90s.
- Security floor: state dirs 0700; renderers `textContent` only (zero `innerHTML`); committed fixtures synthetic; transcript-derived text redacted; `--serve` binds 127.0.0.1 only.
- Wording floor (Trevor-calibrated): plain words a smart non-programmer instantly gets. NO internal rule codes (ER-/GR-…), no raw state names (`degraded`), no unexplained jargon (`yield 13/18`), no raw session-id as a title without a fallback label, durations humanized ("resets Aug 1", never "675h"). Every clickable thing must look clickable; every label must answer "what do I do with this?"
- Every code change ships a test that FAILS without it. The render smoke (`node scripts/dashboard-render-smoke.js .`) and all three suites must stay green: `bash scripts/chat-graph.test.sh && bash scripts/automation-status.test.sh && bash scripts/dashboard.test.sh --require-shell`.
- Evidence to return per packet: full diff, verbatim verify output incl. exit codes, claims list (done / untouched / uncertain).

---

## P1 — Usage tab: real, fresh, honest numbers (Trevor's top gripe)

**Why:** "None of this information is up to date… codex says 65% stale… GLM 0% unknown… copilot resets and 675 — what does that even mean?" The tab shows stale/empty rows with raw field jargon.

**Changes (mostly `scripts/usage-snapshot`, plus renderUsage in `dashboard/index.html`):**
1. **Codex freshness**: the 5h/weekly numbers come from the newest `~/.codex/sessions/**/rollout-*.jsonl` rate-limit stamp and go "stale" when >30min. Add a `--fresh` mode: when the newest stamp is older than 30min AND `codex` binary exists, trigger one tiny probe (`codex exec --skip-git-repo-check -c model="gpt-5.3-codex-spark" "reply OK"` with `timeout 60`, output discarded) then re-read. The chats/usage collector in `scripts/dashboard` calls `usage-snapshot --fresh --no-ccusage` at most once per 30min (guard with a marker file `$MISSION_CONTROL_HOME/.usage-fresh-at`). Never probe more than 2×/hour (cost).
2. **Claude wording**: no % exists for subscription — render what IS known: "burning ~N tokens/min · window resets 4:12 PM" from the ccusage fields already in the feed (`burn_tpm`, `resets_at`). Kill "no numeric read".
3. **GLM real usage**: z.ai exposes a usage/billing endpoint on the same API key `claude-glm` uses (key in Keychain service `zai-api-key`). Add adapter `glm_usage()` in usage-snapshot: `security find-generic-password -s zai-api-key -w` → GET their usage endpoint (check https://docs.z.ai for the current path — likely `/api/paas/v4/usage` or account/billing; if the documented endpoint 404s, print a note row "usage endpoint not available on this plan" rather than 0%). Timeout 10s, degrade to today's health-only row on any failure.
4. **Copilot**: GitHub usage API needs a token — read `gh auth token` if `gh` is logged in (it is on this machine); GET `https://api.github.com/rate_limit` is NOT copilot quota; the real endpoint is the Copilot **premium requests** usage in `https://api.github.com/users/{user}/settings/billing/usage` family — verify the current endpoint in GitHub docs; if individual-plan data isn't exposed, keep schedule-derived reset but say plainly "GitHub doesn't share your remaining Copilot quota — resets Aug 1".
5. **Hermes**: credits live with Hermes' provider config on T7 (`~/.hermes` → `/Volumes/T7/Offload/hermes-home`). Read whatever credit/balance state its config/state.db exposes (inspect `hermes status` output first — parse that if it prints credits). T7 unmounted → "external drive not mounted" row, never 0%.
6. **Cursor**: no public API. Implement the manual route honestly: `usage-snapshot set --provider cursor --used-pct N` writes `~/.usage-snapshot/manual.json` with a timestamp; row renders "N% (you entered this DATE)" and goes amber after 7 days. Dashboard usage tab shows a one-line hint on the Cursor row: "update with: usage-snapshot set --provider cursor --used-pct N".
7. **Wording pass in `renderUsage`** (index.html): humanize resets ("resets in 2h 52m" under 24h, else "resets Tue Aug 1"); confidence chips get plain words (official / estimate / old data); "stale" row adds "refreshing on next pass" when --fresh is wired; delete any remaining `undefined`/`?`/`—` renders (every row must say something a person understands).
8. Sync note: `scripts/usage-snapshot` here is a vendored copy — apply the same diff to `global-implementations/scripts/usage-snapshot` (upstream) in a separate commit there, or the two drift.

**Acceptance:** `scripts/usage-snapshot --fresh` returns codex rows with `confidence != stale` within 90s (when codex CLI works); GLM row shows a real % or the honest not-available note; cursor manual entry round-trips; NO row renders `undefined`, bare `?`, or raw hours >48h. New tests: manual-entry round-trip; fresh-guard (marker file prevents double probe); renderer humanized-reset (fixture with resets_in_min=40500 renders a date, not hours).
**Verify:** `bash scripts/dashboard.test.sh --require-shell` + `scripts/usage-snapshot --fresh | python3 -m json.tool | head -40` + screenshot of #usage.
**Recommended model:** Codex gpt-5.5 high (API research + adapters) with the z.ai/GitHub endpoint verification done via live docs, not memory.

## P2 — Usage → routing: feed the numbers into model choice (the payoff)

**Why:** "I want this information fed into our harnesses so they make better decisions and not waste usage… use the model with the most credits left… strong models only for planning/edits/double-checking… if we're out of Claude, use another API that includes Opus/Fable."

**Changes (this is in `global-implementations`, not this repo — the router + spawn helpers live there):**
1. `scripts/usage-router` (gl): add `--pick <tier>` returning ONE `provider model effort` line chosen by: (a) hard-filter providers with `used_pct >= 95` or `health != ok`; (b) rank remaining by remaining-% (unknown counts as 50, manual counts at face value with age decay); (c) tier constraints — `strong` only returns opus/fable/gpt-5.5-class, `bulk` prefers glm/spark/haiku-class with most headroom. Add `--explain` printing the ranking table.
2. **Fallback map** as data: `gl/config/model-fallbacks.json` — per strong model an ordered list of alternate routes (e.g. claude-opus → [anthropic-api key if present, bedrock if configured, gpt-5.5]). Router consults it when the primary provider is exhausted; entries whose auth isn't configured are skipped with a note. Ship the file with the routes that exist TODAY (codex, glm, native claude) and placeholders marked `"configured": false` for API routes Trevor hasn't set up — the router must tell him exactly what to set up when it skips one ("Anthropic API key missing — add with: security add-generic-password -s anthropic-api-key -w").
3. **Wire-in points** (each one line + a test): `~/.codex/scripts/spawn-claude-worker` and `spawn-codex-worker` — when `--model` is NOT explicitly passed, call `usage-router --pick bulk` instead of hardcoded defaults; `scripts/delegate-audit-loop.sh` — same for its family default resolution. Explicit `--model` always wins (routing must never override a deliberate pin).
4. **Dashboard surface**: usage tab gains a small "What I'd pick right now" line per tier (bulk → X, strong → Y) by shelling `usage-router --pick` in the usage collector; makes routing visible/debuggable.
**Acceptance:** `usage-router --pick bulk --explain` returns a sane choice that changes when a provider's snapshot is edited to 96% used (test with a fixture snapshot via env override); spawn helpers without `--model` log which router pick they used; explicit `--model` unaffected (test).
**Verify:** router unit test + one live `spawn-claude-worker --task "reply OK" --title "worker:router-smoke"` showing the routed model in its log.
**Recommended model:** Opus 4.8 high (routing policy is judgment + touches spawn helpers).

## P3 — Map: from hairball to "how work evolved"

**Why:** "A diagram might be nice to see where things started from and how they developed and evolved… one chat starts, another audits, a sub-issue…" Default map is dense; 5,210 of 5,350 edges are weak "mentions" — they ARE the hairball.

**Changes (all in `dashboard/index.html`, renderMap/scopeGraph/buildCy):**
1. **Edge-type toggles**: legend items become click-to-toggle chips; DEFAULT hides `references` (mentions) and `same_issue`; strong lineage (started/audited/continued/messaged/you-linked) shown. Persist toggles in `localStorage`.
2. **Search**: a text input above the graph; typing ≥3 chars matches node titles (case-insensitive substring), dims non-matches, first match centered (`cy.center(node)`); Enter focuses that chat's web (existing FOCUS_CHAT flow).
3. **Timeline lineage view** (the "see how it evolved" ask): a second layout mode toggle "Timeline" — x = first_seen_at (scale to container width, month gridlines + labels), y = lane per repo (or per root-lineage when focused). Implementation: `layout: {name:'preset'}` with computed positions; cap same as now. In focus mode, the chat's tree reads left→right in time order: root chat, then the chats it started, their audits, etc.
4. **Node tooltips**: hover shows full title + provider + repo + date (a positioned div, since cytoscape has no native tooltip; reuse `mc-cmd` styling).
5. **Cluster labels in default view**: compute connected components ≥4 members, overlay each with its dominant repo name (a floating label div at the component centroid).
6. Perf guard: all of the above must keep first paint <3s at 260 nodes (measure with `performance.now()` around buildCy; log to console).
**Acceptance:** default view visibly un-hairballs (mentions hidden); search finds "mission control" chats; Timeline mode orders this build's own lineage left→right; render smoke still green (map degrades without cytoscape).
**Verify:** suites + headless screenshots of #map default, #map with search term, #map timeline mode.
**Recommended model:** Opus 4.8 high (visual judgment; keep to the existing token/class system).

## P4 — Chats tab → "Open work" (kill the confusion)

**Why:** Trevor's walkthrough: "(untitled) cf391355… what does Claude mean… what does live mean… dash dash resume… what does this really tell me? I'm confused." The flat-list + cluster-cards tab is now redundant with the Map and reads like internals.

**Changes (`dashboard/index.html` renderChats, rename tab label to "Open work"):**
1. Purpose statement at top: "Chats that still owe something — finish, hand off, or dismiss."
2. Show ONLY chats with unfinished items (default), grouped by repo, newest activity first. Each row: title (never a bare id — see P7), when last active ("2d ago"), what it owes in plain words (the existing `openEndHuman`), and TWO labeled buttons: "Reopen this chat" (copies resume cmd; sub-caption "paste in a terminal") and "Show on map" (deep-links FOCUS_CHAT — pattern already exists in Home).
3. Kill the cluster cards section entirely (Map owns relationships now). Kill unexplained chips: "live" becomes "working now" with tooltip "used in the last 30 minutes"; provider chip gets a tooltip "which AI this chat ran on"; "76 new today" becomes "76 conversations found today (across all your AIs)".
4. "Dismiss" affordance per owed item: a small ✕ that copies `chat-graph resolve <id> <hash>` with sub-caption "paste in a terminal to dismiss" (no direct writes from the page — it's a static file; the copy-command pattern is the contract).
**Acceptance:** tab contains zero raw session-ids as titles, zero unexplained words (audit the rendered text with the smoke: extend it to assert the strings "active now" tooltip exists and no `(untitled)` appears when the fixture provides first_prompt); every button labeled with a verb.
**Verify:** suites + render smoke + headless screenshot of #chats.
**Recommended model:** Opus 4.8 high.

## P5 — Needs-attention that actually triages

**Why:** His Home screenshot: seven near-identical rows of ancient worker chats ("worker:er034-pkt1c-… 2 unfinished items · waiting to confirm a tracked change") + "+2112 more across the tabs". Oldest-first sorting surfaced 3-week-old junk; the overflow line is useless.

**Changes (`dashboard/index.html` harvestExceptions + renderHome):**
1. **Score, don't just sort**: score = severity (red=2, amber=1) + recency boost (active <48h: +2, <7d: +1) + kind boost (automation red +2, git diverged +2, usage red +2, chat open-end +0). Sort desc. This inverts today's oldest-first.
2. **Suppress stale chat noise at the source**: chat open-end exceptions ONLY for chats active in the last 7 days OR with a `closeout_handoff` kind; drop `register_unverified` from Home entirely (it stays visible on the Open-work tab).
3. **Collapse look-alikes**: >3 rows sharing a title prefix (e.g. `worker:er034-`) collapse to one row "12 old worker chats have unfinished handoffs" → clicking shows them on the Open-work tab filtered.
4. **Overflow by kind**: "+2112 more" becomes "Also: 2,041 older chats with leftovers · 23 repos need git attention · 2 usage warnings" — each phrase a link to its tab.
**Acceptance:** with the current real data, Home shows automation/git/usage items above ancient worker chats; no "+N more across the tabs" string remains. Fixture test: a fixture with 1 red job + 5 stale worker chats + 1 recent chat must order red job first, recent chat second, collapsed-stale third.
**Verify:** suites + extended smoke assertions + headless screenshot of #home.
**Recommended model:** Opus 4.8 high.

## P6 — Open-end noise reduction (4,282 → the real number)

**Why:** Most "unfinished items" are historical register-code mentions — noise that inflates every count.

**Changes (`scripts/chat-graph`):**
1. `register_unverified` open-ends: only create/keep for sessions with activity in the last 14 days (auto-resolve older on ingest — set `resolved_at` with reason `aged-out` in evidence).
2. `closeout_handoff`: keep, but auto-resolve when a later `continues`/`spawned` edge exists from that session (the handoff was picked up) — currently only checked at creation.
3. Export counts split: `counts.open_now` (active-7d chats) vs `counts.open_total`; Home card + strip use `open_now`.
**Acceptance:** after `chat-graph ingest`, `counts.open_now` on the real machine drops to a two-digit-ish honest number; aged-out items carry `resolved_at`. Tests: aged-out auto-resolve; picked-up handoff auto-resolve; counts split.
**Verify:** `scripts/chat-graph.test.sh` + live `chat-graph export --json && python3 -c "...print counts"`.
**Recommended model:** Codex gpt-5.5 high.

## P7 — No more "(untitled) cf391355"

**Why:** Titles are the UI. Raw ids read as broken.

**Changes (`scripts/chat-graph`):**
1. Enrichment priority: sessions WITH open ends or edges first (they're the ones the UI shows), newest first; batch 150 (was 50) when invoked from `export` (still capped by time: stop after 20s of describes).
2. Worker sessions: derive a display title from their `Spawned-by:` metadata when untitled — "Worker for: <parent title>" (parent title from the sessions table).
3. Export fallback order: title → first_prompt first 60 chars (already stored) → "Worker for: parent" → "(chat from DATE)" — the bare-id form is banned from export output (validate-export gains this check).
**Acceptance:** on real data, `export` contains zero `(untitled)` nodes among nodes with edges/open-ends (spot-check top 100); validate-export rejects a fixture node titled `(untitled) abc`.
**Verify:** chat-graph suite + live export grep.
**Recommended model:** Codex gpt-5.5 high.

## P8 — Git tab: act, don't just look

**Why:** "A button to create a PR or something… adds functionality."

**Changes (`dashboard/index.html` renderGit; NO direct git execution from the page — copy-command pattern):**
1. Per-repo action buttons by state, each copying a ready command with a sub-caption "paste in a terminal": needs commit → `cd "<repo>" && git add -A && git commit` (caption "review before committing"); needs push → `cd "<repo>" && git push`; unmerged branch → `cd "<repo>" && gh pr create --head <branch> --fill` (only when the repo has a GitHub remote — feed must say; see 3).
2. Branch age + size: show "branch feat/x — 12 days old, 3 commits" (data already in scan output branches[]; add commit count in `scan-unfinished-work` if absent).
3. Feed addition (`scripts/scan-unfinished-work`, vendored + upstream): per repo add `has_github_remote` bool + per branch `ahead_count`; keep exit-code contract (0/1) intact.
4. "Open in editor" button per repo: copies `cursor "<repo>"` (or `code`) — detect which exists at collect time and ship the right one in the feed.
**Acceptance:** every red/amber repo row has ≥1 labeled action; commands quote paths with spaces; `gh pr create` only offered when a GitHub remote exists. Tests: feed contract for the new fields; renderer offers the right action per state (fixture).
**Verify:** suites + screenshot of #git.
**Recommended model:** Codex gpt-5.5 high.

## P9 — Automation tab: re-run + streaks + next run

**Why:** Copilot's list (rightly): status, last run, next run, failure streak, re-run button.

**Changes:**
1. `scripts/automation-status`: add `next_run_estimate` (interval jobs: last evidence mtime + interval; calendar: next occurrence of the schedule string — implement for the two forms in jobs.json: "HH:MM daily" and "every Ns"), and `failure_streak` (consecutive nonzero exits — persist a tiny history at `$MISSION_CONTROL_HOME/job-history.json` written by the automation collector each pass: {label: [last 20 {ts, state}]}).
2. Renderer: card shows "next run ~3:40 PM" + a 20-dot mini-strip of recent passes/fails + "Run now" button copying `launchctl kickstart -k gui/$UID/<label>` (caption "paste in a terminal").
**Acceptance:** streak survives collector restarts (history file); next-run correct for both schedule forms (unit tests with fake now); strip renders in smoke.
**Verify:** automation suite + dashboard suite + screenshot of #automation.
**Recommended model:** Codex gpt-5.5 high.

## P10 — Daily focus summary on Home

**Why:** Copilot's best idea: "Yesterday you touched 3 repos, had 7 open chats, 2 automations failed."

**Changes:** compute in the collectors (not the page): `scripts/dashboard` gains a tiny `summary` section in the automation or a new `meta` feed — yesterday's numbers from: chats feed `first_seen_at` counts, git feed repos with recent commits (needs `last_commit_age_days` per repo in scan feed — add), job-history fails (P9's file). Home renders one sentence under the greeting: "Yesterday: 3 repos touched · 41 chats recorded · 1 automation failed."
**Acceptance:** sentence renders from fixture data in the smoke; numbers match a hand-count on fixtures.
**Recommended model:** Codex gpt-5.5 high (after P9 lands — depends on job-history).

## P11 — CI so this can't silently rot

**Why:** the repo is on GitHub now; the suites only run when someone remembers.

**Changes:** `.github/workflows/ci.yml` on `macos-latest`: checkout, `bash scripts/chat-graph.test.sh`, `bash scripts/automation-status.test.sh`, `REPO_ROOT=$PWD bash scripts/dashboard.test.sh --require-shell`, `node scripts/dashboard-render-smoke.js .` (node preinstalled on the runner). Cache nothing (fast already). README badge.
**Gotchas:** launchctl doesn't exist meaningfully on runners — automation-status tests already stub it via env; verify no test touches real `$HOME` (they shouldn't per invariants — if one does, that's a bug to fix, not to work around).
**Acceptance:** green run on GitHub Actions for the current main.
**Recommended model:** Codex spark (mechanical) — but only AFTER confirming the suites are hermetic on a clean runner.

## P12 — Autonomy loop, phase 1: the decision queue + loud alerts (design-then-build)

**Why:** "I don't have to keep checking… fix the safe stuff automatically… if it needs me, glaringly obvious." Boundaries: never merge/push active work, never destructive.

**Scope for phase 1 (deliberately small):**
1. **Decision queue**: collectors append decision-needed items to `~/.mission-control/decisions.jsonl` — {id (stable hash), kind, title, action_cmd, first_seen, last_seen, state: open|dismissed}. Sources: automation red, git diverged/no-remote, usage red, repo-groom's DECIDE list (read `~/.local/state/repo-state-watcher/groom-last.txt`).
2. **Loud channel**: a `scripts/decision-alert` run by the existing 300s ticker (guarded to fire per item at most once/24h, tracked in the queue file): sends each NEW open decision via the existing Telegram bridge (`mobile-connect` bot — reuse its send path; read its config, don't duplicate tokens).
3. **Dashboard**: Home needs-attention pins queue items above everything with a distinct "needs a decision" style; a dismiss ✕ copies `dashboard decide dismiss <id>` (new CLI subcommand writing state=dismissed).
4. **Explicit NON-goals phase 1** (write them in the code header): no auto-merge, no auto-PR, no auto-push of active work, no acting on decisions — surface only. Safe auto-fixes remain repo-groom's job (already live).
**Acceptance:** a simulated red job produces exactly one Telegram message and one pinned Home row; dismiss round-trips; restart doesn't re-alert (dedupe file). Tests with a stubbed send command (`DECISION_ALERT_SEND_CMD` env).
**Verify:** new `scripts/decision-alert.test.sh` + live single-fire proof.
**Recommended model:** Opus 4.8 high (touches alerting + boundaries).

---

## P13 — One loose-ends ledger (the spine): every source writes into `open_ends`, nothing parallel

**Why (Trevor's ask):** "I start a lot of chats and resolve a lot of issues, then move on and they stay open. I want one dedicated view of where things are, what's being worked on, what needs work, what loose ends exist." The store exists (`open_ends` table in `scripts/chat-graph`) but only catches 2 of ~6 real sources, so no single honest list exists. Do NOT build a new tool — extend this table so it's the ONE place. Anti-duplication is the whole point.

**Implemented state (verified 2026-07-08):** `open_ends(session_id, kind, text, text_hash, resolved_at, first_seen_at)` now collects chat handoffs, unverified register references, repo `todo.md` items, latest nightly findings, Git dirty/ahead/branch decisions, and open enforcement-register rows. Each source reconciles into the same table and auto-resolves when the underlying signal clears. `chat-graph export` now exposes `data.loose_ends`, and the dashboard Home + Chats/Open work surfaces read that flat list instead of rebuilding separate lists.

**Changes — collectors writing the SAME table with a distinct `kind` + stable `text_hash`, each with its own auto-resolve rule:**
1. **`todo_open`** — parse `todo.md` in each tracked repo (global-implementations + any repo the git scan sees) for unchecked `- [ ]` items under a `## Work`/`## Active`/`## Todo` heading. `session_id` for repo-scoped items = a synthetic `repo:<name>` node (add a lightweight non-chat node kind so the ledger holds repo items too — the schema already keys on a string id). Auto-resolve: item becomes `- [x]` or disappears. Cap per repo 50, skip archived/`## Completed` sections.
2. **`nightly_finding`** — read the latest `~/.claude/nightly-review/reports/*.md`; each flagged item (the report already lists "loose ends" / failures) becomes an open end on the chat/repo it names (fall back to `repo:<name>`). Auto-resolve: absent from a newer report.
3. **`repo_dirty`** — from `scan-unfinished-work --json`: uncommitted/unpushed/unmerged-branch per repo → one open end on `repo:<name>` with the plain action ("3 files uncommitted", "branch feat/x unpushed 12 days"). Auto-resolve: repo goes clean. (This is the same data the Git tab shows — the ledger just *also* counts it as a loose end so the daily view is complete; render reads one store.)
4. **`register_open`** — register rows with status not `verified`/`landed` → open end on `repo:global-implementations`. Auto-resolve: status advances.
5. **Age + owner metadata**: add `first_seen_at` (already have the pattern) + `age_days` in export; add a `severity` derived at export (`register_open` P0/security = red; detached/divergent Git state = red; unpushed Git work = amber; stale chat handoff >21d = grey/low). NO new "priority" column Trevor has to manage — severity is computed, never entered.
6. **Export**: `chat-graph export` gains a top-level `loose_ends` array (flat, all kinds, each: id, kind, source_node, text, action_hint, age_days, severity, resolve_cmd) so the dashboard has ONE list to render — the "Open work" tab (P4) and Home triage (P5) both read `loose_ends`, not per-source feeds. This is what kills duplication: sources converge here, consumers diverge from here.

**Explicit non-duplication rules (write in the code header):** collectors NEVER keep their own list file — they read their source live and reconcile into `open_ends` (insert-new + auto-resolve-gone) each ingest. The dashboard NEVER re-derives loose ends from raw sources — it reads `loose_ends` from the export. todo.md stays the human-editable source of truth for repo work; the ledger *reflects* it, never replaces it.

**Acceptance:** on real data, `chat-graph export | python3 -c "…print len(loose_ends), Counter(kind)"` shows the flat ledger; checking off a `todo.md` item then re-ingesting drops its `todo_open` row to resolved; a repo going clean resolves its `repo_dirty` rows. Tests (fixtures, env-overridden roots): each collector inserts on signal-present + resolves on signal-gone; repo:<name> synthetic node round-trips; export `loose_ends` shape.
**Verify:** `bash scripts/chat-graph.test.sh`; `node scripts/dashboard-render-smoke.js .`; live `chat-graph ingest && chat-graph export | jq '.loose_ends | group_by(.kind) | map({(.[0].kind): length})'`.
**Recommended model:** Codex gpt-5.5 high (data plumbing + careful auto-resolve logic; the auto-resolve rules are the correctness-critical part).

## P14 — End-of-day loose-ends robot: propose, auto-fix the safe class, escalate the rest

**Why (Trevor's ask):** "The ultimate goal is these taken care of automatically — I start them in motion, then they resolve. Maybe an end-of-day automation that looks for loose ends and autonomously fixes everything we started but didn't finish." Boundaries he's set: auto-fix safe stuff, alert loudly for real decisions, never merge/push active work, never destructive. Build this AFTER P13 (it acts on the one ledger) and lean on the autonomy queue from P12.

**Design — a nightly job `scripts/loose-end-runner` (own launchd, ~end of day), three tiers per loose end, decided by `kind` + `severity`, NOT by a model guessing:**
1. **Auto-fix (safe, reversible, mechanically checkable) — do it, log it, no ask:**
   - `repo_dirty` "unpushed" on a repo with a remote AND branch is NOT the currently-checked-out active branch AND no uncommitted changes → `git push` (the commit was a human's; pushing it isn't). NEVER push a branch with uncommitted work or the branch you're sitting on.
   - `todo_open` items already satisfied (the thing is done but the box wasn't checked) — DETECT ONLY, propose the check-off; do not edit `todo.md` autonomously in phase 1 (editing someone's todo list is too personal to auto-do first cut).
   - stale resolved-signal zombies → run the auto-resolve pass (already safe).
   - Each auto-fix is one reversible git/file op, captured in a run log with the exact command + before/after, so any single action can be undone.
2. **Delegate (bounded, has a clear finish + a test) — spawn a worker via the existing audit loop, land on an isolated branch, NEVER merge/push, leave it for Trevor:**
   - a chat's `closeout_handoff` that names a concrete next step in a repo → spawn a cheap worker (`delegate-audit-loop.sh`, GLM/Codex-spark tier) scoped to that repo with the handoff text as the task; governor verifies; result sits on `improve/looseend-<id>` for review. This is "start it in motion → it gets worked" without crossing the merge line.
   - Cap: N per night (start N=2), quota-preflight first, skip if the repo has uncommitted work (don't stack changes on a dirty tree).
3. **Escalate (needs a human decision) — one loud, deduped alert + a pinned dashboard row, never touched automatically:**
   - `register_open` P0/security, `repo_dirty` "diverged" (rebase/merge choice is a judgment call), unmerged branch >N days (keep or kill), anything the auto/delegate tiers refused. Route through P12's decision queue + one Telegram message per new item per 24h.

**Boundaries (hard, in the code header — these are the "never overstep" guarantees):** never merge, never push an active/uncommitted branch, never force-push, never delete a branch/worktree/file, never edit `todo.md` or any human doc in phase 1, never act on a chat that was active in the last 6 hours (it's live work — leave it alone). Everything the robot does is either reversible-and-logged or proposal-only. A `~/.mission-control/loose-end-runner/DISABLE` file hard-stops it.

**Report:** end-of-day summary (reuse the nightly-review/Telegram path, don't build a new channel): "Tonight: pushed 3 finished branches · started 2 handoffs (on branches for your review) · 4 need your call → dashboard." Dashboard Home shows the same summary + the pinned decisions.

**Acceptance:** dry-run mode (`--dry-run`, default first) prints the planned action per loose end with its tier and reason, touching nothing; the push tier refuses a dirty/active/remote-less branch (tested); delegate tier respects the per-night cap + quota preflight + dirty-tree skip (tested with stubs); escalate tier produces exactly one alert per new item (dedupe file, tested). Live proof: one real dry-run over the actual ledger showing correct tiering, reviewed before `--dry-run` comes off.
**Verify:** `bash scripts/loose-end-runner.test.sh` + `scripts/loose-end-runner --dry-run` reviewed on real data.
**Recommended model:** Opus 4.8 high (boundary logic + delegation orchestration — highest blast radius in the whole plan; the auto-fix guards are the part to over-test).

**Sequencing:** P13 → P14, and P14 builds on P12's decision queue. So the loose-ends spine slots into the plan as: P13 with wave 1 (data truth), then P14 last (after P12), because the robot should only ever act on a ledger that's already complete and a queue that already surfaces decisions.

---

## Suggested assignment + order

| Order | Packets | Model | Why |
|---|---|---|---|
| 1 | P1, P6, P7 | Codex gpt-5.5 high | data truth first — everything else renders it |
| 2 | P5, P4, P3 | Opus 4.8 high | the visible triage/UX layer, judgment-heavy |
| 3 | P8, P9, P10 | Codex gpt-5.5 high | actions + streaks + summary (P10 after P9) |
| 4 | P2 | Opus 4.8 high | routing policy (lives in global-implementations) |
| 5 | P11 | Codex spark | CI, mechanical |
| 6 | P12 | Opus 4.8 high | autonomy phase 1, after the queue's inputs (P5/P9) exist |

Audit contract (what the auditing session will do): re-run every packet's verify
commands cold, screenshot every changed tab headlessly, mutation-test any new
test (break the code, confirm the test goes red), and live-proof on real data —
worker claims are never accepted without command output.
