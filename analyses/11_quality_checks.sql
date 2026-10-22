-- Question: which data-quality rules does the raw data break?
-- Finding:  0 duplicate events, 0 ties, 0 nulls, 0 orphan owners/assignees, 0 stage events before creation;
--           breaks: 5 deals with two add_time, 4 lost_reason before last stage, 8 users sharing 4 emails, 11 repeated activity_ids.
-- Consequence: tests per class in the staging YAML (see eda-findings-to-dbt-tests); known upstream defects at severity warn.
select 'duplicate events' as check_name, count(*) as violations from (select 1 from public.deal_changes group by deal_id, changed_field_key, change_time having count(*) > 1) x
union all select 'deals with two add_time', count(*) from (select 1 from public.deal_changes where changed_field_key = 'add_time' group by deal_id having count(*) > 1) x
union all select 'stage events before add_time', count(*) from public.deal_changes s join (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1) a using (deal_id) where s.changed_field_key = 'stage_id' and s.change_time < a.ts
union all select 'owner ids not in users', count(*) from public.deal_changes d left join public.users u on u.id = d.new_value::int where d.changed_field_key = 'user_id' and u.id is null
union all select 'users sharing an email', count(*) from public.users where email in (select email from public.users group by 1 having count(*) > 1);
