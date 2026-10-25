-- One row per deal with its funnel milestones (DEAL in the logical model), for the Deals Overview dashboard.
-- There is no won/lost status and no amount in the export: "closed" means the deal reached stage 6 (Closing),
-- recorded or inferred. The lead month is the month of the first entry into stage 1 (the cohort).

-- the deals with their flags
with deals as (
    select
        deal_id,
        created_at,
        first_stage_entered_at,
        highest_stage_id,
        is_duplicate_entry
    from {{ ref('int_pipedrive__deals') }}
),

-- the entry into Closing (stage 6), recorded or inferred
closings as (
    select
        deal_id,
        entered_at as closing_entered_at,
        is_inferred
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }}
    where stage_id = 6  -- Closing
)

select
    d.deal_id,
    d.created_at,
    d.first_stage_entered_at as lead_entered_at,
    date_trunc('month', d.first_stage_entered_at)::date as lead_month,
    d.highest_stage_id,
    c.closing_entered_at,
    date_trunc('month', c.closing_entered_at)::date as closing_month,
    c.closing_entered_at is not null as is_closed,
    c.is_inferred,
    datediff('day', d.first_stage_entered_at, c.closing_entered_at) as days_lead_to_closing,
    d.is_duplicate_entry
from deals d
left join closings c
    on c.deal_id = d.deal_id
