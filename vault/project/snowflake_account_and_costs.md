---
tags:
  - project/enpal
  - type/setup
---

# Snowflake account: what each database, role and warehouse is for, and what it costs

Own trial account (AWS, Frankfurt), as seen in Snowsight's database, role and warehouse pickers on 2026-10-24. Layout and decisions: [[snowflake_test_env_plan]].

## Databases

| Database | For | Created by | Cost |
|---|---|---|---|
| `ENPAL_RAW` | The six Pipedrive CSVs as delivered, schema `PIPEDRIVE` (`PUBLIC` is the empty default schema every database gets). Loaded once by SYSADMIN; dbt can only read it | `scripts/snowflake_admin.sql`, `scripts/snowflake_load.sql` | Storage of about 0.3 MB |
| `ENPAL_TEST` | dbt's **default target**. `SRC` holds zero-copy clones of the raw tables (`dbt run-operation refresh_src`); `STAGING`, `INTERMEDIATE`, `MARTS`, `ELEMENTARY` hold what dbt builds. Every change is built and tested here first | admin script; dbt | Clones: 0 bytes until a cloned table changes. Views: no storage. Mart tables and Elementary: a few hundred KB |
| `ENPAL_ANALYTICS_PROD` | dbt target `prod`: the same layers, built from `main` only, after the test build is green and after confirmation. Reads `ENPAL_RAW` directly. Empty so far | admin script | 0 until built |
| `ENPAL_DB` | The first Snowflake copy (raw, Elementary results, the task's test model). **Dropped on 2026-10-24**; restorable with `undrop` for 1 day (time travel), then 7 days of fail-safe | first transfer | Fail-safe keeps its bytes for 7 days (KB) |
| `PC_DBT_DB` | dbt Cloud Partner Connect database of the jaffle_shop learning project | Partner Connect | Separate project |
| `RAW` | Raw data of the jaffle_shop learning project (`JAFFLE_SHOP`, `STRIPE`) | jaffle_shop setup | Separate project |
| `SNOWFLAKE` | Snowflake's own shared database: `ACCOUNT_USAGE` (query, metering and storage history), used for the numbers below | Snowflake | Not billed |
| `SNOWFLAKE_SAMPLE_DATA` | Snowflake's shared sample data (TPC-H and others) | Snowflake | Not billed (a share) |
| `SNOWFLAKE_LEARNING_DB` | Trial tutorial objects | Snowflake trial | Tiny |
| `USER$zolotukmila` | Personal database of the Snowsight user (workspaces, notebooks) | Snowflake | Tiny |

Why other projects' databases appear while `ENPAL_DBT_ROLE` is selected: Snowsight runs with **secondary roles ALL**, so the user sees everything any of their roles can see. The dbt service user `ENPAL_DBT_USER` has no secondary roles and sees only `ENPAL_RAW`, `ENPAL_TEST` and `ENPAL_ANALYTICS_PROD`.

## Roles and warehouses

- `ENPAL_DBT_ROLE`: read-only on `ENPAL_RAW`, owner of `ENPAL_TEST` and `ENPAL_ANALYTICS_PROD`; granted to the dbt service user, to the Snowsight user and to SYSADMIN (so admins keep control).
- System roles: `ACCOUNTADMIN` (top), `SYSADMIN` (objects; the loader of `ENPAL_RAW`), `SECURITYADMIN` and `USERADMIN` (grants, users), `ORGADMIN` (organisation), `PUBLIC` (everyone).
- Other projects: `PC_DBT_ROLE` (jaffle_shop), `SNOWFLAKE_LEARNING_ROLE` (trial tutorial).
- Warehouses, all X-Small: `ENPAL_WH` (loading and dbt for Enpal, suspends after 60 s), `INVENTED_WH` and `PC_DBT_WH` (other projects), `SNOWFLAKE_LEARNING_WH` (tutorial), `SYSTEM$STREAMLIT_NOTEBOOK_WH` (Snowflake's notebooks).

## How the costs arise

Snowflake bills three things separately:

1. **Compute (warehouses)**: credits per second while a warehouse runs, at least 60 seconds per resume. X-Small = 1 credit per hour. A suspended warehouse costs nothing; `auto_suspend = 60` stops it a minute after the last query. Measured since 2026-10-18: `ENPAL_WH` 0.32 credits, all warehouses together 0.78 credits. A full `dbt build` of this project runs about one to two minutes on X-Small (about 0.02 to 0.03 credits).
2. **Storage**: the average compressed bytes per month, per TB (database tables, plus time travel and fail-safe of changed or dropped data). Here: well under 1 MB, so practically 0. Shared databases (`SNOWFLAKE`, `SNOWFLAKE_SAMPLE_DATA`) are not billed to the account.
3. **Cloud services and AI features**: metadata work (cloning, `show`, compilation) is free up to 10% of the daily compute; Snowsight's AI features bill on their own (since 2026-10-18: Snowflake Cowork 0.14 and Cortex agents 0.11 credits, not part of the Enpal project).

The price of a credit depends on the edition and the region (roughly US$2 to 4); the trial comes with free credits. Check Admin, Cost management in Snowsight.

## How the design keeps the costs low

- **Zero-copy clones** for the test environment: a refresh is a metadata operation (no compute for copying, no storage until data changes), instead of a second full copy of raw.
- **Views** for staging and intermediate (no storage; computed when read), **tables** only for the marts that consumers read.
- One X-Small warehouse with a 60-second auto-suspend for loading, dbt and the Elementary report.
- Raw loaded once; `create or replace` in the load script, so a rerun replaces instead of appending (no duplicated storage).
- Production is built only from `main`, so experiments run in `ENPAL_TEST` on clones and never duplicate prod data.

## Query the numbers again

```sql
select warehouse_name, round(sum(credits_used), 3) as credits
from snowflake.account_usage.warehouse_metering_history
where start_time >= '2026-10-18'
group by 1 order by 2 desc;

select service_type, round(sum(credits_used), 3) as credits
from snowflake.account_usage.metering_daily_history
where usage_date >= '2026-10-18'
group by 1 order by 2 desc;
```

`ACCOUNT_USAGE` lags by up to a few hours; the Enpal databases appear in `database_storage_usage_history` the day after they were created.
