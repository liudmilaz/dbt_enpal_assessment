{{ config(
    tags=['dq_known_issue', 'dq_duplicates'],
    meta={'issue': 'DUP-6', 'owner': 'sales_ops', 'quality_dimension': 'accuracy', 'description': 'Found (EDA 07 #26-27, 08 B5b): deals lost as Duplicate Entry still reached Closing or later, so duplicates are not caught early. Improve (sales ops): merge duplicate leads before qualification. Handled: duplicates are kept as deals; whether to drop them from the funnel is open (DUP-6).'}
) }}

-- deals whose lost reason is Duplicate Entry
with duplicate_entries as (
    select distinct
        deal_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'lost_reason'  -- lost reasons only
        and new_value = '5'                  -- Duplicate Entry
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

-- one failed row per Duplicate Entry deal that got to Closing or further
select
    d.deal_id,
    f.furthest_stage_id
from duplicate_entries d
join furthest_stages f
    on f.deal_id = d.deal_id
where f.furthest_stage_id >= 6  -- Closing or an after-sale stage
