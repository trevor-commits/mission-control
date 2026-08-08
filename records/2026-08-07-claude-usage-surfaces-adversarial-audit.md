# Claude usage-surfaces adversarial audit

- date: 2026-08-07
- type: full adversarial cross-AI implementation audit
- audited chat name: `Mission control usages and Twitter API`
- provider: Claude Code
- supplied chat ID: `71f37b5b-839f-4ac5-a933-cfa159ce18d4`
- source transcript: `/Users/gillettes/.claude/projects/-Users-gillettes-Coding-Projects-global-implementations/71f37b5b-839f-4ac5-a933-cfa159ce18d4.jsonl`
- audited repo: `/Users/gillettes/Coding Projects/mission-control`
- scope: the source chat's Mission Control usage dashboard, compact web panel, native menu-bar summary, tests, and unmentioned trust/accessibility/refresh/practicality gaps
- repo fingerprint: branch `codex/operator-ux-audit-019fdf95`, based on `origin/main@febb460ae9c2fb87d04ed0927c8e51a2f0b02f1f`; source verification is green and delivery evidence is appended after landing
- prior audit reference: `records/2026-07-23-full-dashboard-redesign.md`, `records/2026-07-23-menu-bar-panel-redesign.md`, and the 2026-08-06/2026-08-07 usage-surface rows in `todo.md` `Completed`
- source/work chat: Claude Code `71f37b5b-839f-4ac5-a933-cfa159ce18d4`
- audit chat: Codex `019fdf95-6246-7301-a2b8-3316ff00bcbd`
- implementation/disposition chat: Codex `019fdf95-6246-7301-a2b8-3316ff00bcbd`
- separate follow-up audit: yes; the pre-remediation review opened one Critical and nine Important findings. The final concurrent reviewer was interrupted by the host engine shutdown before returning a verdict, so the integrating Codex performed and records an explicit skeptical current-tip pass rather than implying independent final approval.
- commands / evidence: direct `chat-source describe`, exact transcript review, current branch/diff inspection, hostile-state review, focused native/panel/browser/render suites, full `scripts/verify.sh`, CloakBrowser wide captures, and 390px browser captures
- tested: dashboard shell/data/install `PASS=85 FAIL=0`; dashboard browser 306 assertions; compact panel browser 12/12; native headroom 16/16; native core summary 15/15; eight-tab render smoke; full repository verifier exit 0; wide Home/Usage and narrow Home/Git rendered inspection
- not tested: manual VoiceOver traversal, future natural scheduled refresh, commit/push/PR/main containment, installed byte identity, or post-install live canary at this source-verification checkpoint
- findings opened or updated: `MC-AUD-01` through `MC-AUD-11`
- fixes closed / verified: all eleven source findings and the causal wording defect are regression-backed and source-green; delivery/runtime parity is a separate post-merge gate
- declined / deferred findings: none material; unnecessary framework/service/dependency expansion excluded
- better-path challenge: one fail-closed feed trust contract across every renderer/native consumer, with polish layered only on trusted data
- references: this record, `todo.md`, branch `codex/operator-ux-audit-019fdf95`, and visual evidence under `/Users/gillettes/.codex/visualizations/2026/08/08/019fdf95-6246-7301-a2b8-3316ff00bcbd/after/`; PR/merge/install evidence is appended after those actions occur
- by: Codex audit task `019fdf95-6246-7301-a2b8-3316ff00bcbd`
- decision status: accepted findings implemented and source-verified; landing/install in progress
- linear: self-contained cross-AI audit repair; Mission Control remains in repo-only mode

## Scope and audit method

The audit did not accept the source chat's implementation and verification claims at face value. It resolved the supplied chat directly, reviewed the source transcript and the Mission Control implementation surfaces it changed, inspected the current renderer/native-consumer/test contracts, and challenged the result as stale, missing, malformed, partial, torn, keyboard-only, narrow-screen, and long-running operator states. The review covered `dashboard/index.html`, `dashboard/panel.html`, the native menu-bar summary consumer, dashboard and browser harnesses, usage ordering/freshness/provenance, search/filter persistence, and refresh continuity.

The product standard used was Mission Control's stated purpose: a local operator should be able to trust what is shown without reading raw JSON, and missing or inconsistent input must never become a reassuring all-clear state.

## Material findings

