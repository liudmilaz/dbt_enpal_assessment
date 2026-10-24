{{ config(
    tags=['dq_check', 'dq_process'],
    meta={'owner': 'data_team', 'quality_dimension': 'consistency', 'description': 'Found (EDA 07 #17): every deal enters the funnel at stage 1 (Lead Generation). Improve: none. Handled: step 1 relies on it; int_pipedrive__deals tests first_stage_id = 1 at error.'}
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
