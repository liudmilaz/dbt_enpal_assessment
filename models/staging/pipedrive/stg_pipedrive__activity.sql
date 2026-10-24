-- One row per activity (ACTIVITY in the logical model); activity_id is the primary key (decided 2026-10-23).

-- the raw activities, renamed
with source as (
    select
        activity_id,
        type as activity_type,
        assigned_to_user as assigned_user_id,
        deal_id,
        done as is_done,
        due_to as due_at
    from {{ source('pipedrive', 'activity') }}
)

select
    activity_id,
    activity_type,
    assigned_user_id,
    deal_id,
    is_done,
    due_at
from source
