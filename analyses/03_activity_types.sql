-- TABLE public.activity_types    CLASS: dictionary    GRAIN: one activity type
-- Business meaning: the kinds of activity; Sales Call 1 (key meeting) and Sales Call 2 (key sc_2) are funnel steps 2.1 and 3.1.
-- See docs/business_context.md; field definitions and Pipedrive links in docs/data_dictionary.md.
-- Findings in short:
--   - primary key: id, declared by the task; type (the key string) is also unique and is what activity references
--   - foreign keys: none; all 4 types are used by activity
--   - nulls: none
--   - descriptive: Follow Up Call is inactive but used by 1,133 activities; active is text ('Yes' / 'No'), not boolean
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).

-- =====================================================================
-- 1. Rows and columns
-- =====================================================================
select
    *
from public.activity_types;
-- 4 rows: id, name, active, type

-- =====================================================================
-- 2. Primary key
-- =====================================================================
-- Declared in init.sql: id. Rows that share it, and rows that share type:
with counted as (
    select
        *,
        count(*) over (partition by id)   as n_dup_id,
        count(*) over (partition by type) as n_dup_type
    from public.activity_types
)
select
    *
from counted
where n_dup_id > 1
    or n_dup_type > 1;
-- 0 rows

-- =====================================================================
-- 3. Foreign keys
-- =====================================================================
-- None: a dictionary points at nothing. Referenced by activity.type (see 02_activity, section 3).

-- =====================================================================
-- 4. Nulls per column
-- =====================================================================
select
    count(*) - count(id)     as id_nulls,
    count(*) - count(name)   as name_nulls,
    count(*) - count(active) as active_nulls,
    count(*) - count(type)   as type_nulls
from public.activity_types;
-- 0 | 0 | 0 | 0

-- =====================================================================
-- 5. Outliers
-- =====================================================================
-- Not applicable: 4 rows, no measure.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================
-- 6a. Usage by activities
select
    t.id,
    t.name,
    t.type,
    t.active,
    count(a.activity_id) as n_activities
from public.activity_types t
left join public.activity a
    on a.type = t.type
group by 1, 2, 3, 4
order by 1;
-- all 4 used; Follow Up Call is inactive (active = 'No') and still has 1,133 activities
