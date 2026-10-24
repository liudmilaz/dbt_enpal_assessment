{{ config(
    tags=['dq_check', 'dq_process'],
    meta={'owner': 'data_team', 'quality_dimension': 'consistency', 'description': 'Found (EDA 07 #18, 08 B1a): no stage move is dated before the deal was created. Improve: none. Handled: none needed; rows here mean a wrong timestamp or a missing creation event.'}
) }}

-- each deal's first creation time
with created as (
    select
        deal_id,
        min(change_time) as created_at
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'add_time'  -- creation events only
    group by deal_id
),

-- stage moves only
stage_moves as (
    select
        deal_id,
        change_time
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- stage moves only
)

-- one failed row per stage move before the creation
select
    s.deal_id,
    s.change_time,
    c.created_at
from stage_moves s
join created c
    on c.deal_id = s.deal_id
where s.change_time < c.created_at
