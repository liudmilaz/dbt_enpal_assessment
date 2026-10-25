-- One row per funnel step of the task (FUNNEL_STEP in the logical model): 9 stage steps and 2 call steps.
-- Step names are the task's (not the CRM spelling, S1).

select
    funnel_step,
    kpi_name,
    source_type,
    option_id as stage_id,
    activity_type,
    sort_order
from {{ ref('stg_pipedrive__field_options') }}
where funnel_step is not null
