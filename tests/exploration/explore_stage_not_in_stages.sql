-- referential: stage ids in events that do not exist in stages
select d.deal_id, d.new_value as stage_id
from {{ source('postgres_public', 'deal_changes') }} d
left join {{ source('postgres_public', 'stages') }} s on s.stage_id = d.new_value::int
where d.changed_field_key = 'stage_id' and s.stage_id is null
