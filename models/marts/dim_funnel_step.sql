-- One row per funnel step of the task (FUNNEL_STEP in the logical model): 9 stage steps and 2 call steps.

select
    funnel_step,
    kpi_name,
    source_type,
    stage_id,
    sort_order
from {{ ref('int_pipedrive__funnel_steps') }}
