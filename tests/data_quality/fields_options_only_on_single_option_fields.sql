{{ config(
    tags=['dq_check', 'dq_types'],
    meta={'owner': 'data_team', 'quality_dimension': 'completeness', 'description': 'Found (EDA 06 §4, 07 #9): field_value_options is filled for the single-option fields stage_id and lost_reason only. Improve: none. Handled: stg_pipedrive__field_options unpacks the options of these two fields.'}
) }}

-- the fields whose option list is present or missing where it should not be
select
    field_key,
    field_value_options is null as has_no_options
from {{ source('pipedrive', 'fields') }}
where (field_value_options is null) <> (field_key in ('add_time', 'user_id'))  -- options expected only for stage_id and lost_reason
