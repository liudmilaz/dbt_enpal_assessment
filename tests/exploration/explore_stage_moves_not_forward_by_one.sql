-- business logic: stage moves that are not exactly +1 (skips, repeats, backward). Informational: expected to fail.
with m as (
  select deal_id, change_time, new_value::int as stage_id,
         lag(new_value::int) over (partition by deal_id order by change_time) as prev_stage
  from {{ source('postgres_public', 'deal_changes') }} where changed_field_key = 'stage_id'
)
select deal_id, change_time, prev_stage, stage_id, stage_id - prev_stage as move
from m where prev_stage is not null and stage_id - prev_stage <> 1
