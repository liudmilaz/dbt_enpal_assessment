-- temporal: lost_reason dated before the last stage event of the same deal
select l.deal_id, l.change_time as lost_ts, s.last_stage_ts
from {{ source('postgres_public', 'deal_changes') }} l
join (select deal_id, max(change_time) as last_stage_ts from {{ source('postgres_public', 'deal_changes') }}
      where changed_field_key = 'stage_id' group by 1) s using (deal_id)
where l.changed_field_key = 'lost_reason' and l.change_time < s.last_stage_ts
