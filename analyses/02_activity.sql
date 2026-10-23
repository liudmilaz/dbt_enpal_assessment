-- TABLE public.activity    CLASS: FACT    ROWS: 4,579
-- What a row is: one scheduled activity (a call or meeting planned for a time); timestamp due_to, 2024-01-01 to 2024-09-13; done says whether it was marked done
-- Sections: 1 all columns, 2 primary key, 3 foreign keys, 4 nulls and not nulls, 5 outliers, 6 descriptive analytics.
-- Findings in short:
--   - primary key: none given by the task; activity_id is the intended key but is NOT unique (4,568 distinct of 4,579); the full row is unique, so the model needs a surrogate key
--   - foreign keys: assigned user and type hold at 100% with 0 nulls; deal_id fails (8 of 4,579 rows match; the parent column repeats)
--   - nulls: none
--   - outliers: none in due_to
--   - descriptive: four types about 25% each, about half done; 11 activity_ids are collisions of unrelated activities; activities and deal creations share one window
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).
--
-- BUSINESS CONTEXT (company description provided with the task): Enpal is a Berlin-based energy company that sells residential and commercial
-- energy solutions (PV systems, battery storage, EV wallboxes, heat pumps, smart meters) with zero-upfront-cost rental or purchase; over 115,000
-- customers; Enpal Energy is its electricity division. Such a sale is long (consultation, offer, contract, installation, after-sales), so the sales
-- funnel is a core KPI. This export has 1,995 deals and 4,579 activities: a small sample, not Enpal's scale. The role needs governed metric
-- definitions and machine-readable documentation, so every field below is described once, with a link to the system's own documentation.
-- Sales Call 1 and Sales Call 2 are the consultation calls behind funnel steps 2.1 and 3.1; Follow Up Call and After Close Call are not funnel steps.
-- A planned call (due_to) is not a held call (done): the metric definition must say which one counts.
-- FIELDS USED (only the fields the analysis needs; each with a link to the Pipedrive documentation and whether the docs define it):
--   activity_id: the activity's id.
--     Docs: https://developers.pipedrive.com/docs/api/v1/Activities#getActivity (documented ('The ID of the activity'); repeats in the export)
--   type: the activity type, by its key string ('The type of the activity').
--     Docs: https://developers.pipedrive.com/docs/api/v1/Activities#addActivity (documented; the key string comes from the activity type, see https://developers.pipedrive.com/docs/api/v1/ActivityTypes)
--   assigned_to_user: the user the activity belongs to ('The ID of the user who owns the activity', owner_id).
--     Docs: https://developers.pipedrive.com/docs/api/v1/Activities#addActivity (documented under the name owner_id; assigned_to_user is the export's name)
--   deal_id: the deal linked to the activity ('The ID of the deal linked to the activity').
--     Docs: https://developers.pipedrive.com/docs/api/v1/Activities#addActivity (documented)
--   done: 'Whether the activity is marked as done or not'.
--     Docs: https://developers.pipedrive.com/docs/api/v1/Activities#addActivity (documented)
--   due_to: the planned date and time (the API has due_date and due_time: 'The due date / time of the activity').
--     Docs: https://developers.pipedrive.com/docs/api/v1/Activities#addActivity (documented as two fields; the export merges them into one timestamp)

-- =====================================================================
-- 1. All columns
-- =====================================================================
select *
from public.activity;

-- =====================================================================
-- 2. Primary key (given or identified, unique, not null)
-- =====================================================================
-- No key is declared for this table. activity_id is the intended key but it repeats (see 6c); this is the check that proves it.
select 'activity_id' as primary_key, 'identified' as given_by,
       count(*) as n_rows, count(distinct activity_id) as n_distinct,
       count(*) filter (where activity_id is null) as n_null,
       count(*) = count(distinct activity_id) as is_unique,
       count(*) filter (where activity_id is null) = 0 as is_not_null
from public.activity;

-- The full row is unique, which is why a surrogate key (hash of all columns) works.
select count(*) as n_rows, count(distinct (activity_id, type, assigned_to_user, deal_id, done, due_to)) as n_distinct_full_rows from public.activity;

