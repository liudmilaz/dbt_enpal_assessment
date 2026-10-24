-- One row per activity type (ACTIVITY_TYPE in the logical model). activity_type is the key string
-- that activities reference; the flag 'Yes' / 'No' becomes a boolean (T1).

-- the raw activity types, renamed and typed
with source as (
    select
        id as activity_type_id,
        name as activity_type_name,
        type as activity_type,
        active = 'Yes' as is_active
    from {{ source('pipedrive', 'activity_types') }}
)

select
    activity_type_id,
    activity_type_name,
    activity_type,
    is_active
from source
