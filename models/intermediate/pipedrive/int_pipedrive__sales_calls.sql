-- One row per sales call that is a funnel step (ACTIVITY in the logical model, the two call types only):
-- Sales Call 1 (type meeting, step 2.1) and Sales Call 2 (type sc_2, step 3.1). Done and not done are both kept;
-- the funnel report counts done calls only. is_due_before_export_end flags the calls that were due before the export
-- ended but are not marked done (A4), to count them as held if Enpal confirms (question 5).
-- deal_id matches the deal history for only 8 activities (A2).

-- the funnel steps that come from activities
with call_steps as (
    select
        funnel_step,
        activity_type
    from {{ ref('int_pipedrive__funnel_steps') }}
    where source_type = 'activity'  -- steps 2.1 and 3.1
),

-- staged activities
activities as (
    select
        activity_id,
        activity_type,
        assigned_user_id,
        deal_id,
        is_done,
        due_at
    from {{ ref('stg_pipedrive__activity') }}
),

-- the export end: the last change of the deal history, the latest point in time the export covers (X1)
export_end as (
    select
        max(change_time) as export_last_at
    from {{ ref('stg_pipedrive__deal_changes') }}
)

select
    a.activity_id,
    c.funnel_step,
    a.activity_type,
    a.deal_id,
    a.assigned_user_id,
    a.is_done,
    a.due_at,
    a.due_at < e.export_last_at as is_due_before_export_end  -- A4: reps hold calls without marking them done
from activities a
inner join call_steps c
    on c.activity_type = a.activity_type
cross join export_end e
