{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D4', 'owner': 'crm_admin', 'quality_dimension': 'accuracy', 'description': 'D4. Deals lost as Unreachable Customer (reason 3) that reached Needs Assessment or later, so the customer was reached. The lost reason does not describe where a deal stopped.'}
) }}

-- deals whose lost reason is Unreachable Customer
with unreachable as (
    select distinct
        deal_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'lost_reason'  -- lost reasons only
        and new_value = '3'                  -- Unreachable Customer
),

-- the furthest stage per deal, typed after the filter
furthest_stages as (
    select
        deal_id,
        max({{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }}) as furthest_stage_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- stage moves only
    group by deal_id
)

-- one failed row per unreachable deal that got to Needs Assessment or further
select
    u.deal_id,
    f.furthest_stage_id
from unreachable u
join furthest_stages f
    on f.deal_id = u.deal_id
where f.furthest_stage_id >= 3  -- Needs Assessment or later: the customer was talked to
