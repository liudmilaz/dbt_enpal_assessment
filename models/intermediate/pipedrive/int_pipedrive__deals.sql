-- One row per funnel deal (DEAL in the logical model): there is no deals table, so the deals come from the change
-- history. DUP-6: reps label accidental duplicates as "Duplicate Entry" (lost reason 5); these are not real sales
-- opportunities and are excluded from the funnel, also when Duplicate Entry is the first of two lifecycles' lost
-- reasons (D3).

-- the typed change log: deal and lost reason
with changes as (
    select
        deal_id,
        lost_reason_id
    from {{ ref('stg_pipedrive__deal_changes') }}
)

-- one row per deal without a Duplicate Entry lost reason
select
    deal_id
from changes
group by deal_id
having count_if(lost_reason_id = 5) = 0  -- DUP-6
