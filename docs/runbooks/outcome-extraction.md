# Outcome extraction runbook

## Purpose

`chat-graph extract-outcomes` is the optional plain-language classification layer behind Morning Brief. Deterministic Tier 1 parsing remains available at all times and stays authoritative for commands, commit SHAs, session IDs, decisions, and resolution evidence. Tier 2 classifies high-value session tails into a closed outcome taxonomy; Morning Brief combines that inferred classification with deterministic session-title and repo context so distinct sessions remain understandable without accepting model-authored facts.

High-value means the session is repo-linked, names a commit, or participates in a `spawned`, `audits`, or `continues` edge. Unchanged sanitized tails use the private cache and make no new model call.

## Safety contract

- Ingest and export never call a model.
- The extractor has its own lock and closes SQLite before every model call.
- Calls use `~/.local/bin/claude`, the OAuth-lock wrapper, with tools disabled and the prompt on stdin.
- Exit 75 is a benign defer. Timeout, invalid output, missing calibration, privacy rejection, and budget exhaustion all fall back to Tier 1.
- Transcript tails are assistant-only, bounded, and sanitized before egress. Raw tool output is excluded.
- The model selects only fixed outcome-taxonomy codes. Deterministic code validates the exact response schema and maps recognized codes to fixed plain-language sentences, so free-form model commands, IDs, SHAs, repo names, paths, secrets, counts, and contact details cannot enter a card. Unknown or malformed results fail open to Tier 1; the private cache stores only the canonical code shape; deterministic titles, repos, and anchors are copied from graph/Tier 1 only.
- Inferred `needs_trevor` codes enter the decision queue only as visibly inferred, non-actionable suggestions under `Possible follow-ups — Inferred`, never the red `NEEDS YOU` block. A current same-session Tier 1 rollback or newer Tier 2 omission supersedes them; a missing feed does not; re-enabling the unchanged cached code can reopen only that reversible supersession.
- Explicit persistent off dominates production, provider sampling, and synthetic test mode. Test mode requires an explicit local stub and cannot fall back to the installed model wrapper. Loaded caps must remain non-boolean integers at or below 100 calls and 10,000,000 tokens per day.
- State is private: graph/cache/health remain behind the mode-700 graph directory, while `~/.mission-control/outcome-extractor/` is mode 700 with mode-600 files.

## No-call planning

This reads recent provider-native stores and graph evidence but never invokes a model:

```bash
scripts/outcome-coverage --days 7 --json
```

The report separates structured-tail coverage from the high-value sessions eligible for a plain-language rewrite. Any dollar figure is modeled API-equivalent cost, not a claim of charged subscription usage.

## Required authorization gate

Do not run a live sample merely because the code and synthetic privacy suite pass. First obtain explicit authorization for bounded cross-provider transcript egress. Then review the sanitized packet design and provider kill switches.

The synthetic, no-network proof is:

```bash
bash scripts/outcome-extractor.test.sh
```

## Bounded provider sample

After authorization, sample at most one high-value session per provider and write content-free calibration evidence:

```bash
scripts/chat-graph extract-outcomes \
  --days 7 \
  --limit 5 \
  --sample-per-provider 1 \
  --calibration-out /tmp/morning-brief-outcome-calibration.json \
  --json
```

Inspect the JSON. It may contain only provider, model, input/output token counts, latency, and status for each call, followed by caps derived from observed tokens and two-times modeled daily headroom. It must contain no prompt, transcript text, path, secret, email, or phone number.

Apply the observed caps to the private runtime config:

```bash
scripts/chat-graph extract-outcomes \
  --apply-calibration /tmp/morning-brief-outcome-calibration.json \
  --json
```

The resulting config is `~/.mission-control/outcome-extractor/config.json`. Only providers with a successful sampled result are enabled; unsampled or failed providers remain off. The scheduled 04:40 extractor remains fail-closed until this calibrated config exists.

