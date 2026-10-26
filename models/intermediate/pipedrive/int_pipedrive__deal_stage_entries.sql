-- One row per funnel deal and stage it entered as recorded (STAGE_ENTRY in the logical model, recorded part).
-- Only the funnel deals of int_pipedrive__deals: Duplicate Entry deals (DUP-6) are left out here, so every model
-- downstream starts from the funnel deals. A deal that entered a stage twice (two lifecycles, D3) counts once,
-- by its first entry.

-- the funnel deals (DUP-6 excluded)
with deals as (
    select
        deal_id
    from {{ ref('int_pipedrive__deals') }}
),

-- stage moves only
stage_moves as (
    select
        deal_id,
        stage_id,
        change_time
    from {{ ref('stg_pipedrive__deal_changes') }}
    where changed_field_key = 'stage_id'  -- the typed stage_id is filled only on these rows
)

-- first entry per funnel deal and stage
select
    m.deal_id,
    m.stage_id,
    min(m.change_time) as entered_at
from stage_moves m
inner join deals d
    on d.deal_id = m.deal_id
group by
    m.deal_id,
    m.stage_id
