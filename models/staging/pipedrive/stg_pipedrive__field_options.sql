-- One row per option of a single-option deal field (FIELD_OPTION, and through it LOST_REASON, in the
-- logical model): the 9 stage labels and the 5 lost reasons. Fields without options have no rows.
-- The 9 stage options carry the task's funnel step mapping (step number, kpi name, sort order);
-- the 2 call funnel steps (Sales Call 1, Sales Call 2) are added as activity_type rows.

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
    from fields_with_options f,
        lateral flatten(input => f.field_value_options) o
),

-- the task's funnel step definitions: 9 stage steps and 2 call steps
funnel_steps as (
    select
        funnel_step::varchar as funnel_step,
        kpi_name::varchar as kpi_name,
        source_type::varchar as source_type,
        stage_id::integer as stage_id,
        activity_type::varchar as activity_type,
        sort_order::integer as sort_order
    from (values
        ('1',   'Lead Generation',            'stage',    1,    null, 1),
        ('2',   'Qualified Lead',             'stage',    2,    null, 2),
        ('2.1', 'Sales Call 1',               'activity', null, 'meeting', 3),
        ('3',   'Needs Assessment',           'stage',    3,    null, 4),
        ('3.1', 'Sales Call 2',               'activity', null, 'sc_2',    5),
        ('4',   'Proposal/Quote Preparation', 'stage',    4,    null, 6),
        ('5',   'Negotiation',                'stage',    5,    null, 7),
        ('6',   'Closing',                    'stage',    6,    null, 8),
        ('7',   'Implementation/Onboarding',  'stage',    7,    null, 9),
        ('8',   'Follow-up/Customer Success', 'stage',    8,    null, 10),
        ('9',   'Renewal/Expansion',          'stage',    9,    null, 11)
    ) as t(funnel_step, kpi_name, source_type, stage_id, activity_type, sort_order)
)

-- CRM field options enriched with funnel step attributes for stages
select
    o.field_key,
    o.field_name,
    o.option_id,
    o.option_label,
    f.funnel_step,
    f.kpi_name,
    f.source_type,
    cast(null as varchar) as activity_type,
    f.sort_order
from options o
left join funnel_steps f
    on f.stage_id = o.option_id
    and o.field_key = 'stage_id'

union all

-- the two call funnel steps (task-defined, not CRM field options)
select
    'activity_type' as field_key,
    cast(null as varchar) as field_name,
    cast(null as integer) as option_id,
    cast(null as varchar) as option_label,
    f.funnel_step,
    f.kpi_name,
    f.source_type,
    f.activity_type,
    f.sort_order
from funnel_steps f
where f.source_type = 'activity'
