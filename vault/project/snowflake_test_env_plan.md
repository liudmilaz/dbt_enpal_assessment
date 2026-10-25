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

## 2. Target layout for Enpal

| Database | Role in the flow | Built by | Reads |
|---|---|---|---|
| `ENPAL_RAW.PIPEDRIVE` | the six CSVs, loaded once, never modified | `scripts/snowflake_load.sql` (admin) | - |
| `ENPAL_TEST` | **default target `test`**: zero-copy clones in `SRC` + `STAGING`, `INTERMEDIATE`, `MARTS`, `ELEMENTARY`; every change is deployed and tested here first | `dbt run-operation refresh_src`, then `dbt build` | `ENPAL_TEST.SRC` |
| `ENPAL_ANALYTICS_PROD` | target `prod`, only from `main`, only after the test run is green and after triple confirmation | `dbt build --target prod` | `ENPAL_RAW.PIPEDRIVE` |

There is no Postgres target: the repository sent to Enpal is Snowflake-only (agreed with Enpal, see [[NOTES]]).

`ENPAL_DB` (today's raw + Elementary + test_model) is dropped once the move is verified, with the owner's go.

## 3. Setup steps

1. **Admin SQL** (ACCOUNTADMIN, `scripts/snowflake_admin.sql`): databases `ENPAL_RAW`, `ENPAL_TEST`, `ENPAL_ANALYTICS_PROD`; service user `ENPAL_DBT_USER` with a new key pair `~/.ssh/snowflake_enpal_dbt_rsa_key.p8`, default role `ENPAL_DBT_ROLE`, no secondary roles; `ENPAL_DBT_ROLE` gets read-only on `ENPAL_RAW` (usage + select, future grants) and ownership of `ENPAL_TEST` and `ENPAL_ANALYTICS_PROD`; `ENPAL_WH` stays (XS, 60 s).
2. **Raw:** `scripts/snowflake_load.sql` loads into `ENPAL_RAW.PIPEDRIVE` (loader role, not the dbt role); row counts checked against Postgres.
3. **profiles.yml:** outputs `test` (default, `ENPAL_TEST`) and `prod` (`ENPAL_ANALYTICS_PROD`); same for the `elementary` profile. Account, user and key path from `~/.snowflake/enpal.env`.
4. **macros/refresh_src.sql:** clones the six tables `ENPAL_RAW.PIPEDRIVE.*` into `ENPAL_TEST.SRC` (same table names); `create or replace schema` first, so a refresh resets the test data; raises an error on `prod` and on Postgres.
5. **Sources:** database and schema by `target.name` (vars in dbt_project.yml): `test` -> `ENPAL_TEST.SRC`, `prod` -> `ENPAL_RAW.PIPEDRIVE`.
6. **macros/generate_schema_name.sql:** one schema per layer (`STAGING`, `INTERMEDIATE`, `MARTS`, `ELEMENTARY`), as in shine_test.
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
| STAGE_ENTRY | `int_pipedrive__deal_stage_entries` (recorded) and `_backfilled` (`is_inferred`) | intermediate |
| ACTIVITY (calls) | `int_pipedrive__sales_calls` (meeting, sc_2; done calls counted in the report) | intermediate |
| FUNNEL_STEP | `int_pipedrive__funnel_steps` + `dim_funnel_step` | intermediate, marts |
| FUNNEL_MONTH | `rep_sales_funnel_monthly` (contract: `month`, `kpi_name`, `funnel_step`, `deals_count`; month spine by `dbt_utils.date_spine`) | marts |

Cycle for every model, in DAG order: write -> `dbt build --select <model>+ --target test` -> `dbt show` profiling (row count, keys, nulls, min/max) -> YAML tests (Tier 1 PK/FK, then the findings) -> reconcile with the expected totals in [[model_plan]].

SQL is plain Snowflake: `lateral flatten` for the JSON unpack, `qualify` for the deduplication, `generator` for the month spine.

Before `rep_sales_funnel_monthly`: the open decisions in NOTES (step 1 date, done-only calls, two-lifecycle deals, report window, `kpi_name` format) need the owner's answer.

## 5. Open points for the owner

All four points of this section were answered on 2026-10-24; the answers are the decisions below. Reviewers at Enpal run the project on Snowflake with the default target `test`, as the repo README describes.

## Decisions on the plan (owner, 2026-10-24)

1. Claude writes the models, the owner reviews; notify at raw load (checkpoint 1) and at staging with tests (checkpoint 2). Default rule, written into the skills `dbt-snowflake-project-from-scratch` and `data-project-with-claude-code`.
2. The repo for Enpal contains no Postgres: the `dev` target, docker-compose.yml, init.sql and raw_data/load_data.sh are removed; default target `test`.
3. Admin SQL runs through the ACCOUNTADMIN admin connection.
4. `ENPAL_DB` (first Snowflake copy: raw, Elementary results, the task's test model) is redundant: **dropped on 2026-10-24** on the owner's go.

## As built (2026-10-24)

- `scripts/snowflake_admin.sql`: ENPAL_RAW (owner SYSADMIN, the loader), ENPAL_TEST and ENPAL_ANALYTICS_PROD (owner ENPAL_DBT_ROLE), ENPAL_WH; service user ENPAL_DBT_USER (`type = service`, key pair `~/.ssh/snowflake_enpal_dbt_rsa_key.p8`, no secondary roles); ENPAL_DBT_ROLE has usage + select (including future tables) on ENPAL_RAW.PIPEDRIVE.
- `scripts/snowflake_load.sql` as SYSADMIN: 4 / 4,579 / 15,406 / 4 / 9 / 1,787 rows (checkpoint 1).
- `macros/refresh_src.sql`: six table clones in ENPAL_TEST.SRC, 0 bytes of own storage; refuses `--target prod`.
- Sources read `var('raw_location')[target.name]`; the source is renamed `pipedrive` (was `postgres_public`) and its YAML moved to `models/sources/pipedrive/`, so the raw tests (tag `dq_raw`, warn) and staging tests (tag `dq_staging`, error) are configured per folder.
- Raw tests in test: 69, 51 pass and 18 warn at steady state, same counts as before.
- Staging (checkpoint 2): 6 views in ENPAL_TEST.STAGING, 37 tests, all pass. deal_changes 15,406 (0 removed; typed: 2,000 creations, 2,500 owners, 8,906 stages, 2,000 lost reasons); activity 4,568 (11 removed, A1); activity_types 4; stages 9; field_options 14; users 1,787.
- Still Postgres SQL: `analyses/` (to be converted to Snowflake) and `lightdash/` (points at Postgres).

## Layers built (2026-10-24)

- Intermediate: `int_pipedrive__deals` (1,995; flags D1 1,684, D2 683, D3 5), `int_pipedrive__deal_stage_entries` (8,891), `int_pipedrive__deal_stage_entries_backfilled` (1,995 / 1,990 / 1,951 / 1,862 / 1,693 / 1,424 / 1,081 / 723 / 324, equal to [[model_plan]]), `int_pipedrive__sales_calls` (1,142 Sales Call 1, 1,120 Sales Call 2).
- Marts: `dim_funnel_step` (11 steps, from `int_pipedrive__funnel_steps`), `rep_sales_funnel_monthly` (154 rows, 2024-01 to 2025-02, contract enforced).
- Open decisions run on the recommended defaults, `step_1_date: stage_entry` and the report window 2024-01 to 2025-02 as vars; done calls only, fixed in the model.
- Tests: unit test of the backfill, reconciliation of the report with the stage entries. Full `dbt build` on a fresh clone: 163 pass, 18 warn (known raw issues), 0 errors.
- `analyses/` (11 files, 89 statements) and the 47 Lightdash chart queries rewritten to Snowflake SQL and compared with the Postgres results: same numbers, only formatting differs.
