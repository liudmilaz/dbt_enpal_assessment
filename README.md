# Enpal take-home: Pipedrive sales funnel in dbt on Snowflake

The assignment ships a local Postgres in Docker. Enpal agreed that this solution may run on my own **Snowflake trial account** instead, so the setup section below describes Snowflake and the repository contains no Postgres. Everything the task asks for is unchanged: the same six Pipedrive tables, the same layers, the same reporting model. The role also asks for Snowflake semantic views, and keeping one platform makes the project simpler to read. AI tools (Claude Code) were used as support, as agreed.

## Result

`MARTS.rep_sales_funnel_monthly(month, kpi_name, funnel_step, deals_count)`: one row per month and funnel step, 2024-01 to 2025-02, zero-filled (154 rows). Contract enforced.

| Step | Counted as | Total deals in the window |
|---|---|---|
| 1 to 9 (stages) | distinct deals whose **first entry** into the stage falls in the month; a skipped stage counts as reached (`is_inferred`) and is dated at the next recorded stage | 1,995 / 1,990 / 1,951 / 1,862 / 1,693 / 1,424 / 1,081 / 723 / 324 |
| 2.1 Sales Call 1, 3.1 Sales Call 2 | distinct deal ids with a **done** call of that type due in the month | 566 / 558 |

## Data flow

```
ENPAL_RAW.PIPEDRIVE        6 CSVs, loaded once (scripts/snowflake_load.sql); dbt can only read it
  -> ENPAL_TEST.SRC        zero-copy clones (dbt run-operation refresh_src) - default target `test`
  -> STAGING               stg_pipedrive__*  one view per raw table: rename, cast, deduplicate
  -> INTERMEDIATE          int_pipedrive__deals, __deal_stage_entries(_backfilled), __sales_calls
  -> MARTS                 dim_funnel_step, rep_sales_funnel_monthly, fct_deals
ENPAL_ANALYTICS_PROD       same layers, target `prod`, built from main only, reads ENPAL_RAW directly
```

## Setup (Snowflake)

1. **Account objects** (once, as ACCOUNTADMIN): `scripts/snowflake_admin.sql` creates the warehouse `ENPAL_WH` (X-Small, suspends after 60 s), the databases `ENPAL_RAW`, `ENPAL_TEST`, `ENPAL_ANALYTICS_PROD`, the role `ENPAL_DBT_ROLE` (read-only on raw) and the service user `ENPAL_DBT_USER` (key pair, no secondary roles). The header of the script shows the `snow sql` call.
2. **Raw data** (as SYSADMIN): `snow sql -c <admin connection> -f scripts/snowflake_load.sql` loads `raw_data/*.csv` into `ENPAL_RAW.PIPEDRIVE`. It replaces the tables, so a rerun never appends twice.
3. **Credentials**: copy `scripts/snowflake_env.example` to `~/.snowflake/enpal.env`, fill in account and key path, `source` it. `profiles.yml` reads them from the environment; nothing secret is in the repo.
4. **dbt** (venv outside the repo): `pip install -r requirements.txt`, then
   ```bash
   export DBT_PROFILES_DIR=.
   dbt deps
   dbt run-operation refresh_src   # fresh zero-copy clones in ENPAL_TEST.SRC
   dbt build                       # target test: seed, models and all tests
   ```
   Production: `dbt build --target prod` (from `main` only).
5. **Data quality report** (optional): `pip install -r requirements-elementary.txt` in a separate venv, then `bash scripts/dq_report.sh` serves the Elementary report on http://localhost:8081.

## Decisions and assumptions

