-- referential: deal owner ids (user_id events) that do not exist in users
select d.deal_id, d.new_value as owner_id
from {{ source('postgres_public', 'deal_changes') }} d
left join {{ source('postgres_public', 'users') }} u on u.id = d.new_value::int
where d.changed_field_key = 'user_id' and u.id is null
