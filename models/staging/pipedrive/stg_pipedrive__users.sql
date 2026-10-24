-- One row per CRM user, current state only (USER in the logical model).
-- email is not unique (U1: 4 shared): never join on it.

-- the raw users, renamed
with source as (
    select
        id as user_id,
        name as user_name,
        email,
        modified as modified_at
    from {{ source('pipedrive', 'users') }}
)

select
    user_id,
    user_name,
    email,
    modified_at
from source
