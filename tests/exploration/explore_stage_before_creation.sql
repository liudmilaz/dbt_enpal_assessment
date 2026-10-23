-- temporal: a stage event dated before the deal's creation event
select s.deal_id, s.change_time as stage_ts, a.created_at
from {{ source('postgres_public', 'deal_changes') }} s
join (select deal_id, min(change_time) as created_at from {{ source('postgres_public', 'deal_changes') }}
      where changed_field_key = 'add_time' group by 1) a using (deal_id)
where s.changed_field_key = 'stage_id' and s.change_time < a.created_at
