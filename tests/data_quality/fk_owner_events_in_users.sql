{{ config(
    tags=['dq_check'],
    meta={'owner': 'data_team', 'quality_dimension': 'consistency', 'description': 'Foreign key deal_changes.new_value (key user_id) to users.id: 0 orphans on 2026-10-23, although users ends on 2024-10-28 (X1). Rows here mean owners missing from users.'}
) }}

-- owner changes only, with the user id typed after the filter
with owner_events as (
    select
        deal_id,
        change_time,
        new_value
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'user_id'  -- new_value is a user id only for this key
),

owner_events_typed as (
    select
        deal_id,
        change_time,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as owner_id
    from owner_events
),

-- the reference keys
users as (
    select
        id as user_id
    from {{ source('pipedrive', 'users') }}
)

-- one failed row per owner change to an unknown user
select
    e.deal_id,
    e.change_time,
    e.owner_id
from owner_events_typed e
left join users u
    on u.user_id = e.owner_id
where u.user_id is null  -- no matching user
