# ER-141 answer-dispatch slice 1 pinned audit follow-up

## Audited Chat

- Audited chat name: `worker:Answer dispatch slice 1 - pinned audit`
- Audited chat repo/cwd: `/Users/gillettes/Coding Projects/mission-control-worktrees/answer-dispatch-slice1`
- Provider: Codex
- Full ID: `019f5d61-1e7e-7713-91a7-2e50c857175c`
- Transcript: `/Users/gillettes/.codex/sessions/2026/07/13/rollout-2026-07-13T14-27-53-019f5d61-1e7e-7713-91a7-2e50c857175c.jsonl`

## Scope and boundary

This was a separate, read-only, pinned `gpt-5.5`/high review after the completed HOTL run. The first pass reviewed committed branch head `d8781309fdb575a2627301c69c5e6a673a784c7d` against `main@f355b5ef8882a12945df35b253378a062b8a28ce`. The follow-up reviewed only the correction diff in `scripts/dashboard`, `scripts/dispatch-runner`, and `scripts/dispatch-runner.test.sh`. It did not rerun or mutate `.hotl/state/answer-dispatch-slice1-20260713T164247Z.json` or the completed HOTL report.

## Findings and dispositions

| Finding | Decision | Evidence and disposition |
|---|---|---|
| Receipt feed state disappeared after a real decision became resolved | Accepted | A kept synthetic run proved the answered decision left `data.pinned` while its receipt existed. The collector now emits bounded top-level `data.dispatch` receipt summaries and retains the per-pinned-row field for open decisions. A real answer, stub drain, forced decisions collect, and resolved-state assertion now cover the path. |
| Prompt/receipt writes could be redirected by a directory swap after path validation | Accepted | A malicious lint hook moved `receipts` and replaced the public path with a symlink; before the fix the receipt landed outside the dispatch subtree. The runner now opens private directories with `O_DIRECTORY|O_NOFOLLOW` and performs staged writes, replacement, receipt lookup, queue reads, and queue removal relative to pinned directory descriptors. The regression proves the receipt lands in the originally validated directory and the outside target stays empty. |
| The original feed regression manually seeded a receipt on an open decision | Accepted, subsumed | Replaced as merge evidence by the real post-answer/post-drain regression above. The open-decision attachment case remains as compatibility coverage. |
| Template files remain Claude-owned TODO skeletons | Rejected as a slice-1 defect | The authoritative packet explicitly requires skeletons, correct placeholders, and no Codex-authored prompt prose when final templates are absent. Final wording remains a later Claude-owned gate. |

## Red and green evidence

- Before correction, the new regressions failed with `KeyError: 'dispatch'`, `FAIL: resolved decision receipt remains in decisions feed`, and `FAIL: receipt write stays in validated dispatch directory` (`PASS=17 FAIL=2`).
- After correction, `bash scripts/dispatch-runner.test.sh` passed `PASS=19 FAIL=0`.
- `REPO_ROOT="$PWD" bash scripts/dashboard.test.sh --require-shell` passed `PASS=67 FAIL=0`.
- `bash scripts/decision-alert.test.sh` passed `ALL PASS`.
- Bash syntax, Python compilation, and `git diff --check` passed.

## Follow-up verdict

`READY / review-clean`. The pinned reviewer confirmed both accepted blockers are closed, receipt idempotence and malformed-queue isolation remain intact, feed fields are bounded, and `dashboard/index.html` is untouched.

## Ripple Check

The correction changes only dispatch receipt surfacing and filesystem write safety. It adds the collector-owned `data.dispatch` field but does not change renderer code, delivery sequencing, real-send behavior, queue schema, templates, installed runtime, launchd configuration, dependencies, or external integrations. Therefore the design document's delivery-sequencing section did not need a slice-order update.

## Self-audit

Verified: the two counterexamples, red-before-green regressions, focused runner suite, requested existing suites, syntax/compile/whitespace gates, exact pinned-review provenance, current branch/base, and unchanged completed HOTL artifacts.

Not verified: real spawn/mailbox/platform sends, installed `~/.mission-control/bin` behavior, scheduling, rendered receipt UI, final Claude template wording, live provider quota switching, or hostile manual corruption of already-written receipt files. These remain outside slice 1. The reviewer noted that an unreadable receipt scan yields no dispatch rows for that tick and that future UI must treat `prompt_path` as display-only; neither is a blocker for this stub-only correction.

Provenance: executor=codex:gpt-5.6-sol:high; audit=L3; scripts=dispatch-runner.test.sh,dashboard.test.sh,decision-alert.test.sh; escalations=0; routing=strong; notes=pinned gpt-5.5 read-only reviewer
