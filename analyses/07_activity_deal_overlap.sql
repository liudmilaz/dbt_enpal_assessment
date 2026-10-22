-- Question: can activities be joined to deals?
-- Finding:  only 8 of 4,572 distinct activity deal_ids exist in deal_changes; both id ranges are 6 digits, so random overlap is about as large.
-- Consequence: calls cannot be attributed to deals; count Sales Call 1/2 by due_to month and raise the question with Enpal.
select count(*) as n_activity_deals,
       sum(case when d.deal_id is not null then 1 else 0 end) as n_found_in_deal_changes
from (select distinct deal_id from public.activity) a
left join (select distinct deal_id from public.deal_changes) d using (deal_id);
