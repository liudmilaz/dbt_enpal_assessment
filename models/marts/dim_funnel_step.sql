-- One row per funnel step of the task (FUNNEL_STEP in the logical model): 9 stage steps and 2 call steps.
-- Step names are the task's (not the CRM spelling, S1).

-- the funnel steps, as defined by the task
with funnel_steps as (
    select
        cast(funnel_step as varchar) as funnel_step,
        kpi_name,
        source_type,
        stage_id,
        activity_type,
        sort_order
    from {{ ref('funnel_steps') }}
)

select
    funnel_step,
    kpi_name,
    source_type,
    stage_id,
    activity_type,
    sort_order
from funnel_steps
