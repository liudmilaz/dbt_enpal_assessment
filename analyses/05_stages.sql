-- TABLE public.stages    CLASS: dictionary    GRAIN: one pipeline stage
-- Business meaning: the nine steps of the sales pipeline; stage_id order is the funnel order. See docs/business_context.md;
-- field definitions and Pipedrive links in docs/data_dictionary.md.
-- Findings in short:
--   - primary key: stage_id, declared by the task
--   - foreign keys: none; all 9 stages are used by the stage events
--   - nulls: none
--   - descriptive: stage 2 is spelled "Qualified lead" here and "Qualified Lead" in fields (text comparison is case sensitive)
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).

-- =====================================================================
-- 1. Rows and columns
-- =====================================================================
select
    *
from public.stages
order by stage_id;
-- 9 rows: stage_id, stage_name

-- =====================================================================
-- 2. Primary key
-- =====================================================================
-- Declared in init.sql: stage_id. Rows that share it:
with counted as (
    select
        *,
        count(*) over (partition by stage_id) as n_dup
    from public.stages
)
select
    *
from counted
where n_dup > 1;
-- 0 rows

-- =====================================================================
-- 3. Foreign keys
-- =====================================================================
-- None: a dictionary points at nothing. Referenced by the stage events in deal_changes (see 01_deal_changes, section 3).

-- =====================================================================
-- 4. Nulls per column
-- =====================================================================
select
    count(*) - count(stage_id)   as stage_id_nulls,
    count(*) - count(stage_name) as stage_name_nulls
from public.stages;
-- 0 | 0

-- =====================================================================
-- 5. Outliers
-- =====================================================================
-- Not applicable: 9 rows, no measure.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================
-- 6a. Stage names compared with the stage labels in fields
with stage_labels as (  -- unpack the JSON array once: one row per stage option
    select
        o.id as stage_id,
        o.label as stage_label
    from public.fields f
    cross join jsonb_to_recordset(f.field_value_options) as o(id int, label text)  -- typed columns: id arrives as int, no (o ->> 'id')::int
    where f.field_key = 'stage_id'  -- unpack only the stage field's array
)
select
    s.stage_id,
    s.stage_name,
    l.stage_label
from public.stages s
join stage_labels l
    on l.stage_id = s.stage_id
where s.stage_name <> l.stage_label;
-- 1 row: stage 2, "Qualified lead" vs "Qualified Lead"; equal under lower(); the report uses the task's names