-- =====================================================================
-- 3. Foreign keys (nulls, matches, orphans, parent unique)
-- =====================================================================
-- Foreign keys of this table. None is declared in the task; these are the column pairs found by value overlap.
-- activity.type points at a unique column that is not the parent's primary key (activity_types.type).
-- deal_id: the parent column (deal_changes.deal_id) repeats per event, so it is not a valid parent key, and only 8 rows match.
select fk, n_child_rows, n_null, n_matched, n_child_rows - n_null - n_matched as n_orphans, parent_is_unique
from (
  select 'activity.assigned_to_user -> users.id' as fk, count(*) as n_child_rows, count(*) filter (where c.assigned_to_user is null) as n_null, count(p.id) as n_matched,
         (select count(*) = count(distinct id) from public.users) as parent_is_unique
  from public.activity c left join public.users p on p.id = c.assigned_to_user
  union all
  select 'activity.type -> activity_types.type', count(*), count(*) filter (where c.type is null), count(p.type),
         (select count(*) = count(distinct type) from public.activity_types)
  from public.activity c left join public.activity_types p on p.type = c.type
  union all
  select 'activity.deal_id -> deal_changes.deal_id', count(*), count(*) filter (where c.deal_id is null), count(p.deal_id),
         (select count(*) = count(distinct deal_id) from public.deal_changes)
  from public.activity c left join (select distinct deal_id from public.deal_changes) p on p.deal_id = c.deal_id
) f;

-- =====================================================================
-- 4. Nulls and not nulls per column
-- =====================================================================
select key as col, count(*) as n_rows,
       count(*) - count(*) filter (where value = 'null'::jsonb) as n_not_null,
       count(*) filter (where value = 'null'::jsonb) as n_null,
       count(*) filter (where value = '""'::jsonb) as n_blank
from public.activity t, jsonb_each(to_jsonb(t)) group by key order by key;

-- =====================================================================
-- 5. Outliers (IQR rule)
-- =====================================================================
-- 5a. due_to as days since 1970 (a plausibility check on the planned dates)
with t as (select extract(epoch from due_to) / 86400 as x from public.activity),
b as (select percentile_cont(0.25) within group (order by x) as q1, percentile_cont(0.75) within group (order by x) as q3 from t)
select count(*) as n_values, round(q1::numeric, 1) as q1, round(q3::numeric, 1) as q3,
       round((q1 - 1.5 * (q3 - q1))::numeric, 1) as lower_fence, round((q3 + 1.5 * (q3 - q1))::numeric, 1) as upper_fence,
       count(*) filter (where x < q1 - 1.5 * (q3 - q1) or x > q3 + 1.5 * (q3 - q1)) as n_outliers,
       round(min(x)::numeric, 1) as min_value, round(max(x)::numeric, 1) as max_value
from t, b group by q1, q3;

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================

-- 6a. Activity types and the done flag
-- Question: what activity types exist and how many are done?
-- Finding:  four types (meeting, sc_2, follow_up, after_close_call), about 1,100 each, about 50% done; 11 activity_ids appear twice with different content.
-- Consequence: steps 2.1 / 3.1 use meeting and sc_2 only; surrogate key for activity; source uniqueness test at warn.
select type, done, count(*) as n from public.activity group by 1, 2 order by 1, 2;
-- repeated activity ids
select activity_id, count(*) as n from public.activity group by 1 having count(*) > 1 order by 1;

-- 6b. Can activities be joined to deals
-- Question: can activities be joined to deals?
-- Finding:  only 8 of 4,572 distinct activity deal_ids exist in deal_changes; both id ranges are 6 digits, so random overlap is about as large.
-- Consequence: calls cannot be attributed to deals; count Sales Call 1/2 by due_to month and raise the question with Enpal.
select count(*) as n_activity_deals,
       sum(case when d.deal_id is not null then 1 else 0 end) as n_found_in_deal_changes
from (select distinct deal_id from public.activity) a
left join (select distinct deal_id from public.deal_changes) d using (deal_id);

-- 6c. The 11 repeated activity_ids are collisions of unrelated activities, not duplicates: deal, user and due date differ in every pair.
-- (4,579 ids from a 900,000-wide range predict about 11.6 chance collisions; 11 were observed.)
select activity_id, count(*) as n, count(distinct deal_id) as n_deals, count(distinct assigned_to_user) as n_users, count(distinct type) as n_types, count(distinct due_to) as n_due_dates
from public.activity group by activity_id having count(*) > 1 order by activity_id;

-- 6d. Shape of the data: categorical frequency with cumulative share
select type, count(*) as n, round(100.0 * count(*) / sum(count(*)) over (), 1) as pct,
       round(100.0 * sum(count(*)) over (order by count(*) desc, type rows unbounded preceding) / sum(count(*)) over (), 1) as cum_pct
from activity group by type order by n desc;

-- 6d. distribution over time (monthly counts + share of peak)
select date_trunc('month', due_to)::date as month, count(*) as n,
       repeat('#', (30.0 * count(*) / max(count(*)) over ())::int) as bar
from activity group by 1 order by 1 limit 4;

-- 6d. compare a distribution across groups (type x month)
select to_char(date_trunc('month', due_to), 'YYYY-MM') as month,
       count(*) filter (where type = 'meeting') as meeting, count(*) filter (where type = 'sc_2') as sc_2,
       count(*) filter (where done) as done_n, round(100.0 * count(*) filter (where done) / count(*), 1) as done_pct
from activity group by 1 order by 1 limit 3;
