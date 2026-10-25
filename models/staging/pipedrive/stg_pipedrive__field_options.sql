-- One row per option of a single-option deal field (FIELD_OPTION, and through it LOST_REASON, in the
-- logical model): the 9 stage labels and the 5 lost reasons. Fields without options have no rows.

-- the fields that carry options
with fields_with_options as (
    select
        field_key,
        name as field_name,
        field_value_options
    from {{ source('pipedrive', 'fields') }}
    where field_value_options is not null  -- only single-option fields have an options array
),

-- one row per array element; ids are strings in the JSON
options as (
    select
        f.field_key,
        f.field_name,
        cast(o.value:id::varchar as integer) as option_id,
        o.value:label::varchar as option_label
    from fields_with_options f
    inner join lateral flatten(input => f.field_value_options) o
)

select
    field_key,
    field_name,
    option_id,
    option_label
from options
