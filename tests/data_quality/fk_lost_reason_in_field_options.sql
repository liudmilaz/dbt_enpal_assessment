{{ config(
    tags=['dq_check'],
    meta={'owner': 'data_team', 'quality_dimension': 'consistency', 'description': 'Foreign key: every lost reason on a deal is an option of the Lost reason field.'}
) }}

-- the lost-reason options, unpacked from the field's JSON array of {id, label}
with lost_reason_options as (
    select
        o.value:id::varchar as option_id
    from {{ source('pipedrive', 'fields') }} f
    inner join lateral flatten(input => f.field_value_options) o
    where f.field_key = 'lost_reason'  -- only the lost-reason field's options
),

-- lost-reason events only
lost_reasons as (
    select
        deal_id,
        changed_field_key,
        change_time,
        new_value
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'lost_reason'  -- new_value is a lost-reason id only for this key
)

-- one failed row per raw lost-reason event with an unknown option
select
    r.deal_id,
    r.changed_field_key,
    r.change_time,
    r.new_value
from lost_reasons r
left join lost_reason_options o
    on o.option_id = r.new_value
where o.option_id is null  -- not an option of the field
