-- One row per funnel deal and stage it entered as recorded (STAGE_ENTRY in the logical model, recorded part).
-- Duplicate Entry deals (DUP-6) are already left out in staging. A deal that entered a stage twice (two lifecycles,
-- D3) counts once, by its first entry.

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
    min(change_time) as entered_at
from stage_moves
group by
    deal_id,
    stage_id
