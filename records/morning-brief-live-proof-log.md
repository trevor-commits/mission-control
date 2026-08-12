# Morning Brief Live Proof Log

Purpose: track the five-morning proof window for the live Morning Brief without
turning Trevor's comprehension check into an inferred machine claim.

Usage:

```bash
scripts/harvest-morning-brief-proof
scripts/harvest-morning-brief-proof --brief-id 20260711-b8346ab99288
```

The harvester reads delivery receipts from
`~/.mission-control/morning-brief/delivery/*.json`, adds latest brief metadata
when `latest.json` still matches that `brief_id`, and updates rows idempotently
by `brief_id`.

Per-morning template:
- Confirm delivery receipt exists and shows every chunk confirmed.
- Confirm the corresponding latest brief metadata when retained locally.
- Leave `Trevor read?`, `Trevor understood?`, and `Trevor notes` blank until
  Trevor supplies that comprehension evidence.
- Do not send Telegram, activate Outcome Extractor, or unload Screenpipe while
  maintaining this proof log.

<!-- proof-table -->
| Morning | Brief ID | Delivery proof | Latest brief metadata | Trevor read? | Trevor understood? | Trevor notes |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-07-10 | `20260710-e0b7a9ca4b16` | delivered; 2/2 chunks confirmed at 2026-07-10 21:03:16 PDT | not latest retained sidecar |  |  |  |
| 2026-07-11 | `20260711-b8346ab99288` | delivered; 2/2 chunks confirmed at 2026-07-11 06:53:36 PDT | not latest retained sidecar |  |  |  |
| 2026-07-12 | `20260712-f195b5aa73a7` | delivered; 2/2 chunks confirmed at 2026-07-12 05:00:02 PDT | not latest retained sidecar |  |  |  |
| 2026-07-13 | `20260713-8e275cff700b` | delivered; 2/2 chunks confirmed at 2026-07-13 05:00:06 PDT | not latest retained sidecar |  |  |  |
| 2026-07-14 | `20260714-3dbdd031b218` | delivered; 2/2 chunks confirmed at 2026-07-14 05:00:01 PDT | not latest retained sidecar |  |  |  |
| 2026-07-15 | `20260715-b51a866784b7` | delivered; 3/3 chunks confirmed at 2026-07-15 05:00:04 PDT | not latest retained sidecar |  |  |  |
| 2026-07-16 | `20260716-67d9deb36761` | delivered; 2/2 chunks confirmed at 2026-07-16 05:00:05 PDT | not latest retained sidecar |  |  |  |
| 2026-07-17 | `20260717-9195b90ee312` | delivered; 2/2 chunks confirmed at 2026-07-17 05:00:05 PDT | not latest retained sidecar |  |  |  |
| 2026-07-18 | `20260718-60282505b6c2` | delivered; 3/3 chunks confirmed at 2026-07-18 05:00:03 PDT | not latest retained sidecar |  |  |  |
| 2026-07-19 | `20260719-316a0fa19dbd` | delivered; 3/3 chunks confirmed at 2026-07-19 05:00:02 PDT | not latest retained sidecar |  |  |  |
| 2026-07-20 | `20260720-c0c1e652e935` | delivered; 3/3 chunks confirmed at 2026-07-20 05:00:01 PDT | not latest retained sidecar |  |  |  |
| 2026-07-21 | `20260721-ebeca300e429` | delivered; 2/2 chunks confirmed at 2026-07-21 05:00:01 PDT | not latest retained sidecar |  |  |  |
| 2026-07-22 | `20260722-225bc406ce74` | delivered; 3/3 chunks confirmed at 2026-07-22 05:00:05 PDT | not latest retained sidecar |  |  |  |
| 2026-07-23 | `20260723-fed704e36e15` | delivered; 8/8 chunks confirmed at 2026-07-23 05:00:01 PDT | not latest retained sidecar |  |  |  |
| 2026-07-24 | `20260724-80f46473809c` | delivered; 2/2 chunks confirmed at 2026-07-24 05:00:06 PDT | latest.json match; generated 2026-07-24 05:00:06 PDT; sections 6; markdown_sha256 663a13cf8f3506f0fd3bcee5ba95c4b864678be6a960763d2c3aba96447fa076 |  |  |  |
<!-- /proof-table -->
