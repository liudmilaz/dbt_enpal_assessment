-- One row per deal id of the funnel, from the deal history or from the calls (DEAL in the logical model), with the
-- cohort the report counts the deal in. Pipedrive's deal conversion report attributes a deal to the period it was
-- created in (default filter "deal created"), so every step a deal reaches counts in its creation month. A deal with
-- two creations (two lifecycles, D3) belongs to its first. Duplicate Entry deals (DUP-6) are already left out in
-- staging. The calls' deal ids are almost never in the deal history (A2) and have no creation date: their cohort is
-- the month of the deal's first activity, the earliest date the export knows for them.

-- creation events only
with creations as (
    select
        deal_id,
        deal_created_at
    from {{ ref('stg_pipedrive__deal_changes') }}
    where changed_field_key = 'add_time'  -- the typed deal_created_at is filled only on these rows
),

-- the first creation per deal of the deal history
history_deals as (
    select
        deal_id,
        min(deal_created_at) as cohort_at
    from creations
    group by
        deal_id
),

-- the first activity per deal id of the activities (any type, done or not)
activity_deals as (
    select
        deal_id,
        min(due_at) as cohort_at
    from {{ ref('stg_pipedrive__activity') }}
    group by
        deal_id
),

-- deals of the history by their creation; activity deals only when the history does not know them (A2)
deal_dates as (
    select
        deal_id,
        cohort_at,
        'deal_created' as cohort_source
    from history_deals
    union all
    select
        a.deal_id,
        a.cohort_at,
        'first_activity' as cohort_source
    from activity_deals a
    left join history_deals h
        on h.deal_id = a.deal_id
    where h.deal_id is null  -- not in the deal history
)

select
    deal_id,
    cohort_at,
    cohort_source,
    date_trunc('month', cohort_at)::date as cohort_month
from deal_dates
