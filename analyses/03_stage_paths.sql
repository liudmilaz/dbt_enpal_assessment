-- Question: do deals move through the stages one by one?
-- Finding:  every deal starts at stage 1; 2,502 moves skip at least one stage (1,684 deals); 8 backward moves; 2 repeats.
-- Consequence: recorded-only counts under-count the middle steps -> backfill skipped stages with an is_inferred flag.
with s as (
  select deal_id, new_value::int as stage_id,
         lag(new_value::int) over (partition by deal_id order by change_time) as prev_stage
  from public.deal_changes where changed_field_key = 'stage_id'
)
select stage_id - prev_stage as move, count(*) as n_events
from s where prev_stage is not null group by 1 order by 1;
