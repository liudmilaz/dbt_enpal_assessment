{{ config(
    tags=['dq_known_issue', 'dq_types'],
    meta={'issue': 'S1', 'owner': 'crm_admin', 'quality_dimension': 'validity', 'description': 'Found (EDA 05 §6a, 07 #10): a stage name is spelled differently in stages and in the field labels (Qualified lead vs Qualified Lead). Improve (CRM admin): one spelling. Handled: the report names the steps by the Stage field labels (the task\'s spelling), pinned by tests on int_pipedrive__funnel_steps.kpi_name.'}
) }}

-- the stage labels, unpacked from the stage field's options (JSON array of {id, label})
with stage_labels as (
    select
        o.value:id::int as stage_id,
        o.value:label::varchar as stage_label
    from {{ source('pipedrive', 'fields') }} f,
        lateral flatten(input => f.field_value_options) o
    where f.field_key = 'stage_id'  -- only the stage field's options
)

-- one failed row per stage spelled differently
select
    s.stage_id,
    s.stage_name,
    l.stage_label
from {{ source('pipedrive', 'stages') }} s
inner join stage_labels l
    on l.stage_id = s.stage_id
where s.stage_name <> l.stage_label
