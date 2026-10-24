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
),

-- 11 activity_ids are shared by two unrelated activities (A1 / DUP-3): keep the latest due_at per id
-- (decided 2026-10-23; 4,579 rows to 4,568). The tie-break on the other columns makes the choice repeatable.
deduplicated as (
    select
        activity_id,
        activity_type,
        assigned_user_id,
        deal_id,
        is_done,
        due_at
    from source
    qualify row_number() over (
        partition by activity_id
        order by
            due_at desc,
            assigned_user_id desc,
            deal_id desc
    ) = 1
)

select
    activity_id,
    activity_type,
    assigned_user_id,
    deal_id,
    is_done,
    due_at
from deduplicated
