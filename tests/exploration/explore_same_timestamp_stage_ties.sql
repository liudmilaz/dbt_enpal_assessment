-- record: two stage events for one deal at the same timestamp (ambiguous order)
select deal_id, change_time, count(*) as n
from {{ source('postgres_public', 'deal_changes') }}
where changed_field_key = 'stage_id' group by 1, 2 having count(*) > 1
