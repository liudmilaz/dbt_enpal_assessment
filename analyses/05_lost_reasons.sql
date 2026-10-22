-- Question: what does lost_reason mean here?
-- Finding:  every deal has one (values 1-5, roughly uniform), including deals that reached stage 9; for 4 of the 5 two-lifecycle deals it is dated before the last stage event.
-- Consequence: lost_reason marks the end of a lifecycle, not a lost deal; it does not remove deals from the funnel.
with mx as (select deal_id, max(new_value::int) as max_stage from public.deal_changes where changed_field_key = 'stage_id' group by 1)
select l.new_value as lost_reason, count(*) as n_deals, round(avg(mx.max_stage), 2) as avg_max_stage
from public.deal_changes l join mx using (deal_id)
where l.changed_field_key = 'lost_reason' group by 1 order by 1;
