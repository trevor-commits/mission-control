# Corrective receipt — full verifier source-artifact false green

## Observed evidence

The fresh Lane D candidate run at `754de932301113e81f51bbf4febe2d3fc28c01e0` reached `SUITES PASS=22 FAIL=0`, but the immediate post-run check found `scripts/__pycache__/mission_control_common.cpython-314.pyc`. The declared dashboard artifact assertion had executed before the producing Morning Brief sender subprocesses, so the overall green result did not prove final tree cleanliness.

## Root cause and reusable failure class

`scripts/morning-brief-deadman-sender.test.py` rebuilt subprocess environments with `clear=True`/explicit `env=` and omitted the verifier's inherited `PYTHONDONTWRITEBYTECODE=1`. Those Homebrew Python subprocesses loaded `mission_control_common` from the repository via `PYTHONPATH` and wrote ignored bytecode. The reusable failure class is **cleanliness checked before the last mutator plus child environments that silently discard parent safeguards**.

## What would have caught it earlier

A final, verifier-owned artifact assertion after every suite would have rejected the run. A real-subprocess regression around each deliberately rebuilt Python environment would have exposed the lost safeguard before the full matrix.

## Smallest durable prevention

- Preserve `PYTHONDONTWRITEBYTECODE=1` in the isolated sender-test environment.
- Exercise that environment against a copied temporary runtime and assert it creates no `__pycache__`.
- Run one final source-artifact suite after all other authoritative suites.

## Canonical landing surface

- `scripts/morning-brief-deadman-sender.test.py`
- `scripts/verify.sh`
- Test receipt: `records/evidence/rollup-answer-verifier-artifact-red-green.txt`

## Verification and disposition

- RED reproduced the temporary runtime `__pycache__` creation.
- GREEN passed the exact regression, the enclosing shell/15-test sender matrix, verifier self-test, Lane D rollup suite, Bash 3.2 syntax, strict OpenSpec, diff check, and final source-artifact predicates.
- Disposition: **accepted and repaired** on `codex/rollup-answer-wiring`; no new dependency or runtime behavior was added.
- Did not verify: the post-repair authoritative full matrix, independent audit, or PR state at this receipt checkpoint.
- by: Codex `019f73d8-e5dc-73a0-acc5-8a4916ac6819`.
- linear: repo-only; no Mission Control Linear team is configured.
