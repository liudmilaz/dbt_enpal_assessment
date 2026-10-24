---
tags:
  - project/enpal
  - type/plan
---

# Snowflake test environment (zero-copy clone) and model build plan

Status: **built on 2026-10-24** (decisions below; as-built notes at the end). The repo is Snowflake-only: no Postgres target. Pattern taken from github.com/liudmilaz/shine_test (`macros/refresh_src.sql`, `macros/generate_schema_name.sql`, `models/staging/_sources.yml`).

## 1. What shine_test does

- `SHINE_RAW.INTERCOM`: raw tables, loaded once, never modified; the dbt user can only read it.
- `SHINE_DEV`: default target. `dbt run-operation refresh_src` makes zero-copy **table** clones of the raw tables in `SHINE_DEV.SRC` (table by table, so the dbt role owns them; a schema clone keeps the original owner). dbt builds `STAGING`, `INTERMEDIATE`, `MARTS` there.
- `SHINE_ANALYTICS_PROD`: target `prod`, reads raw directly, built only from `main`; `refresh_src` refuses to run on prod.
- `generate_schema_name`: one schema per layer, the same name in every environment; the database tells the environments apart.
- Service user `SHINE_DBT_USER` (key pair, role `SHINE_DBT_ROLE`, no secondary roles).

## 2. Target layout for Enpal (account UE17459)

| Database | Role in the flow | Built by | Reads |
|---|---|---|---|
| `ENPAL_RAW.PIPEDRIVE` | the six CSVs, loaded once, never modified | `scripts/snowflake_load.sql` (admin) | - |
| `ENPAL_TEST` | **default target `test`**: zero-copy clones in `SRC` + `STAGING`, `INTERMEDIATE`, `MARTS`, `ELEMENTARY`; every change is deployed and tested here first | `dbt run-operation refresh_src`, then `dbt build` | `ENPAL_TEST.SRC` |
| `ENPAL_ANALYTICS_PROD` | target `prod`, only from `main`, only after the test run is green and after triple confirmation | `dbt build --target prod` | `ENPAL_RAW.PIPEDRIVE` |
| Postgres `public` | target `dev`: the task's deliverable, unchanged | `dbt build --target dev` | `postgres.public` |