## Manual proof before activation

Run one bounded normal pass, refresh the chat feed, and inspect health:

```bash
scripts/chat-graph extract-outcomes --days 7 --limit 20 --json
scripts/chat-graph export --json --catchup-limit 0
scripts/chat-graph validate-export ~/.chat-graph/export/graph.json
```

Expected behavior: high-value sessions receive `method=tier2` inferred classifications rendered with deterministic session/repo context; allowlisted audit/spawn/continuation edges keep related outcomes together; deterministic Tier 1 decisions and anchors remain intact; inferred decisions remain visibly inferred and non-actionable; `data.outcome_extraction_health` contains content-free counts.

## Kill switches and rollback

The immediate persistent kill switch is:

```bash
scripts/chat-graph extract-outcomes --set-enabled 0 --json
```

Re-enable only after the issue is understood:

```bash
scripts/chat-graph extract-outcomes --set-enabled 1 --json
```

For one manual process, `MORNING_BRIEF_LLM=0` also disables Tier 2. Per-source-provider switches are `MORNING_BRIEF_LLM_CLAUDE=0`, `MORNING_BRIEF_LLM_CODEX=0`, `MORNING_BRIEF_LLM_CURSOR=0`, `MORNING_BRIEF_LLM_HERMES=0`, and `MORNING_BRIEF_LLM_COPILOT=0`.

Disabling Tier 2 does not remove or weaken Tier 1. Persistent off dominates any inherited positive environment value, existing cached prose remains local, and exports immediately prefer deterministic inputs.

## Scheduling

`launchd/com.gillettes.outcome-extractor.plist.template` starts at 04:40, ahead of the 05:00 brief, with bounded 04:47 and 04:54 retry opportunities. Successful unchanged work is served from cache without another model call; OAuth defers back off for five minutes, so a later slot can retry. It invokes the stable installed dashboard command, which routes to the explicit extractor command. The job writes a content-free last-run marker for Automation health.

Do not install or bootstrap the LaunchAgent until the authorized sample, calibration, manual proof, and explicit activation decision are complete.

The normal `dashboard install` path skips all activation-gated Morning Brief jobs. After the explicit activation decision, install/bootstrap them with:

```bash
DASHBOARD_INSTALL_ACTIVATE_GATED=1 \
  MISSION_CONTROL_HOME="$HOME/.mission-control" \
  REPO_ROOT="$PWD" \
  scripts/dashboard install
```

## Provider access denial and newer answers — October 21, 2026

A synthetic installed-wrapper probe returned HTTP 403 with subscription access disabled by the organization. No private transcript was sent in that probe. Generic failure counts previously concealed this cause.

A structured 401 or 403 now stops the entire model batch and writes the private content-free `outcome-extractor/provider-access.json` hold. Later runs make zero model calls while that file exists. Corrupt holds remain blocking. Deterministic ingest/export and native daily Codex review remain available; this is degraded coverage, not successful Tier 2 extraction. The hold applies to primary and escalation calls. Historical failed attempts remain historical failures.

Restore the account's supported subscription access outside the review. Then use the existing `chat-graph extract-outcomes --set-enabled 1 --json` operator command to clear the hold, and run one bounded authorized proof. Never switch models, introduce paid API credentials, or clear the hold on a timer. Revalidate this handling when the Claude JSON error-envelope schema or authentication route changes.

The extractor's assistant-only taxonomy cannot prove whether Trevor answered in a newer user message or another chat. The daily review and loose-ends skill must check the original question, later user replies, structured answer events, and linked/newer related chats before asking. Record exact answer provenance in the existing ledger; preserve unresolved agent follow-through. Missing access is unknown, not an unanswered question.

Daily 08:00 Pacific was explicitly confirmed in thread `01a15e1d-56ed-78d2-811d-19817731d768`. The existing heartbeat retains this cadence and performs the answer check. Its source review remains the fallback while external provider access is blocked.
