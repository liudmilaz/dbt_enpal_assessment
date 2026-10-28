{{ config(
    severity='error',
    tags=['dq_check'],
    meta={'owner': 'data_team', 'quality_dimension': 'validity', 'description': 'Allowed values: every option of the Stage field is one of the report step names 1 to 9, spelled as in the task, under its stage id. The report takes its step names from these labels (S1).'}
) }}

-- the Stage field's options, unpacked from the field's JSON array of {id, label}
with stage_options as (
    select
        o.value:id::varchar as option_id,
        o.value:label::varchar as option_label
    from {{ source('pipedrive', 'fields') }} f
    inner join lateral flatten(input => f.field_value_options) o
    where f.field_key = 'stage_id'  -- only the Stage field's options
),

-- the allowed values: the report's stage steps and names
allowed as (
    select
        column1 as option_id,
        column2 as option_label
    from values
        ('1', 'Lead Generation'),
        ('2', 'Qualified Lead'),
        ('3', 'Needs Assessment'),
        ('4', 'Proposal/Quote Preparation'),
        ('5', 'Negotiation'),
        ('6', 'Closing'),
        ('7', 'Implementation/Onboarding'),
        ('8', 'Follow-up/Customer Success'),
        ('9', 'Renewal/Expansion')
)

-- one failed row per stage option whose id or label is not an allowed pair
select
    s.option_id,
    s.option_label
from stage_options s
left join allowed a
    on a.option_id = s.option_id
    and a.option_label = s.option_label
where a.option_id is null  -- not an allowed stage name under this id
