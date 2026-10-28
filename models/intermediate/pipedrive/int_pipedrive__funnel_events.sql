-- One row per funnel event at the lowest level (FUNNEL_EVENT in the logical model): every stage a funnel deal reached
-- (recorded or inferred, D1) and every sales call (done or not, A4), put together before anything is counted and
-- enriched with the cohort of the deal. The report decides what to count (for example done calls only); this model
-- keeps every event, so another rule needs no new model. The calls' deal ids are almost never in the deal history
-- (A2): their cohort is the month of their first activity (int_pipedrive__deal_cohorts).

-- the funnel steps of the stages
with stage_steps as (
    select
        funnel_step,
        stage_id
    from {{ ref('int_pipedrive__funnel_steps') }}
    where source_type = 'stage'  -- steps 1 to 9
),

-- stage events: one row per funnel deal and stage reached (DUP-6 already excluded upstream)
stage_events as (
    select
        'stage_entry' as event_source,
        s.funnel_step,
        e.deal_id,
        cast(null as integer) as activity_id,      -- stage entries have no activity
        e.entered_at as event_at,
        e.is_inferred,
        cast(null as boolean) as is_done,          -- applies to calls only
        cast(null as boolean) as is_due_before_export_end
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }} e
    inner join stage_steps s
        on s.stage_id = e.stage_id
),

-- call events: one row per Sales Call 1 or 2, done or not
call_events as (
    select
        'sales_call' as event_source,
        funnel_step,
        deal_id,
        activity_id,
        due_at as event_at,                        -- the planned time; the export has no completion time
        cast(null as boolean) as is_inferred,      -- applies to stage entries only
        is_done,
        is_due_before_export_end
    from {{ ref('int_pipedrive__sales_calls') }}
),

-- deals and calls together, at the event grain
funnel_events as (
    select
        event_source,
        funnel_step,
        deal_id,
        activity_id,
        event_at,
        is_inferred,
        is_done,
        is_due_before_export_end
    from stage_events
    union all
    select
        event_source,
        funnel_step,
        deal_id,
        activity_id,
        event_at,
        is_inferred,
        is_done,
        is_due_before_export_end
    from call_events
)

-- every event with the cohort of its deal
select
    {{ dbt_utils.generate_surrogate_key(['f.event_source', 'f.deal_id', 'f.funnel_step', 'f.activity_id']) }} as funnel_event_key,
    f.event_source,
    f.funnel_step,
    f.deal_id,
    f.activity_id,
    f.event_at,
    f.is_inferred,
    f.is_done,
    f.is_due_before_export_end,
    c.cohort_month,
    c.cohort_source
from funnel_events f
inner join {{ ref('int_pipedrive__deal_cohorts') }} c
    on c.deal_id = f.deal_id
