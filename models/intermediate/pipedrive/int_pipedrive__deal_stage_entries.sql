-- One row per deal and stage it entered as recorded (STAGE_ENTRY in the logical model, recorded part).
-- A deal that entered a stage twice (two lifecycles, D3; 2 repeats) counts once, by its first entry.

-- stage moves only
with stage_moves as (
    select
        deal_id,
        stage_id,
        change_time
    from {{ ref('stg_pipedrive__deal_changes') }}
    where changed_field_key = 'stage_id'  -- the typed stage_id is filled only on these rows
)

-- first entry per deal and stage
select
    deal_id,
    stage_id,
    min(change_time) as entered_at,
    false as is_inferred
from stage_moves
group by
    deal_id,
    stage_id
