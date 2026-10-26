{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D1', 'owner': 'sales_ops', 'quality_dimension': 'completeness', 'description': 'Found (EDA 00 D1, 01 §6a): deals jump over stages; reps move them several stages at once. Improve (sales ops): move deals stage by stage. Handled: int_pipedrive__deal_stage_entries_backfilled counts a skipped stage as reached (is_inferred), dated at the earliest recorded entry of a higher stage.'}
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

-- each move with the stage before it
stage_moves as (
    select
        deal_id,
        changed_field_key,
        change_time,
        new_value,
        stage_id,
        lag(stage_id) over (
            partition by deal_id
            order by change_time
        ) as previous_stage_id
    from stage_events
)

-- one failed row per raw stage move that jumps over at least one stage
select
    deal_id,
    changed_field_key,
    change_time,
    new_value,
    previous_stage_id
from stage_moves
where stage_id - previous_stage_id > 1  -- skipped at least one stage
