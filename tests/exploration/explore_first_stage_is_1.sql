-- business logic: every deal should start at stage 1
with first_stage as (
  select deal_id, (array_agg(new_value::int order by change_time))[1] as first_stage
  from {{ source('postgres_public', 'deal_changes') }}
  where changed_field_key = 'stage_id' group by 1
)
select * from first_stage where first_stage <> 1
