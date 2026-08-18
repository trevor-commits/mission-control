# Ops profile monitoring layer registration — 2026-08-18

## Goal

Register the new Hermes `ops` profile's monitoring layer in the Mission Control
automation registry so the dashboard shows the ops tick chain and the weekly
ops backup verification alongside the other background jobs.

- Owner: Hermes subagent (kimi-k3), delegated by Trevor's default-profile session.
- Execution checkout: `/Users/gillettes/Coding Projects/mission-control` on `main` at `19901c8`.
- Scope: `dashboard/jobs.json` only. No launchd, install, or live-state action.

## Background

A new Hermes profile `ops` (home `/Users/gillettes/.hermes/profiles/ops`) was
created to monitor and maintain the whole AI stack. Two of its jobs belong on
the Automation surface:

1. `com.gillettes.hermes-ops-tick` — the ops tick chain. The launchd plist
   exists at `~/Library/LaunchAgents/com.gillettes.hermes-ops-tick.plist`
   (StartInterval 60, RunAtLoad) but is deliberately not yet bootstrapped; a
   default-profile cron job `ops-tick-runner` runs the chain every minute in
   the meantime. The liveness proof of the whole chain is the canary stamp at
   `/Users/gillettes/.hermes/profiles/ops/ops-data/canary/stamp` (epoch
   seconds, refreshed every 15 minutes by an ops cron job).
2. `com.gillettes.hermes-ops-backup-verify` — weekly Sunday 7:00 AM job
   (`/Users/gillettes/.hermes/profiles/ops/scripts/ops-backup-verify.sh`,
   cron-driven, no launchd plist) that snapshots the default and ops profiles
   via `hermes backup -q -l weekly-ops` and flags any newest snapshot older
   than 8 days. Snapshot roots: `/Users/gillettes/.hermes/state-snapshots` and
   `/Users/gillettes/.hermes/profiles/ops/state-snapshots`.

## What was added

Two entries in `dashboard/jobs.json`, schema-matched to existing entries:

- Hermes Ops Tick: `kind: interval`, `expected_freshness_s: 1800`, evidence
  canary stamp with `role: run` + `run_key: true`, `err_log` from the plist's
  StandardErrorPath, and `activation_required: true` copied from the
  Morning Brief / Outcome Extractor pattern for plists that exist but are not
  yet loaded. Live classification: `awaiting-activation` (honest while the
  bootstrap is pending; flips to normal green/yellow/red classification once
  Trevor bootstraps the agent).
- Hermes Ops Backup Verify: `kind: calendar`, `expected_freshness_s: 691200`
  (8 days, matching the script's own budget), `pseudo: true` copied from the
  `chat-graph-ingest` pattern because this job is cron-driven and has no
  launchd label, so evidence freshness is the only truthful classifier. Live
  classification: `green` on today's `-weekly-ops` snapshots.

Evidence-path adaptation: the requested evidence roots are directories of
snapshot subdirectories, but `scripts/automation-status` only stats regular
files (`os.path.isfile`), so directory mtimes can never register. Each root is
registered as `<root>/*/manifest.json` — every snapshot directory contains a
`manifest.json` written at backup completion, so the newest glob match carries
exactly the "newest entry mtime" semantics the job contract asks for. Both
paths keep `role: run` and `run_key: true`.

## Verification

- `python3 -c json.load` on the edited registry: parses, 16 jobs.
- Live `scripts/automation-status --json --registry dashboard/jobs.json`:
  tick = `awaiting-activation`, backup-verify = `green`
  (`evidence_age_s` ≈ 1380 at check time).
- `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/automation-status.test.sh`:
  ALL PASS (focused release gate for registry changes).
- Full `PYTHONDONTWRITEBYTECODE=1 /bin/bash scripts/verify.sh`: result recorded
  in `todo.md` Test Evidence Log.

## Did not verify

- No `launchctl bootstrap` of `com.gillettes.hermes-ops-tick` — activation is
  Trevor's to perform; the entry honestly reports `awaiting-activation` until
  then.
- The next natural Sunday 7:00 AM backup-verify run (today's snapshots were
  observed as evidence, not produced by this change).
- No commit or push: explicitly out of scope for this task; the change sits in
  the working tree on `main`.

linear: repo-only; no Mission Control Linear team is configured.
