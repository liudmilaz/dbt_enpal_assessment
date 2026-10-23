-- OVERALL DATA QUALITY FINDINGS for the six raw Pipedrive tables.
-- One result row per check. violations = number of rows (or deals, ids, users: see the finding text) that break the rule.
-- result: pass (0 violations), flag (violations found) or info (expected or descriptive, not an error).
-- class: field (nulls, domain, spelling), record (keys, duplicates), referential (foreign keys), business logic (sequence, meaning), coverage.
-- severity: proposed dbt test severity. error = our own pipeline would be wrong; warn = known upstream defect, fixed in staging; info = documented only.
-- The detail queries for each finding are in the per-table files 01 to 06 (section named in the last column).
--
-- Not queryable (not in the export): deal status (open, won, lost), pipeline, value, person and organization, who changed a field,
-- the previous value, and when an activity was completed. See docs/findings.md (Pipedrive terms).

select row_number() over (order by case class when 'record' then 1 when 'field' then 2 when 'referential' then 3 when 'business logic' then 4 else 5 end, no) as no,
       tbl, class, finding, violations, severity,
       case when violations = 0 then 'pass' when severity = 'info' then 'info' else 'flag' end as result,
       detail_in
from (
  -- ---------- record: keys and duplicates ----------
  select 1 as no, 'activity' as tbl, 'record' as class, 'full-row duplicates (a table loaded twice)' as finding,
         (select count(*) - count(distinct (activity_id, type, assigned_to_user, deal_id, done, due_to)) from public.activity) as violations,
         'error' as severity, '02_activity 2' as detail_in
  union all select 2, 'deal_changes', 'record', 'duplicate events on (deal_id, field key, time)',
         (select count(*) - count(distinct (deal_id, changed_field_key, change_time)) from public.deal_changes), 'error', '01_deal_changes 2'
  union all select 3, 'activity', 'record', 'activity_id repeated (ids; collisions of unrelated activities)',
         (select count(*) from (select activity_id from public.activity group by 1 having count(*) > 1) x), 'warn', '02_activity 6c'
  union all select 4, 'users', 'record', 'rows sharing an email (4 emails, 2 users each)',
         (select count(*) from public.users where email in (select email from public.users group by 1 having count(*) > 1)), 'warn', '04_users 6a'
  union all select 5, 'deal_changes', 'record', 'deals with two creation events (add_time)',
         (select count(*) from (select 1 from public.deal_changes where changed_field_key = 'add_time' group by deal_id having count(*) > 1) x), 'warn', '01_deal_changes 6d'
  union all select 6, 'deal_changes', 'record', 'deals with two lost_reason events',
         (select count(*) from (select 1 from public.deal_changes where changed_field_key = 'lost_reason' group by deal_id having count(*) > 1) x), 'warn', '01_deal_changes 6e'
  union all select 7, 'deal_changes', 'record', 'same-timestamp stage events of one deal (ambiguous order)',
         (select count(*) from (select 1 from public.deal_changes where changed_field_key = 'stage_id' group by deal_id, change_time having count(*) > 1) x), 'error', '01_deal_changes 6c'
  -- ---------- field: nulls, domain, spelling ----------
  union all select 8, 'all', 'field', 'NULLs in required columns (all tables, fields.field_value_options excluded)',
         (select count(*) from public.deal_changes t where not (t is not null)) + (select count(*) from public.activity t where not (t is not null))
         + (select count(*) from public.activity_types t where not (t is not null)) + (select count(*) from public.users t where not (t is not null))
         + (select count(*) from public.stages t where not (t is not null))
         + (select count(*) from public.fields where id is null or field_key is null or name is null), 'error', 'all tables, section 4'
  union all select 9, 'fields', 'field', 'NULL field_value_options (expected: user_id and add_time have no option list)',
         (select count(*) from public.fields where field_value_options is null), 'info', '06_fields 4'
  union all select 10, 'stages', 'field', 'stage names spelled differently from the labels in fields (Qualified lead vs Qualified Lead)',
         (select count(*) from public.stages s join (select (j ->> 'id')::int as id, j ->> 'label' as label from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'stage_id') o on o.id = s.stage_id where s.stage_name <> o.label), 'info', '05_stages 6a'
  union all select 11, 'deal_changes', 'field', 'stage ids outside 1 to 9',
         (select count(*) from public.deal_changes where changed_field_key = 'stage_id' and new_value::int not between 1 and 9), 'error', '01_deal_changes 3'
  -- ---------- referential: foreign keys ----------
  union all select 12, 'deal_changes', 'referential', 'owner ids (user_id events) missing from users',
         (select count(*) from public.deal_changes c left join public.users u on u.id = c.new_value::int where c.changed_field_key = 'user_id' and u.id is null), 'error', '01_deal_changes 3'
  union all select 13, 'deal_changes', 'referential', 'stage ids missing from stages',
         (select count(*) from public.deal_changes c left join public.stages s on s.stage_id = c.new_value::int where c.changed_field_key = 'stage_id' and s.stage_id is null), 'error', '01_deal_changes 3'
  union all select 14, 'activity', 'referential', 'assigned users missing from users',
         (select count(*) from public.activity a left join public.users u on u.id = a.assigned_to_user where u.id is null), 'error', '02_activity 3'
  union all select 15, 'activity', 'referential', 'activity types missing from activity_types',
         (select count(*) from public.activity a left join public.activity_types t on t.type = a.type where t.type is null), 'error', '02_activity 3'
  union all select 16, 'activity', 'referential', 'activity rows whose deal_id is not in deal_changes (no deals table; ids look unrelated)',
         (select count(*) from public.activity a where not exists (select 1 from public.deal_changes d where d.deal_id = a.deal_id)), 'warn', '02_activity 3, 6b'
  -- ---------- business logic: sequence and meaning ----------
  union all select 17, 'deal_changes', 'business logic', 'deals not starting at stage 1',
         (select count(*) from (select deal_id, (array_agg(new_value::int order by change_time))[1] as first_stage from public.deal_changes where changed_field_key = 'stage_id' group by 1) x where first_stage <> 1), 'error', '01_deal_changes 6c'
  union all select 18, 'deal_changes', 'business logic', 'stage events dated before the deal was created',
         (select count(*) from public.deal_changes s join (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1) a using (deal_id) where s.changed_field_key = 'stage_id' and s.change_time < a.ts), 'error', '01_deal_changes 6d'
  union all select 19, 'deal_changes', 'business logic', 'lost_reason dated before the last stage event (deals)',
         (select count(distinct l.deal_id) from public.deal_changes l join (select deal_id, max(change_time) as ts from public.deal_changes where changed_field_key = 'stage_id' group by 1) s using (deal_id) where l.changed_field_key = 'lost_reason' and l.change_time < s.ts), 'warn', '01_deal_changes 6e'
  union all select 20, 'deal_changes', 'business logic', 'stage moves that skip a stage',
         (select count(*) from (select new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as mv from public.deal_changes where changed_field_key = 'stage_id') x where mv > 1), 'info', '01_deal_changes 6c'
  union all select 21, 'deal_changes', 'business logic', 'stage moves that go backward',
         (select count(*) from (select new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as mv from public.deal_changes where changed_field_key = 'stage_id') x where mv < 0), 'info', '01_deal_changes 6c'
  union all select 22, 'deal_changes', 'business logic', 'stage moves that repeat the same stage',
         (select count(*) from (select new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as mv from public.deal_changes where changed_field_key = 'stage_id') x where mv = 0), 'info', '01_deal_changes 6c'
  union all select 23, 'deal_changes', 'business logic', 'deals that reached the last stage but also carry a lost_reason (reason is not a deal outcome)',
         (select count(distinct m.deal_id) from (select deal_id, max(new_value::int) as mx from public.deal_changes where changed_field_key = 'stage_id' group by 1) m join public.deal_changes l on l.deal_id = m.deal_id and l.changed_field_key = 'lost_reason' where m.mx = 9), 'info', '01_deal_changes 6e'
  union all select 26, 'deal_changes', 'business logic', 'deals lost as Duplicate Entry (duplicates kept as deals, not merged)',
         (select count(distinct l.deal_id) from public.deal_changes l where l.changed_field_key = 'lost_reason' and l.new_value = '5'), 'warn', '01_deal_changes 6i'
  union all select 27, 'deal_changes', 'business logic', 'Duplicate Entry deals that reached Closing or later',
         (select count(distinct l.deal_id) from public.deal_changes l join (select deal_id, max(new_value::int) as mx from public.deal_changes where changed_field_key = 'stage_id' group by 1) m on m.deal_id = l.deal_id where l.changed_field_key = 'lost_reason' and l.new_value = '5' and m.mx >= 6), 'warn', '01_deal_changes 6i'
  union all select 28, 'deal_changes', 'business logic', 'Unreachable Customer deals that reached Needs Assessment or later',
         (select count(distinct l.deal_id) from public.deal_changes l join (select deal_id, max(new_value::int) as mx from public.deal_changes where changed_field_key = 'stage_id' group by 1) m on m.deal_id = l.deal_id where l.changed_field_key = 'lost_reason' and l.new_value = '3' and m.mx >= 3), 'warn', '01_deal_changes 6i'
  -- ---------- coverage ----------
  union all select 24, 'activity', 'coverage', 'months with stage events but no activities (activities end 2024-09-13)',
         (select count(*) from (select distinct date_trunc('month', change_time) as m from public.deal_changes where changed_field_key = 'stage_id') s where m not in (select date_trunc('month', due_to) from public.activity)), 'info', '02_activity 6d'
  union all select 25, 'users', 'coverage', 'users never referenced by an activity or an owner event',
         (select count(*) from public.users u where u.id not in (select assigned_to_user from public.activity) and u.id not in (select new_value::int from public.deal_changes where changed_field_key = 'user_id')), 'info', '04_users 6b'
) f
order by no;
