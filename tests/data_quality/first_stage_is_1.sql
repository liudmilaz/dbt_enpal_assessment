{{ config(
    tags=['dq_check', 'dq_process'],
    meta={'owner': 'data_team', 'quality_dimension': 'consistency', 'description': 'Every deal enters the funnel at stage 1 (Lead Generation): 0 exceptions on 2026-10-23. Step 1 relies on it.'}
) }}

-- stage moves only, numbered per deal in time order
with stage_moves as (
    select
        deal_id,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as stage_id,
        row_number() over (
            partition by deal_id
            order by change_time
        ) as move_number
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- new_value is a stage id only for this key
)

-- one failed row per deal whose first stage is not 1
select
    deal_id,
    stage_id as first_stage_id
from stage_moves
where move_number = 1  -- the first move
    and stage_id <> 1
