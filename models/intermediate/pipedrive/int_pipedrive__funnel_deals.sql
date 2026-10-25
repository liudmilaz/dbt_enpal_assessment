-- Deals eligible for the funnel report (DUP-6): excludes Duplicate Entry deals when the var is set.
-- fct_deals keeps all deals with the flag for the Deals Overview.

select
    deal_id,
    created_at,
    first_stage_entered_at
from {{ ref('int_pipedrive__deals') }}
{% if var('exclude_duplicate_entry_deals') %}
where not is_duplicate_entry
{% endif %}
