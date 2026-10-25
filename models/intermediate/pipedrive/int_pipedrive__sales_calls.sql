-- One row per sales call that is a funnel step (ACTIVITY in the logical model, the two call types only):
-- Sales Call 1 (type meeting, step 2.1) and Sales Call 2 (type sc_2, step 3.1). Done and not done are both kept;
-- the funnel report filters to done calls only. deal_id matches the deal history for only 8 activities (A2).

-- the funnel steps that come from activities
with call_steps as (
    select
        funnel_step,
        activity_type
    from {{ ref('funnel_steps') }}
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
)

select
    a.activity_id,
    c.funnel_step,
    a.activity_type,
    a.deal_id,
    a.assigned_user_id,
    a.is_done,
    a.due_at
from activities a
inner join call_steps c
    on c.activity_type = a.activity_type
