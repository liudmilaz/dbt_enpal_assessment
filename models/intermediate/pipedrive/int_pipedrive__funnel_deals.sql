-- Deals eligible for the funnel report (DUP-6): excludes Duplicate Entry deals.
-- fct_deals keeps all deals with the flag for the Deals Overview.

select
    deal_id,
    created_at,
    first_stage_entered_at
from {{ ref('int_pipedrive__deals') }}
where not is_duplicate_entry