| ID | Severity | Finding | Why it matters | Disposition |
|---|---|---|---|---|
| MC-AUD-01 | Critical | The native menu-bar summary could clear an alert when attention, decisions, or automation input was missing, stale, malformed, partial, or torn across feeds. | A compact always-visible status is more dangerous when it is falsely reassuring than when it admits uncertainty. | Closed at source; fail-closed summary parsing passes 15/15 focused core-feed checks. Installed parity remains a post-merge gate. |
| MC-AUD-02 | Important | The web panel trusted decision and automation payloads without reconciling arrays, counts, exceptions, and attention summaries, so inconsistent feeds could render `All clear`. | Independently refreshed local files can be observed between writes; an envelope alone does not prove internal consistency. | Closed at source; strict shape/count reconciliation and unknown-state rendering pass the 12-case panel browser suite. |
| MC-AUD-03 | Important | Live usage displayed producer age instead of each provider reading's age and ignored a current headroom error sidecar. | A recently rewritten file can contain an old provider reading; the old value must not look fresh. | Accepted; reading-level provenance, feed-error fallback, and explicit stale/unknown treatment are in the active branch. |
| MC-AUD-04 | Important | A malformed live headroom row such as `null` could throw during rendering before the previous summary was cleared. | One bad provider row could freeze stale-good UI or blank the usage surface. | Closed at source; the complete row set is validated before render and malformed input clears stale-good totals in browser coverage. |
| MC-AUD-05 | Important | The native headroom reader used a weaker trust contract than the full dashboard and could accept errored, partial, stale, or lower-trust sibling rows. | The menu bar and dashboard could disagree about whether a provider was safe to use. | Closed at source; native trust/freshness parity passes 16/16 focused checks. |
| MC-AUD-06 | Important | A focused search/control could suppress the page's periodic refresh indefinitely. | An operator who leaves a search field focused can unknowingly stare at frozen operational state. | Closed at source; interaction deferral is bounded to 15 seconds with retry and context restoration, covered by the browser suite. |
| MC-AUD-07 | Important | Home's actionable needs-attention row used a click handler on a non-button element. | Mouse users could navigate, but keyboard and assistive-technology users did not receive the same action. | Closed at source; native button semantics, ARIA state, and keyboard activation are browser-asserted. |
| MC-AUD-08 | Important | X usage detail labeled arbitrary retained dates as a seven-day view. | Old history could be mistaken for current-week activity and distort routing decisions. | Closed at source; only current UTC seven-day readings render, with fixture and browser coverage. |
| MC-AUD-09 | Important | An early dashboard test gate treated every live-data fingerprint change as corruption even when the known Mission Control refresher legitimately wrote it. | A scheduled tick could create a false test failure, while duplicated attribution logic could drift between gates. | Closed at source; shared refresher-only attribution passes the 36-check shell suite. |
| MC-AUD-10 | Important | Healthy green providers could sort before blue providers that were not captured or not configured. | The list hid setup/action work below providers that required no operator action. | Closed at source; action-state rank and lowest-headroom ordering are browser-asserted. |
| MC-AUD-11 | Important | Narrow Git tables technically stayed inside the document but hid problem and next-action fields behind an unmarked horizontal swipe. | The mobile operator view concealed the fields needed to decide what to do. | Closed at source after final visual inspection; Git tables become labeled stacked cards at 600px and 306 browser assertions prove all critical cells fit without horizontal scrolling. |

## Beyond-the-source improvements

The repair deliberately goes beyond the source chat's named usage cards. The active branch adds scalable Map/Chats/Open-work search and filters; keyboard-native disclosure and navigation; persisted tab/filter/focus/scroll context; reduced-motion control; clearer headroom grouping and actionability ordering; labeled mobile Git cards; and narrow-screen/contrast affordances. These source behaviors are focused/full/browser green. Main containment, pinned installation, and live file-page proof remain distinct delivery gates.

## Causal-claim correction

The source work observed a live z.ai Coding Plan weekly window at 100% and also had historical `claude-glm` HTTP 429 failures. That establishes correlation only. No request-level response, provider error body, or timestamped quota-reset evidence in this audit proves that the weekly window caused those historical 429s. Durable wording must say the weekly limit was observed saturated at that time and that it was a plausible contributor, not an established root cause.

## Commands and evidence

