{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'U2', 'owner': 'crm_admin', 'quality_dimension': 'consistency', 'description': 'U2. Users that own no activity and no deal. Not an error (users is the full user list), but part of the owner shape that does not look like a sales team.'}
) }}

-- users referenced as activity owner
with activity_owners as (
    select distinct
        assigned_to_user as user_id
    from {{ source('pipedrive', 'activity') }}
),

-- users referenced as deal owner, typed after the filter
deal_owners as (
    select distinct
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as user_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'user_id'  -- owner changes only
),

referenced as (
    select
        user_id
    from activity_owners
    union
    select
        user_id
    from deal_owners
)

-- one failed row per user nobody refers to
select
    u.id as user_id,
    u.name
from {{ source('pipedrive', 'users') }} u
left join referenced r
    on r.user_id = u.id
where r.user_id is null  -- no activity and no deal
