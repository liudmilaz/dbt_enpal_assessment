---
tags:
  - project/enpal
  - domain/data-architecture
  - domain/dbt
  - type/reference
---

# Low-cost stack for raw Excel/CSV sheets (startup)

Local Postgres on one laptop works for one person, not a team: no backups, no shared access, single point of failure. The idea (Postgres for a few GB of sheets) is fine; the hosting is the problem.

## Shape
```
Excel/CSV → bucket (raw, never edited) → load script → raw tables
                                           └→ dbt: staging → marts (tests, docs) → BI
```
1. **Landing zone:** dated folders, e.g. `raw/sales/2026-10-22_pipeline.xlsx`; raw files are never edited.
2. **Load script:** Python reads files into `raw` tables with `_source_file`, `_loaded_at`, row hash; raw columns stay text, typing happens in dbt staging.
3. **dbt:** staging cleans/casts, marts model the business, tests catch broken files.
4. **Git + scheduler:** GitHub Action on cron runs load + `dbt build`.
5. **Access:** one shared database, roles: analysts read marts, not raw.

## Cheap hosting

| Option | Rough cost | Watch out |
|---|---|---|
| BigQuery sandbox / on-demand | free: 10 GB storage, 1 TB queries/month | cost cap; sandbox tables expire in 60 days without billing |
| Managed Postgres (Neon, Supabase, Cloud SQL, RDS small) | free to ~10–30 €/month | free tiers pause/limit |
| DuckDB + Parquet in a bucket | cents | not a shared multi-user DB (MotherDuck adds that) |
| Postgres in Docker on a small VM | ~5–10 €/month | you own backups, updates, security |
| Snowflake | trial then per-second | needs resource monitors, auto-suspend |
| Google Sheets as source | free | connect as BigQuery external table |

Recommendation for Liudmila: BigQuery free tier + dbt + GitHub Actions + Looker Studio/Lightdash.

## Spreadsheet pitfalls
- Schema drift → source tests on expected columns.
- Silent type errors (dates as numbers, merged cells) → raw as text, cast in staging.
- Several versions of truth → decide replace vs append per sheet; keep `_loaded_at`.
- No owner → write down who produces each sheet and how often.

Move to Snowflake when sources, users and data (hundreds of GB) justify a budget; dbt models port with small changes.