- Exact chat resolution: `/Users/gillettes/.codex/scripts/chat-source describe 71f37b5b-839f-4ac5-a933-cfa159ce18d4`.
- Source evidence: the exact Claude transcript path listed above, not its display title or a nearby session.
- Repository evidence: `git status --short`, `git diff --stat`, renderer/native-consumer source review, the pre-remediation adversarial review, and an explicit skeptical current-tip self-review after the final external reviewer was interrupted.
- Current branch/base evidence: `codex/operator-ux-audit-019fdf95` at `febb460ae9c2fb87d04ed0927c8e51a2f0b02f1f` before the audit repair is committed.
- Source verification: `/bin/bash scripts/dashboard.test.sh --require-shell`; `node scripts/dashboard-browser.test.js`; `node scripts/panel-browser.test.js`; `python3 scripts/mc-panel-headroom.test.py`; `python3 scripts/mc-panel-summary.test.py`; `node scripts/dashboard-render-smoke.js .`; `/bin/bash scripts/verify.sh`; all exit 0.
- Visual evidence: CloakBrowser 1440px Home/Usage captures and browser-harness 390px Home/Git captures were inspected; the first narrow Git capture opened `MC-AUD-11`, and the replacement shows every critical field as a labeled card without horizontal scrolling.
- Delivery evidence: commit, PR, merge SHA, install stamp, and live canary are appended only after those actions occur.

## Tested

- Audit/source identity and current repository scope were resolved directly.
- Structural counterexamples were reviewed against the relevant renderer, native consumer, and harness contracts.
- Focused and full suites are green at the source-verification tip: dashboard shell/data/install `PASS=85 FAIL=0`, dashboard browser 306 assertions, compact panel browser 12/12, native headroom 16/16, native core summary 15/15, eight-tab render smoke, and full verifier exit 0.

## Not tested yet

- Manual VoiceOver traversal and a future natural 60-second refresh cycle.
- Independent final exact-tip review: the attempted reviewer produced no result before the shared engine shutdown, so no independent approval is claimed.
- Commit/push/PR/checks, `origin/main` containment, installed-file byte identity, and a live post-install canary at this checkpoint.

## Fixes closed or verified

All eleven source findings are closed by regression and rendered evidence. The causal wording defect is corrected durably here and in `todo.md`. Runtime parity remains unclaimed until exact merged bytes are installed and read back.

## Declined or deferred findings

None of the material findings above was declined. No new framework, service, dependency, remote dashboard, or credential flow was introduced; those would conflict with the local/offline product boundary and were not needed to fix the defects.

## Better-path challenge

The smaller trustworthy design is one fail-closed feed contract used by every surface: validate the envelope, current error sidecar, cadence, row shape, per-reading age, and cross-field counts before deriving reassuring copy. Then preserve operator input for a bounded interval and refresh automatically. Visual polish should sit on top of that trust model rather than mask stale or inconsistent data.

## Continuity, coherence, and references

- Durable home: this record plus the linked `todo.md` Work, Audit, Branch, Feedback, and Test evidence surfaces.
- Ripple Check: `PROJECT_INTENT.md`, `AGENTS.md`, `CONTINUITY.md`, `COHERENCE.md`, `LINEAR.md`, and the prior redesign records were checked for affected claims. No product-intent or governance contract changed; only audit truth and completion wording needed companion updates.
- References: branch `codex/operator-ux-audit-019fdf95`; `todo.md`; source transcript above; visual evidence directory above; delivery evidence is appended after landing/install.
- by: Codex audit task `019fdf95-6246-7301-a2b8-3316ff00bcbd`.

## Final delivery disposition — 2026-08-08

- Implementation head `da11b8a780359077db5d49e35c2db08cda1c0e34` merged
  through PR #13 at `3d8b897c227d2ae624781df33299f3b80ab70538`; remote
  ancestry proves the reviewed head is contained by current `origin/main`.
- The live Mission Control install stamp attests provenance `head` at that exact
  merge, with nine required runtimes and four required assets verified.
- A merged-source usage refresh is fresh, and the installed headroom feed exactly
  matches the Global merged collector output with its summary trust fields intact.
- Mission Control's independently existing `chats` and `decisions` degradation
  remains visible and leaves the aggregate launchd collection at exit 1. That is
  outside this usage-surface acceptance item and is not rewritten as a successful
  canary.

The eleven source findings, merge, installed provenance, and task-owned live feed
contract are complete. Manual VoiceOver, a future natural refresh, and an independent
final exact-tip verdict were not observed and are not claimed. No new dependency,
service, remote dashboard, activation-gated job, or credential flow was introduced.
