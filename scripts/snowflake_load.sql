-- Load the six Pipedrive CSVs (raw_data/) into ENPAL_RAW.PIPEDRIVE, once, as SYSADMIN (the loader; dbt can only read raw).
-- Needs scripts/snowflake_admin.sql first. Run from the repo root:
--   snow sql -c <admin connection> -f scripts/snowflake_load.sql
-- Safe to rerun: the tables are replaced, so a reload never appends rows twice.
-- New tables are readable by ENPAL_DBT_ROLE through the future grant in snowflake_admin.sql.

use role sysadmin;
use warehouse enpal_wh;
use schema enpal_raw.pipedrive;

-- The six tables with their declared types (fields.field_value_options holds JSON: variant)
create or replace table activity_types (
    id int primary key,
    name varchar(255),
    active varchar(10),
    type varchar(50)
);
create or replace table activity (
    activity_id int,
    type varchar(50),
    assigned_to_user int,
    deal_id int,
    done boolean,
    due_to timestamp_ntz
);
create or replace table deal_changes (
    deal_id int,
    change_time timestamp_ntz,
    changed_field_key varchar(50),
    new_value varchar(255)
);
create or replace table fields (
    id int primary key,
    field_key varchar(50),
    name varchar(255),
    field_value_options variant
);
create or replace table stages (
    stage_id int primary key,
    stage_name varchar(255)
);
create or replace table users (
    id int primary key,
    name varchar(255),
    email varchar(255),
    modified timestamp_ntz
);

create or replace file format csv_header
    type = csv skip_header = 1 field_optionally_enclosed_by = '"' empty_field_as_null = true;
create or replace stage raw_csv file_format = csv_header;

-- Load the six CSVs; fields.field_value_options is parsed from JSON text
put file://raw_data/*.csv @raw_csv auto_compress = true overwrite = true;
copy into activity_types from @raw_csv/activity_types.csv.gz;
copy into activity from @raw_csv/activity.csv.gz;
copy into deal_changes from @raw_csv/deal_changes.csv.gz;
copy into stages from @raw_csv/stages.csv.gz;
copy into users from @raw_csv/users.csv.gz;
copy into fields from (select $1, $2, $3, parse_json($4) from @raw_csv/fields.csv.gz);
select 'activity_types' t, count(*) n from activity_types union all select 'activity', count(*) from activity
union all select 'deal_changes', count(*) from deal_changes union all select 'fields', count(*) from fields
union all select 'stages', count(*) from stages union all select 'users', count(*) from users;
