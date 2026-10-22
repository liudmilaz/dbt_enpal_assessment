-- Question: how big is each source and what dates does it cover?
-- Finding:  deal_changes 15,406 rows / 1,995 deals, 2024-01-01 to 2025-03-11; activity 4,579 rows, 2024-01-01 to 2024-09-13;
--           users 1,787; stages 9; fields 4; activity_types 4. A double docker load would show activity = 9,158.
-- Consequence: counts are the reference for the loader test; report window starts 2024-01.
select 'deal_changes' as tbl, count(*) as n_rows, min(change_time)::date as first_dt, max(change_time)::date as last_dt from public.deal_changes
union all select 'activity', count(*), min(due_to)::date, max(due_to)::date from public.activity
union all select 'users', count(*), min(modified)::date, max(modified)::date from public.users
union all select 'stages', count(*), null, null from public.stages
union all select 'fields', count(*), null, null from public.fields
union all select 'activity_types', count(*), null, null from public.activity_types;
