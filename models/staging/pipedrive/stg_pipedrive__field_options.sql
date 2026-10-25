-- One row per option of a single-option deal field (FIELD_OPTION, and through it LOST_REASON, in the
-- logical model): the 9 stage labels and the 5 lost reasons. Fields without options have no rows.
-- The 9 stage options carry the task's funnel step mapping (step number, kpi name, sort order);
-- the 2 call funnel steps (Sales Call 1, Sales Call 2) are added as activity_type rows.

-- the fields that carry options
with fields_with_options as (
    select
        field_key,
        name as field_name,
        field_value_options
    from {{ source('pipedrive', 'fields') }}
    where field_value_options is not null  -- only single-option fields have an options array
),

-- one row per array element; ids are strings in the JSON
options as (
    select
        f.field_key,
        f.field_name,
        cast(o.value:id::varchar as integer) as option_id,
        o.value:label::varchar as option_label
    from fields_with_options f,
        lateral flatten(input => f.field_value_options) o
)

-- CRM field options enriched with funnel step attributes for stages
select
    field_key,
    field_name,
    option_id,
    option_label,
    case when field_key = 'stage_id'
        then cast(option_id as varchar)
    end as funnel_step,
    -- option_label matches the task's step names (S1: stages.stage_name differs, not the field label)
    case when field_key = 'stage_id'
        then option_label
    end as kpi_name,
    case when field_key = 'stage_id'
        then 'stage'
    end as source_type,
    cast(null as varchar) as activity_type,
    -- sort order interleaves 2 call steps: after stage 2 (Sales Call 1) and after stage 3 (Sales Call 2)
    case
        when field_key != 'stage_id' then null
        when option_id <= 2 then option_id
        when option_id = 3 then option_id + 1
        else option_id + 2
    end as sort_order
from options

union all

-- the two call funnel steps (task-defined, not CRM field options)
select
    'activity_type' as field_key,
    cast(null as varchar) as field_name,
    cast(null as integer) as option_id,
    cast(null as varchar) as option_label,
    funnel_step,
    kpi_name,
    source_type,
    activity_type,
    sort_order
from (values
    ('2.1', 'Sales Call 1', 'activity', 'meeting', 3),
    ('3.1', 'Sales Call 2', 'activity', 'sc_2',    5)
) as t(funnel_step, kpi_name, source_type, activity_type, sort_order)
