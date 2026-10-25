-- One row per deal and every stage from 1 to the highest stage it reached (STAGE_ENTRY in the logical model).
-- Deals skip stages (D1): a skipped stage counts as reached (decided by the owner), flagged is_inferred and
-- dated at the first recorded entry of a higher stage. Downstream consumers filter on is_inferred if needed;
-- for recorded-only entries use int_pipedrive__deal_stage_entries directly.

-- recorded entries
with recorded as (
    select
        deal_id,
        stage_id,
        entered_at
    from {{ ref('int_pipedrive__deal_stage_entries') }}
),

-- the highest stage each deal reached
deal_highest_stage as (
    select
        deal_id,
        max(stage_id) as highest_stage_id
    from recorded
    group by deal_id
),

-- every stage from 1 to the highest one, per deal
expected_stages as (
    select
        d.deal_id,
        s.stage_id
    from deal_highest_stage d
    inner join {{ ref('stg_pipedrive__stages') }} s
        on s.stage_id <= d.highest_stage_id
),

-- per expected stage: its recorded entry (null when skipped)
with_recorded as (
    select
        e.deal_id,
        e.stage_id,
        r.entered_at as recorded_at
    from expected_stages e
    left join recorded r
        on r.deal_id = e.deal_id
        and r.stage_id = e.stage_id
),

-- the next recorded entry of a higher stage: proves this stage was passed
dated as (
    select
        deal_id,
        stage_id,
        recorded_at,
        first_value(recorded_at ignore nulls) over (
            partition by deal_id
            order by stage_id
            rows between 1 following and unbounded following
        ) as next_recorded_at
    from with_recorded
)

select
    deal_id,
    stage_id,
    coalesce(recorded_at, next_recorded_at) as entered_at,
    recorded_at is null as is_inferred
from dated
