-- TABLE public.users    CLASS: DICTIONARY    ROWS: 1,787
-- What a row is: one user: name and email, current state only (master data); modified is the last change of the user
-- Sections: 1 all columns, 2 primary key, 3 foreign keys, 4 nulls and not nulls, 5 outliers, 6 descriptive analytics.
-- Findings in short:
--   - primary key: id, given by the task, unique and not null; email is NOT a key (4 emails are shared by 2 users each)
--   - foreign keys: none; referenced by activity.assigned_to_user and the owner events (1,757 of 1,787 users referenced)
--   - nulls: none
--   - outliers: none in modified
--   - descriptive: modified spans 2024-01-02 to 2024-10-28; 30 users are never referenced
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).
--
-- BUSINESS CONTEXT (company description provided with the task): Enpal is a Berlin-based energy company that sells residential and commercial
-- energy solutions (PV systems, battery storage, EV wallboxes, heat pumps, smart meters) with zero-upfront-cost rental or purchase; over 115,000
-- customers; Enpal Energy is its electricity division. Such a sale is long (consultation, offer, contract, installation, after-sales), so the sales
-- funnel is a core KPI. This export has 1,995 deals and 4,579 activities: a small sample, not Enpal's scale. The role needs governed metric
-- definitions and machine-readable documentation, so every field below is described once, with a link to the system's own documentation.
-- Users are the sales and service staff who own deals and activities. The table is current state only, so any metric by owner over time needs the
-- owner events in deal_changes.
-- FIELDS USED (only the fields the analysis needs; each with a link to the Pipedrive documentation and whether the docs define it):
--   id: the user's id ('The ID of the user').
--     Docs: https://developers.pipedrive.com/docs/api/v1/Users (documented as a path parameter)
--   email: the user's email ('The email of the user').
--     Docs: https://developers.pipedrive.com/docs/api/v1/Users (documented; not unique in the export (4 shared emails))
--   modified: the last change of the user record.
--     Docs: https://developers.pipedrive.com/docs/api/v1/Users (not documented on the official page)

-- =====================================================================
-- 1. All columns
-- =====================================================================
select *
from public.users;

-- =====================================================================
-- 2. Primary key (given or identified, unique, not null)
-- =====================================================================
-- Primary key declared in the task's init.sql. email looks like a key but is not unique (see 6a).
select 'id' as primary_key, 'task (init.sql)' as given_by,
       count(*) as n_rows, count(distinct id) as n_distinct,
       count(*) filter (where id is null) as n_null,
       count(*) = count(distinct id) as is_unique,
       count(*) filter (where id is null) = 0 as is_not_null
from public.users;

-- =====================================================================
-- 3. Foreign keys (nulls, matches, orphans, parent unique)
-- =====================================================================
-- No foreign keys: a dictionary points at nothing. It is referenced by activity.assigned_to_user and by the owner events in deal_changes (see 6b).

-- =====================================================================
-- 4. Nulls and not nulls per column
-- =====================================================================
select key as col, count(*) as n_rows,
       count(*) - count(*) filter (where value = 'null'::jsonb) as n_not_null,
       count(*) filter (where value = 'null'::jsonb) as n_null,
       count(*) filter (where value = '""'::jsonb) as n_blank
from public.users t, jsonb_each(to_jsonb(t)) group by key order by key;

-- =====================================================================
-- 5. Outliers (IQR rule)
-- =====================================================================
-- 5a. modified as days since 1970
with t as (select extract(epoch from modified) / 86400 as x from public.users),
b as (select percentile_cont(0.25) within group (order by x) as q1, percentile_cont(0.75) within group (order by x) as q3 from t)
select count(*) as n_values, round(q1::numeric, 1) as q1, round(q3::numeric, 1) as q3,
       round((q1 - 1.5 * (q3 - q1))::numeric, 1) as lower_fence, round((q3 + 1.5 * (q3 - q1))::numeric, 1) as upper_fence,
       count(*) filter (where x < q1 - 1.5 * (q3 - q1) or x > q3 + 1.5 * (q3 - q1)) as n_outliers,
       round(min(x)::numeric, 1) as min_value, round(max(x)::numeric, 1) as max_value
from t, b group by q1, q3;

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================

-- 6a. Emails shared by more than one user (email is not a key)
select email, count(*) as n_users, array_agg(id order by id) as user_ids
from public.users group by email having count(*) > 1 order by email;

-- 6b. How many users are referenced by the facts
select count(*) as n_users,
       count(*) filter (where u.id in (select assigned_to_user from public.activity) or u.id in (select new_value::int from public.deal_changes where changed_field_key = 'user_id')) as n_referenced
from public.users u;

-- 6c. Users by month of the last change
select to_char(date_trunc('month', modified), 'YYYY-MM') as month, count(*) as n_users,
       repeat('#', (30.0 * count(*) / max(count(*)) over ())::int) as bar
from public.users group by 1 order by 1;
