-- One-time admin setup of the Snowflake account.
--   ENPAL_RAW.PIPEDRIVE       the six CSVs, loaded once by SYSADMIN (scripts/snowflake_load.sql); dbt can only read it
--   ENPAL_TEST                dbt target test (default): zero-copy clones in SRC (macros/refresh_src.sql) + layer schemas
--   ENPAL_ANALYTICS_PROD      dbt target prod: built from main only, reads ENPAL_RAW directly
-- Run as ACCOUNTADMIN from the repo root, with the dbt service user's public key (one line, without the BEGIN/END lines)
-- and the Snowsight user who should see the results:
--   snow sql -c <admin connection> -f scripts/snowflake_admin.sql \
--     -D dbt_public_key="$(grep -v -- '-----' <path to the public key>.pub | tr -d '\n')" -D snowsight_user=<USER>
-- Safe to rerun: every statement is "if not exists" or a grant.

use role accountadmin;

-- warehouse for loading and dbt: smallest size, suspends after a minute
create warehouse if not exists enpal_wh
    warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true
    comment = 'Enpal take-home: loading and dbt';
grant usage on warehouse enpal_wh to role sysadmin;  -- the loader

-- databases: raw owned by SYSADMIN (the loader), test and prod by the dbt role
create database if not exists enpal_raw comment = 'Pipedrive CSVs as delivered; loaded once, never modified by dbt';
create schema if not exists enpal_raw.pipedrive comment = 'The six Pipedrive tables';
grant ownership on database enpal_raw to role sysadmin copy current grants;
grant ownership on schema enpal_raw.pipedrive to role sysadmin copy current grants;
create database if not exists enpal_test comment = 'dbt target test (default): zero-copy clones of ENPAL_RAW in SRC, then STAGING, INTERMEDIATE, MARTS, ELEMENTARY';
create database if not exists enpal_analytics_prod comment = 'dbt target prod: built from main only, reads ENPAL_RAW directly';

-- dbt role: read-only on raw, owner of test and prod
create role if not exists enpal_dbt_role comment = 'Enpal take-home: dbt';
grant role enpal_dbt_role to role sysadmin;
grant usage, operate on warehouse enpal_wh to role enpal_dbt_role;
grant usage on database enpal_raw to role enpal_dbt_role;
grant usage on schema enpal_raw.pipedrive to role enpal_dbt_role;
grant select on all tables in schema enpal_raw.pipedrive to role enpal_dbt_role;
grant select on future tables in schema enpal_raw.pipedrive to role enpal_dbt_role;
grant ownership on database enpal_test to role enpal_dbt_role copy current grants;
grant ownership on database enpal_analytics_prod to role enpal_dbt_role copy current grants;

-- service user for dbt and the Elementary CLI: key pair only, no secondary roles (so it cannot borrow other privileges)
create user if not exists enpal_dbt_user
    type = service
    default_role = enpal_dbt_role
    default_warehouse = enpal_wh
    default_secondary_roles = ()
    comment = 'Enpal take-home: dbt service user';
alter user enpal_dbt_user set rsa_public_key = '<% dbt_public_key %>';
grant role enpal_dbt_role to user enpal_dbt_user;

-- the developer sees the results in Snowsight
grant role enpal_dbt_role to user identifier('"<% snowsight_user %>"');
