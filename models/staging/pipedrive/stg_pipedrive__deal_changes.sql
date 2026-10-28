-- One row per change of one deal field (DEAL_EVENT in the logical model).
-- new_value is text for every key: one typed column per key, cast only for its own key.
-- DUP-6: reps label accidental duplicates as "Duplicate Entry" (lost reason 5); these are not real sales opportunities,
-- so every change of such a deal is left out here, also when Duplicate Entry is the first of two lifecycles' lost
-- reasons (D3). The raw-layer test dup6_duplicate_entry_deals_past_closing still lists them.

-- the raw change log without the Duplicate Entry deals, with a surrogate key over the grain (deal, field key, change time)
with source as (
    select
        -- A timestamp in a primary key is not good practice: in row-store databases the key is indexed, and a wide,
        -- always-new timestamp makes the index large and slow to maintain; a timestamp's precision can also differ
        -- between systems or loads, so the same change would get another key. Snowflake has no indexes, but the
        -- stability argument holds. The export has no change id, so the time is the only column that separates the
        -- changes of one deal and field. With a better understanding of the processes, the system and the whole
        -- code base, the key can be improved or adjusted (for example to a change id from the source system, if one is exported).
        {{ dbt_utils.generate_surrogate_key(['deal_id', 'changed_field_key', 'change_time']) }} as deal_change_key, --arguable if we need to include timestamp into PK, after the domain knowledge would be easier to understand if the PK is as precise as needed
        deal_id,
        changed_field_key,
        change_time,
        new_value
    from {{ source('pipedrive', 'deal_changes') }}
    qualify count_if(changed_field_key = 'lost_reason' and new_value = '5') over (partition by deal_id) = 0  -- DUP-6
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
from source
