-- One row per funnel step of the task (FUNNEL_STEP in the logical model): 9 stage steps and 2 call steps, both from
-- the CRM dictionaries. Stage step names are the Stage field labels (the task's spelling, S1); call step names are the
-- activity type names. Nothing in the export links a call type to a stage (the activity fact matches almost no deal,
-- A2), so the step number of a call follows the task: Sales Call n comes after stage n + 1.

-- the pipeline stages
with stages as (
    select
        stage_id
    from {{ ref('stg_pipedrive__stages') }}
),

-- the labels of the Stage field
stage_labels as (
    select
        option_id,
        option_label
    from {{ ref('stg_pipedrive__field_options') }}
    where field_key = 'stage_id'  -- lost reasons are not funnel steps
),

-- steps 1 to 9: one per stage
stage_steps as (
    select
        cast(s.stage_id as varchar) as funnel_step,
        l.option_label as kpi_name,
        'stage' as source_type,
        s.stage_id,
        cast(null as varchar) as activity_type
    from stages s
    inner join stage_labels l
        on l.option_id = s.stage_id
),

-- steps 2.1 and 3.1: the sales call types; Sales Call n is step (n + 1).1
call_steps as (
    select
        cast(cast(regexp_substr(activity_type_name, '[0-9]+$') as integer) + 1 as varchar) || '.1' as funnel_step,
        activity_type_name as kpi_name,
        'activity' as source_type,
        cast(null as integer) as stage_id,
        activity_type
    from {{ ref('stg_pipedrive__activity_types') }}
    where activity_type_name like 'Sales Call %'  -- Follow Up Call and After Close Call are not funnel steps
),

-- stage and call steps together
all_steps as (
    select * from stage_steps
    union all
    select * from call_steps
)

-- the step number orders the funnel: 2.1 falls between 2 and 3
select
    funnel_step,
    kpi_name,
    source_type,
    stage_id,
    activity_type,
    row_number() over (order by cast(funnel_step as number(4, 1))) as sort_order
from all_steps
