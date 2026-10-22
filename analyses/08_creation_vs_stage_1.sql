-- Question: which date should define Step 1 (Lead Generation)?
-- Finding:  deals enter stage 1 a median of 35 days after add_time (min 2, max 83, IQR 25-45); 2024-01 has 247 created but 30 entering stage 1.
-- Consequence: Step 1 = stage 1 entry (consistent with the other steps); add_time stays documented as the alternative.
with a as (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1),
     s as (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'stage_id' and new_value = '1' group by 1)
select percentile_cont(0.5) within group (order by extract(epoch from s.ts - a.ts) / 86400) as median_days,
       min(extract(epoch from s.ts - a.ts) / 86400) as min_days, max(extract(epoch from s.ts - a.ts) / 86400) as max_days
from a join s using (deal_id);
