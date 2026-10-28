{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D2', 'owner': 'sales_ops', 'quality_dimension': 'completeness', 'description': 'Found (EDA 00 D2): deals reach an after-sale stage (7 to 9) without a recorded Closing (6). Handled: the backfill counts them under Closing, flagged is_inferred in int_pipedrive__deal_stage_entries_backfilled.'}
) }}

-- stage moves only, with the stage id typed after the filter
with stage_events as (
    select
        deal_id,
        changed_field_key,
        change_time,
        new_value,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as stage_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- new_value is a stage id only for this key
),

-- deals that reached an after-sale stage but never entered Closing
deals_without_closing as (
    select
        deal_id
    from stage_events
    group by deal_id
    having max(stage_id) >= 7                 -- Implementation, Follow-up or Renewal reached
        and count_if(stage_id = 6) = 0        -- Closing never recorded
)

-- one failed row per raw stage move of those deals: the path that skips Closing
select
    s.deal_id,
    s.changed_field_key,
    s.change_time,
    s.new_value
from stage_events s
inner join deals_without_closing d
    on d.deal_id = s.deal_id
