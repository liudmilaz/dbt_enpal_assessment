{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D1', 'owner': 'sales_ops', 'quality_dimension': 'completeness', 'description': 'Found (EDA 00 D1, 01 §6a): deals jump over stages; reps move them several stages at once. Handled: int_pipedrive__deal_stage_entries_backfilled counts a skipped stage as reached (is_inferred), dated at the earliest recorded entry of a higher stage.'}
) }}

-- one failed row per raw stage move that jumps over at least one stage,
-- with the skipped stages and every stage the deal entered (its recorded path)
select
    deal_id,
    change_time,
    lag(new_value::int) over (partition by deal_id order by change_time) as previous_stage_id,
    new_value::int as stage_id,
    array_to_string(array_generate_range(previous_stage_id + 1, stage_id), ',') as skipped_stage_ids,  -- stages between the two moves
    listagg(new_value, '>') within group (order by change_time) over (partition by deal_id) as recorded_stages  -- every stage the deal entered
from {{ source('pipedrive', 'deal_changes') }}
where changed_field_key = 'stage_id'  -- stage moves only
qualify stage_id - previous_stage_id > 1  -- skipped at least one stage
