{{ config(
    tags=['dq_check'],
    meta={'owner': 'data_team', 'quality_dimension': 'consistency', 'description': 'Found (EDA 07 #12): every owner id exists in users, although users can end earlier (X1). Improve: none. Handled: staging tests owner_user_id against stg_pipedrive__users at error.'}
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