| Topic | Choice | Why / effect |
|---|---|---|
| Skipped stages (84% of deals) | counted as reached, flagged `is_inferred`; for recorded entries only use `int_pipedrive__deal_stage_entries` | a deal in Negotiation has passed Qualified Lead; recorded-only would roughly halve the middle steps |
| Step 1 date | first entry into stage 1 (`step_1_date: created` uses the creation time) | same rule as every other step; creation is a median 35 days earlier |
| Calls 2.1 / 3.1 | done calls only | a held call is the KPI; about 50% of every type is done |
| Calls vs deals | calls counted per month by their own `deal_id` | only 8 of 4,579 activities link to a deal in the history, so they cannot be attached to the funnel deals |
| Two lifecycles in one deal (5 deals) | counted once per step, by the first entry | |
| Repeated `activity_id` (11 ids) | `activity_id` is the key; the latest `due_to` per id is kept (4,579 to 4,568) | |
| Report window | 2024-01 to 2025-02 (`report_start_month`, `report_end_month`) | months with stage events; calls and new deals stop on 2024-09-13 (the exports end on different dates) |
| Names | `kpi_name` = the task's step name, `funnel_step` = step number as text (`'2.1'`) | the CRM spells one stage differently |

The open questions for the business (KPI owner, CRM admin) and the evidence behind every finding are in `vault/` (documentation PR) and `analyses/` (one exploratory file per raw table, with results under each query).

## Tests

- **Raw layer** (`models/sources/pipedrive/`, `tests/data_quality/`): every primary and foreign key, the domains, and the known issues of the export as warn-level tests named by issue id (for example `a1_repeated_activity_id`, `d1_deals_with_skipped_stages`), plus Elementary volume, freshness, dimension and schema monitors.
- **Staging, intermediate, marts**: keys, relationships, accepted values at error; a unit test of the backfill rule; a reconciliation of the report against the stage entries.
- `dbt build` on a fresh clone: 166 pass, 19 warn (the known issues of the export), 0 errors.

## Repository

| Path | Content |
|---|---|
| `models/sources/pipedrive/` | sources with descriptions, keys in `meta`, raw-layer tests and monitors |
| `models/staging`, `models/intermediate`, `models/marts`, `seeds/` | the models |
| `macros/` | `refresh_src` (test clones), `generate_schema_name` (one schema per layer) |
| `tests/` | singular tests: raw data quality, report reconciliation |
| `analyses/` | exploratory analysis per raw table, Snowflake SQL with results |
| `scripts/` | Snowflake admin and load scripts, data quality report |
| `lightdash/` | scripts for an exploratory Lightdash dashboard (optional) |

---

## The task (as given)

1. Remove the test model once you make sure it works
2. Dive deep into the Pipedrive CRM source data to gain a thorough understanding of all its details. (You may also research the Pipedrive CRM tool terms).
3. Define DBT sources and build the necessary layers organizing the data flow for optimal relevance and maintainability.
4. Build a reporting model (rep_sales_funnel_monthly) with monthly intervals, incorporating the following funnel steps (KPIs):  
  &nbsp;&nbsp;&nbsp;Step 1: Lead Generation  
  &nbsp;&nbsp;&nbsp;Step 2: Qualified Lead  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 2.1: Sales Call 1  
  &nbsp;&nbsp;&nbsp;Step 3: Needs Assessment  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 3.1: Sales Call 2  
  &nbsp;&nbsp;&nbsp;Step 4: Proposal/Quote Preparation  
  &nbsp;&nbsp;&nbsp;Step 5: Negotiation  
  &nbsp;&nbsp;&nbsp;Step 6: Closing  
  &nbsp;&nbsp;&nbsp;Step 7: Implementation/Onboarding  
  &nbsp;&nbsp;&nbsp;Step 8: Follow-up/Customer Success  
  &nbsp;&nbsp;&nbsp;Step 9: Renewal/Expansion
5. Column names of the reporting model: `month`, `kpi_name`, `funnel_step`, `deals_count`
6. “Git commit” all the changes and create a PR to your forked repo (not the original one). Send your repo link to us.

The setup steps of the original task (Docker, local Postgres with admin/admin, `dbt-postgres`) are replaced by the Snowflake setup above, with Enpal's agreement. The project steps are unchanged.
