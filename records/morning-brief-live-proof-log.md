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
| 2026-07-12 | `20260712-f195b5aa73a7` | delivered; 2/2 chunks confirmed at 2026-07-12 05:00:02 PDT | latest.json match; generated 2026-07-12 05:00:02 PDT; sections 6; markdown_sha256 45352f5ac695d00f266d4d0682e8b45d1fbb121b8e910261248d06cc13f28a9a; first item: **Confirmed:** Commit and push this hardening branch Free more disk now (I can reclaim known rebuildable caches safely) Leave it — soak + Di |  |  |  |
<!-- /proof-table -->
