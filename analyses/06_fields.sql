-- TABLE public.fields    CLASS: dictionary (metadata)    GRAIN: one deal field
-- Business meaning: decodes the keys and option ids in deal_changes into names and labels (stage labels, lost reasons).
-- See vault/project/business_context.md; field definitions and Pipedrive links in vault/project/data_dictionary.md.
-- Findings in short:
--   - primary key: id, declared by the task; field_key is also unique and is what deal_changes references
--   - foreign keys: none; all 4 field keys are used by deal_changes
--   - nulls: field_value_options is null for user_id and add_time (no option list: expected)
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).

-- =====================================================================
-- 1. Rows and columns
-- =====================================================================
select
    *
from public.fields;
-- 4 rows: id, field_key, name, field_value_options (JSON)

-- =====================================================================
-- 2. Primary key
-- =====================================================================
-- Declared in init.sql: id. Rows that share it, and rows that share field_key:
with counted as (
    select
        *,
        count(*) over (partition by id)        as n_dup_id,
        count(*) over (partition by field_key) as n_dup_key
    from public.fields
)
select
    *
from counted
where n_dup_id > 1
    or n_dup_key > 1;
-- 0 rows

-- =====================================================================
-- 3. Foreign keys
-- =====================================================================
-- None: a dictionary points at nothing. Referenced by deal_changes.changed_field_key (see 01_deal_changes, section 3).

-- =====================================================================
-- 4. Nulls per column
-- =====================================================================
select
    count(*) - count(id)                  as id_nulls,
    count(*) - count(field_key)           as field_key_nulls,
    count(*) - count(name)                as name_nulls,
    count(*) - count(field_value_options) as field_value_options_nulls
from public.fields;
-- 0 | 0 | 0 | 2 (user_id and add_time have no option list)

-- =====================================================================
-- 5. Outliers
-- =====================================================================
-- Not applicable: 4 rows, no measure.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================
-- 6a. The option lists inside field_value_options (JSON keys are case sensitive: 'label', not 'Label')
select
    f.field_key,
    o.id as option_id,
    o.label as option_label
from public.fields f
cross join jsonb_to_recordset(f.field_value_options) as o(id int, label text)  -- one row per option, typed; fields without options (null) drop out
order by f.field_key, o.id;
-- lost_reason: 1 Customer Not Ready, 2 Pricing Issues, 3 Unreachable Customer, 4 Product Mismatch, 5 Duplicate Entry
-- stage_id: the nine stage labels