`ENPAL_DB` (today's raw + Elementary + test_model) is dropped once the move is verified, with the owner's go.

## 3. Setup steps

1. **Admin SQL** (ACCOUNTADMIN, `scripts/snowflake_admin.sql`): databases `ENPAL_RAW`, `ENPAL_TEST`, `ENPAL_ANALYTICS_PROD`; service user `ENPAL_DBT_USER` with a new key pair `~/.ssh/snowflake_enpal_dbt_rsa_key.p8`, default role `ENPAL_DBT_ROLE`, no secondary roles; `ENPAL_DBT_ROLE` gets read-only on `ENPAL_RAW` (usage + select, future grants) and ownership of `ENPAL_TEST` and `ENPAL_ANALYTICS_PROD`; `ENPAL_WH` stays (XS, 60 s).
2. **Raw:** `scripts/snowflake_load.sql` loads into `ENPAL_RAW.PIPEDRIVE` (loader role, not the dbt role); row counts checked against Postgres.
3. **profiles.yml:** outputs `test` (default, `ENPAL_TEST`), `prod` (`ENPAL_ANALYTICS_PROD`), `dev` (Postgres); same for the `elementary` profile. Account, user and key path from `~/.snowflake/enpal.env`.
4. **macros/refresh_src.sql:** clones the six tables `ENPAL_RAW.PIPEDRIVE.*` into `ENPAL_TEST.SRC` (same table names); `create or replace schema` first, so a refresh resets the test data; raises an error on `prod` and on Postgres.
5. **Sources:** database and schema by `target.name` (vars in dbt_project.yml): `test` -> `ENPAL_TEST.SRC`, `prod` -> `ENPAL_RAW.PIPEDRIVE`, `dev` -> `postgres.public`. Column types stay by `target.type`.
6. **macros/generate_schema_name.sql:** on Snowflake one schema per layer (`STAGING`, `INTERMEDIATE`, `MARTS`, `ELEMENTARY`), as in shine_test; on Postgres everything in `public_pipedrive_analytics`, as the task's README expects.
7. **dbt_project.yml:** folder configs staging and intermediate = view, marts = table, layer schemas.
8. **scripts/dq_report.sh:** target `test` runs `refresh_src` first.
9. **Verification:** `refresh_src`; `dbt build --target test` gives 71 tests, 53 pass, 18 warn, the same counts as Postgres; `show tables in ENPAL_TEST.SRC` shows clones (`bytes` 0 until data diverges).

## 4. Model build plan (implements [[logical_model]], spec in [[model_plan]])

| Logical entity | Model | Layer |
|---|---|---|
| DEAL_EVENT | `stg_pipedrive__deal_changes` (typed per key, `deal_change_key`, dedup keeps first) | staging |
| ACTIVITY | `stg_pipedrive__activity` (dedup to latest `due_to` per `activity_id`) | staging |
| ACTIVITY_TYPE | `stg_pipedrive__activity_types` (`is_active` boolean) | staging |
| STAGE | `stg_pipedrive__stages` | staging |
| DEAL_FIELD, FIELD_OPTION, LOST_REASON | `stg_pipedrive__field_options` (JSON unpacked; adapter macro: `jsonb_to_recordset` / `lateral flatten`) | staging |
| USER | `stg_pipedrive__users` | staging |
| DEAL, OWNER_ASSIGNMENT | `int_pipedrive__deals` (created_at, first and last owner, `has_two_lifecycles`, flags D1 to D3) | intermediate |
| STAGE_ENTRY | `int_pipedrive__deal_stage_entries` (recorded) and `_backfilled` (`is_inferred`, var `funnel_backfill_skipped_stages`) | intermediate |
| ACTIVITY (calls) | `int_pipedrive__sales_calls` (meeting, sc_2; var `calls_done_only`) | intermediate |
| FUNNEL_STEP | seed `funnel_steps.csv` + `dim_funnel_step` | marts |
| FUNNEL_MONTH | `rep_sales_funnel_monthly` (contract: `month`, `kpi_name`, `funnel_step`, `deals_count`; month spine by `dbt_utils.date_spine`) | marts |

Cycle for every model, in DAG order: write -> `dbt build --select <model>+ --target test` -> `dbt show` profiling (row count, keys, nulls, min/max) -> YAML tests (Tier 1 PK/FK, then the findings) -> reconcile with the expected totals in [[model_plan]] -> same build on `--target dev` (Postgres) to keep both warehouses equal.

SQL portable through dbt cross-database macros (`dbt.date_trunc`, `dbt.safe_cast`, `dbt.dateadd`, `dbt_utils.date_spine`) and one adapter-dispatched macro for the JSON unpack.

Before `rep_sales_funnel_monthly`: the open decisions in NOTES (step 1 date, done-only calls, two-lifecycle deals, report window, `kpi_name` format) need the owner's answer.

## 5. Open points for the owner

1. Who writes the models: the standing rule says the owner writes them and Claude reviews and deploys to test.
2. Default target `test` in the committed profiles.yml: Enpal's reviewers run Postgres, so their README step becomes `dbt build --target dev`.
3. Admin SQL: run by Claude through the `ue17459` ACCOUNTADMIN connection, or by the owner in Snowsight (as for the INVENTED project).
4. Drop `ENPAL_DB` after the move.

## Decisions on the plan (owner, 2026-10-24)

1. Claude writes the models, the owner reviews; notify at raw load (checkpoint 1) and at staging with tests (checkpoint 2). Default rule, written into the skills `dbt-snowflake-project-from-scratch` and `data-project-with-claude-code`.
2. The repo for Enpal contains no Postgres: the `dev` target, docker-compose.yml, init.sql and raw_data/load_data.sh are removed; default target `test`.
3. Admin SQL runs through the `ue17459` ACCOUNTADMIN connection.
4. `ENPAL_DB` (first Snowflake copy: raw, Elementary results, the task's test model) is redundant; dropped only on the owner's go.

## As built (2026-10-24)

- `scripts/snowflake_admin.sql`: ENPAL_RAW (owner SYSADMIN, the loader), ENPAL_TEST and ENPAL_ANALYTICS_PROD (owner ENPAL_DBT_ROLE), ENPAL_WH; service user ENPAL_DBT_USER (`type = service`, key pair `~/.ssh/snowflake_enpal_dbt_rsa_key.p8`, no secondary roles); ENPAL_DBT_ROLE has usage + select (including future tables) on ENPAL_RAW.PIPEDRIVE.
- `scripts/snowflake_load.sql` as SYSADMIN: 4 / 4,579 / 15,406 / 4 / 9 / 1,787 rows (checkpoint 1).
- `macros/refresh_src.sql`: six table clones in ENPAL_TEST.SRC, 0 bytes of own storage; refuses `--target prod`.
- Sources read `var('raw_location')[target.name]`; the source is renamed `pipedrive` (was `postgres_public`) and its YAML moved to `models/sources/pipedrive/`, so the raw tests (tag `dq_raw`, warn) and staging tests (tag `dq_staging`, error) are configured per folder.
- Raw tests in test: 69, 51 pass and 18 warn at steady state, same counts as before.
- Staging (checkpoint 2): 6 views in ENPAL_TEST.STAGING, 37 tests, all pass. deal_changes 15,406 (0 removed; typed: 2,000 creations, 2,500 owners, 8,906 stages, 2,000 lost reasons); activity 4,568 (11 removed, A1); activity_types 4; stages 9; field_options 14; users 1,787.
- Still Postgres SQL: `analyses/` (to be converted to Snowflake) and `lightdash/` (points at Postgres).
