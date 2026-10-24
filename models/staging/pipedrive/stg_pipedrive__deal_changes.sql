-- One row per change of one deal field (DEAL_EVENT in the logical model).
-- new_value is text for every key (D6): one typed column per key, cast only for its own key.

-- the raw change log, with a surrogate key over the grain (deal, field key, change time)
with source as (
    select
        {{ dbt_utils.generate_surrogate_key(['deal_id', 'changed_field_key', 'change_time']) }} as deal_change_key,
        deal_id,
        changed_field_key,
        change_time,
        new_value
    from {{ source('pipedrive', 'deal_changes') }}
),

-- remove full-row duplicates only (DUP-1, decided 2026-10-23); two different values for one
-- key are a conflict, not a duplicate: they stay and fail the unique test on deal_change_key
deduplicated as (
    select
        deal_change_key,
        deal_id,
        changed_field_key,
        change_time,
        new_value
    from source
    qualify row_number() over (
        partition by deal_id, changed_field_key, change_time, new_value
        order by change_time
    ) = 1
)

-- typed value per key: a cast runs only on the rows of its own key
select
    deal_change_key,
    deal_id,
    changed_field_key,
    change_time,
    new_value,
    case when changed_field_key = 'add_time' then cast(new_value as timestamp_ntz) end as deal_created_at,
    case when changed_field_key = 'user_id' then cast(new_value as integer) end as owner_user_id,
    case when changed_field_key = 'stage_id' then cast(new_value as integer) end as stage_id,
    case when changed_field_key = 'lost_reason' then cast(new_value as integer) end as lost_reason_id
from deduplicated
