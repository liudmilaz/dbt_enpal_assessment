{{ config(
    tags=['dq_check', 'dq_process'],
    meta={'owner': 'data_team', 'quality_dimension': 'uniqueness', 'description': 'No deal has two stage moves at the same timestamp: 0 on 2026-10-23. Rows here make the stage order, and so the backfill, ambiguous.'}
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
