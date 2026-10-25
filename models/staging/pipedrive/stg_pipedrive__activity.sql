-- One row per activity (ACTIVITY in the logical model); activity_id is the primary key (decided 2026-10-23).
-- DUP-3: 11 activity_ids appear twice with different user, deal and due date; keep the latest version.

-- the raw activities, renamed and deduplicated on activity_id
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
qualify row_number() over (partition by activity_id order by due_at desc) = 1
