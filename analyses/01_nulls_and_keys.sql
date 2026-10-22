-- Question: which columns contain NULLs or blanks, and what are the primary and foreign keys of the six tables, declared or not?
-- Part 1 (nulls): 24 columns in six tables. Only fields.field_value_options has NULLs (2 of 4 rows: the user_id and add_time fields have
--           no option list; not applicable, not missing). No blank strings anywhere.
-- Part 2 (keys): Declared primary keys: activity_types.id, fields.id, stages.stage_id, users.id. None on activity or deal_changes; no
--           foreign key declared anywhere. deal_changes is unique only on (deal_id, changed_field_key, change_time); deal_id repeats
--           (7.7 events per deal), so there is no deal master table. activity_id is NOT unique (4,568 of 4,579), the full row is.
--           Alternate keys that are the ones referenced: activity_types.type and fields.field_key. Foreign key candidates hold 100%
--           (assigned user, activity type, owner, stage, lost reason, event key) except activity.deal_id -> deal_changes.deal_id (8 of 4,579).
-- Consequence: not_null on every key and column except fields.field_value_options (nullable by design, do not coalesce); key register in
--              docs/findings.md drives unique + not_null on every key, relationships on every foreign key that holds, a surrogate key for
--              activity, a composite key for deal_changes, and activity.deal_id documented as an unrelated key (known failure).
-- Method:   Part 1 uses to_jsonb(t) + jsonb_each to list every column without naming it (Postgres). Run one statement at a time.

-- ===== Part 1: nulls and blanks per column =====
select tbl, col, n_rows, n_null, n_blank,
       round(100.0 * n_null / n_rows, 1) as pct_null
from (
  select 'deal_changes' as tbl, key as col, count(*) as n_rows,
         count(*) filter (where value = 'null'::jsonb) as n_null, count(*) filter (where value = '""'::jsonb) as n_blank
  from public.deal_changes t, jsonb_each(to_jsonb(t)) group by key
  union all
  select 'activity', key, count(*), count(*) filter (where value = 'null'::jsonb), count(*) filter (where value = '""'::jsonb)
  from public.activity t, jsonb_each(to_jsonb(t)) group by key
  union all
  select 'activity_types', key, count(*), count(*) filter (where value = 'null'::jsonb), count(*) filter (where value = '""'::jsonb)
  from public.activity_types t, jsonb_each(to_jsonb(t)) group by key
  union all
  select 'users', key, count(*), count(*) filter (where value = 'null'::jsonb), count(*) filter (where value = '""'::jsonb)
  from public.users t, jsonb_each(to_jsonb(t)) group by key
  union all
  select 'stages', key, count(*), count(*) filter (where value = 'null'::jsonb), count(*) filter (where value = '""'::jsonb)
  from public.stages t, jsonb_each(to_jsonb(t)) group by key
  union all
  select 'fields', key, count(*), count(*) filter (where value = 'null'::jsonb), count(*) filter (where value = '""'::jsonb)
  from public.fields t, jsonb_each(to_jsonb(t)) group by key
) x
order by tbl, col;

-- ===== Part 2: primary and foreign keys =====
-- 1. constraints the database declares
select conrelid::regclass as tbl, case contype when 'p' then 'primary key' when 'f' then 'foreign key' when 'u' then 'unique' else contype::text end as kind,
       pg_get_constraintdef(oid) as definition
from pg_constraint where connamespace = 'public'::regnamespace and contype in ('p', 'f', 'u') order by 1;

-- 2. primary key candidates: a key has n = distinct and no NULLs (NULLs were checked in 01)
select 'deal_changes (deal_id)' as candidate, count(*) as n_rows, count(distinct deal_id) as n_distinct from public.deal_changes
union all select 'deal_changes (deal_id, changed_field_key, change_time)', count(*), count(distinct (deal_id, changed_field_key, change_time)) from public.deal_changes
union all select 'activity (activity_id)', count(*), count(distinct activity_id) from public.activity
union all select 'activity (all six columns)', count(*), count(distinct (activity_id, type, assigned_to_user, deal_id, done, due_to)) from public.activity
union all select 'activity_types (id)', count(*), count(distinct id) from public.activity_types
union all select 'activity_types (type)', count(*), count(distinct type) from public.activity_types
union all select 'users (id)', count(*), count(distinct id) from public.users
union all select 'users (email)', count(*), count(distinct email) from public.users
union all select 'stages (stage_id)', count(*), count(distinct stage_id) from public.stages
union all select 'stages (stage_name)', count(*), count(distinct stage_name) from public.stages
union all select 'fields (id)', count(*), count(distinct id) from public.fields
union all select 'fields (field_key)', count(*), count(distinct field_key) from public.fields;

-- 3. foreign key candidates: share of child rows whose value exists in the parent key (inclusion test)
select 'activity.assigned_to_user -> users.id' as fk, count(*) as child_rows, count(*) filter (where p.id is not null) as matched
from public.activity c left join public.users p on p.id = c.assigned_to_user
union all select 'activity.type -> activity_types.type', count(*), count(*) filter (where p.type is not null)
from public.activity c left join public.activity_types p on p.type = c.type
union all select 'activity.deal_id -> deal_changes.deal_id', count(*), count(*) filter (where p.deal_id is not null)
from public.activity c left join (select distinct deal_id from public.deal_changes) p on p.deal_id = c.deal_id
union all select 'deal_changes.changed_field_key -> fields.field_key', count(*), count(*) filter (where p.field_key is not null)
from public.deal_changes c left join public.fields p on p.field_key = c.changed_field_key
union all select 'deal_changes.new_value [user_id] -> users.id', count(*), count(*) filter (where p.id is not null)
from public.deal_changes c left join public.users p on p.id = c.new_value::int where c.changed_field_key = 'user_id'
union all select 'deal_changes.new_value [stage_id] -> stages.stage_id', count(*), count(*) filter (where p.stage_id is not null)
from public.deal_changes c left join public.stages p on p.stage_id = c.new_value::int where c.changed_field_key = 'stage_id'
union all select 'deal_changes.new_value [lost_reason] -> fields option id', count(*), count(*) filter (where o.id is not null)
from public.deal_changes c
left join (select j ->> 'id' as id from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'lost_reason') o on o.id = c.new_value
where c.changed_field_key = 'lost_reason';

-- 4. is deal_id a key of a deal table? (no: it repeats per event, and there is no deals table)
select count(*) as events, count(distinct deal_id) as deals, round(count(*)::numeric / count(distinct deal_id), 1) as events_per_deal from public.deal_changes;
