{{ config(
    tags=['dq_check', 'dq_process'],
    meta={'owner': 'data_team', 'quality_dimension': 'uniqueness', 'description': 'Found (EDA 07 #7): no deal has two stage moves at the same timestamp. Improve: none. Handled: the backfill orders stage entries by time and relies on it.'}
) }}

-- stage moves per deal and timestamp
with stage_moves_per_time as (
    select
        deal_id,
        change_time,
        count(*) as stage_moves
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- stage moves only
    group by
        deal_id,
        change_time
)

-- one failed row per tie
select
    deal_id,
    change_time,
    stage_moves
from stage_moves_per_time
where stage_moves > 1
