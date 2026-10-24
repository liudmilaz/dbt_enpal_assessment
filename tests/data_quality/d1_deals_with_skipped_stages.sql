{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D1', 'owner': 'sales_ops', 'quality_dimension': 'completeness', 'description': 'D1. Deals that jump over at least one stage. The intermediate layer backfills the skipped stages with is_inferred.'}
) }}

-- stage moves only, with the stage id typed after the filter
with stage_events as (
    select
        deal_id,
        change_time,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as stage_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- new_value is a stage id only for this key
),

-- each move with the stage before it
stage_moves as (
    select
        deal_id,
        change_time,
        stage_id,
        lag(stage_id) over (
            partition by deal_id
            order by change_time
        ) as previous_stage_id
    from stage_events
)

-- one failed row per deal with a jump of more than one stage
select
    deal_id,
    count(*) as skipping_moves,
    max(stage_id - previous_stage_id) as largest_jump
from stage_moves
where stage_id - previous_stage_id > 1  -- skipped at least one stage
group by deal_id
