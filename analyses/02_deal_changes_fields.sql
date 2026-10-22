-- Question: what does deal_changes track, and for how many deals?
-- Finding:  an event log with four keys: stage_id 8,906, user_id 2,500, add_time 2,000, lost_reason 2,000 (each key covers all 1,995 deals).
-- Consequence: build the funnel from stage_id events; cast new_value per changed_field_key in staging.
select changed_field_key, count(*) as n_events, count(distinct deal_id) as n_deals
from public.deal_changes group by 1 order by 2 desc;
