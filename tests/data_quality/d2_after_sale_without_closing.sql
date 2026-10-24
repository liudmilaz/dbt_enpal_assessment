{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D2', 'owner': 'sales_ops', 'quality_dimension': 'completeness', 'description': 'D2. Deals in an after-sale stage (7 to 9) that never entered Closing (6). Installation needs a signed contract, so the Closing was not recorded; the backfill counts them under Closing.'}
) }}

-- stage moves only, with the stage id typed after the filter
with stage_events as (
    select
        deal_id,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as stage_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- new_value is a stage id only for this key
),

-- per deal: the furthest stage and whether Closing was entered
deal_stages as (
    select
        deal_id,
        max(stage_id) as furthest_stage_id,
        sum(case when stage_id = 6 then 1 else 0 end) as closing_entries
    from stage_events
    group by deal_id
)

-- one failed row per after-sale deal without a Closing
select
    deal_id,
    furthest_stage_id
from deal_stages
where furthest_stage_id >= 7  -- Implementation, Follow-up or Renewal reached
    and closing_entries = 0   -- Closing never recorded
