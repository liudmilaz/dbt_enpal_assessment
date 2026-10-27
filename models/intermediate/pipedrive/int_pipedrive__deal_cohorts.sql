-- One row per funnel deal with its creation (DEAL in the logical model): the cohort the report counts the deal in.
-- Pipedrive's deal conversion report attributes a deal to the period it was created in (default filter "deal
-- created"), so every step a deal reaches counts in its creation month. A deal with two creations (two lifecycles,
-- D3) belongs to its first. Duplicate Entry deals (DUP-6) are already left out in staging.

-- creation events only
with creations as (
    select
        deal_id,
        deal_created_at
    from {{ ref('stg_pipedrive__deal_changes') }}
    where changed_field_key = 'add_time'  -- the typed deal_created_at is filled only on these rows
)

-- the first creation per deal
select
    deal_id,
    min(deal_created_at) as deal_created_at,
    date_trunc('month', min(deal_created_at))::date as cohort_month
from creations
group by
    deal_id
