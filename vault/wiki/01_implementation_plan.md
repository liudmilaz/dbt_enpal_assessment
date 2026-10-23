---
tags:
  - project/enpal
  - domain/dbt
  - type/plan
---

# Implementation plan

Task (from the assignment): remove the test model; explore the Pipedrive data; define dbt sources and layers; build `rep_sales_funnel_monthly(month, kpi_name, funnel_step, deals_count)` for steps 1–9 plus 2.1 and 3.1; commit and open a PR **on my fork only**; send the repo link and a zip.

## Status

- [x] Fork + clone
- [x] `docker compose up -d`, CSVs loaded **once** (the double load is fixed: activity 4,579 / deal_changes 15,406 / users 1,787 / stages 9 / fields 4 / activity_types 4)
- [x] venv with dbt-core 1.10 + dbt-postgres 1.9, `dbt run` on the test model works
- [x] EDA skills created (branch `skills/eda`, local commit, not pushed) and installed in the project's `.claude/skills/`: [[eda_skills]]
- [ ] Everything below

## Steps

1. **Housekeeping:** `.gitignore` (`target/`, `logs/`, `dbt_packages/`, `.venv/`), delete committed `target/`, remove `test_model.sql`, `requirements.txt`, pin the Postgres image tag, MIT licence.
2. **Exploratory analysis, driven by the EDA skills** (`eda-source-profiling`, `eda-event-log-and-funnel-checks`): SQL in `analyses/`, each file starting with Question / Finding / Consequence; findings in `docs/exploratory_analysis.md` (see [[02_data_findings]], [[eda_skills]]).
3. **Sources:** `models/staging/pipedrive/_pipedrive__sources.yml` declares the six tables (plus freshness/recency comments). **The data-quality tests live in the staging YAML** (`_stg_pipedrive__models.yml`), following `eda-dbt-test-probes`: double-load check, keys, accepted values, relationships (see [[dbt_source_tests_and_loader_gotcha]]).
4. **Layers** (layout skill: one concern per layer):

   | Layer | Models | Grain |
   |---|---|---|
   | staging (view) | `stg_pipedrive__deal_changes`, `__activity` (deduped), `__activity_types`, `__stages`, `__users`, `__fields` | 1 row per source row |
   | intermediate (view) | `int_pipedrive__deals`, `int_pipedrive__deal_stage_entries` (first entry per deal × stage via `min(change_time)`) | deal; deal × stage |
   | marts (table) | `dim_funnel_step` (seed, 11 rows), `fct_deal_stage_entries`, `fct_sales_calls`, `rep_sales_funnel_monthly` | see YAML |

5. **Report definition:**
   - `deals_count` = distinct deals **first entering** the stage in that month (event cohort, not cumulative).
   - Steps 2.1 / 3.1 = distinct deals with a `done = true` activity of type `meeting` / `sc_2`, by `due_to` month (activities cannot be joined to deals, see findings).
   - Month spine bounded to the observed range; empty months = 0.
   - Contract enforced on the report.
6. **Tests** (in staging for raw-table properties, per the four classes: field, record, referential, business logic): key `unique`/`not_null`, `accepted_values`, `relationships`; singular reconciliations (step 1 total = 1,995 distinct deals; monthly sums = fact); one unit test on the dedupe.
7. **Efficiency:** `min() group by` instead of self-joins, early filters, indexes via post-hook, `EXPLAIN ANALYZE` evidence in the README. No incremental models (about 15k rows).
8. **Docs:** README (setup, assumptions, findings, open questions for Enpal), Mermaid lineage, `dbt docs generate`.
9. **CI:** GitHub Action with a Postgres service container running `dbt build`.
10. **Git:** commit as `zolotukmila@datacanonic.com`; `gh pr create -R liudmilaz/dbt_enpal_assessment`; zip for the email.
11. **Optional (branch `snowflake-extension`):** second dbt target on a Snowflake trial via `snow sql` + key-pair auth, `sv_sales_funnel` semantic view, Cortex Analyst question. Postgres stays the deliverable.

## Open decisions

1. **Skipped stages:** 84% of deals skip at least one stage. Count recorded entries only, or backfill skipped stages with an `is_inferred` flag? Recommendation: backfill, with a variable for recorded-only and a documented reconciliation.
2. **Step 1:** stage-1 entry (consistent with the other steps) vs `add_time` (median 35 days earlier). Recommendation: stage-1 entry; README mentions the alternative.
3. **Report window:** 2024-01 to 2025-02 (months with funnel events); calls are 0 from 2024-10.
4. **Calls:** `done = true` only (recommended) vs all scheduled.
5. **Snowflake branch:** in or out of scope.

## Integrity note

The original repo has about 42 PRs from other candidates. Used only to sanity-check data findings. Nothing copied.
