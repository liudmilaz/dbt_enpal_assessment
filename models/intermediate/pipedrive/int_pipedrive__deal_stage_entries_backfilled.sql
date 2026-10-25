-- One row per deal and every stage from 1 to the highest stage it reached (STAGE_ENTRY in the logical model).
-- deals skip stages (D1): a skipped stage counts as reached (decided by the owner), flagged is_inferred and
-- dated at the first recorded entry of a higher stage. var funnel_backfill_skipped_stages = false keeps recorded rows only.

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

-- the first recorded entry of any higher stage: a later stage proves this one was passed
dated as (
    select
        deal_id,
        stage_id,
        recorded_at,
        min(recorded_at) over (
            partition by deal_id
            order by stage_id desc
            rows between unbounded preceding and 1 preceding
        ) as next_recorded_at
    from with_recorded
),

backfilled as (
    select
        deal_id,
        stage_id,
        coalesce(recorded_at, next_recorded_at) as entered_at,
        recorded_at is null as is_inferred
    from dated
)

select
    deal_id,
    stage_id,
    entered_at,
    is_inferred
from backfilled
{% if not var('funnel_backfill_skipped_stages') %}
where not is_inferred  -- recorded entries only
{% endif %}
