-- TABLE public.activity_types    CLASS: DICTIONARY    ROWS: 4
-- What a row is: one activity type; decodes activity.type (a key string) into a name
-- Sections: 1 all columns, 2 primary key, 3 foreign keys, 4 nulls and not nulls, 5 outliers, 6 descriptive analytics.
-- Findings in short:
--   - primary key: id, given by the task, unique and not null; type is also unique and is the column activity references
--   - foreign keys: none; referenced by activity.type (4 of 4 types used)
--   - nulls: none
--   - outliers: not applicable (4 rows, no numeric measure)
--   - descriptive: Follow Up Call is inactive but used by 1,133 activities; After Close Call is not a funnel step
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).
--
-- BUSINESS CONTEXT (company description provided with the task): Enpal is a Berlin-based energy company that sells residential and commercial
-- energy solutions (PV systems, battery storage, EV wallboxes, heat pumps, smart meters) with zero-upfront-cost rental or purchase; over 115,000
-- customers; Enpal Energy is its electricity division. Such a sale is long (consultation, offer, contract, installation, after-sales), so the sales
-- funnel is a core KPI. This export has 1,995 deals and 4,579 activities: a small sample, not Enpal's scale. The role needs governed metric
-- definitions and machine-readable documentation, so every field below is described once, with a link to the system's own documentation.
-- Activity types are configured by the CRM admin (Settings, Company settings, Activities). Here Sales Call 1 and Sales Call 2 are the consultation
-- calls of the funnel; the key string of a type is fixed when it is created.
-- FIELDS USED (only the fields the analysis needs; each with a link to the Pipedrive documentation and whether the docs define it):
--   id: the activity type's id.
--     Docs: https://developers.pipedrive.com/docs/api/v1/ActivityTypes (documented as a path parameter)
--   name: the display name, for example Sales Call 1.
--     Docs: https://developers.pipedrive.com/docs/api/v1/ActivityTypes (documented as a body parameter)
--   type: the key string that activities reference; generated from the name at creation and cannot be changed.
--     Docs: https://developers.pipedrive.com/docs/api/v1/ActivityTypes (documented (key_string))
--   active: whether the type can be chosen for new activities (inactive types stay linked to old activities).
--     Docs: https://developers.pipedrive.com/docs/api/v1/ActivityTypes (active_flag is not described on the official API page; behaviour seen in Settings, Company settings, Activities of the trial account)

-- =====================================================================
-- 1. All columns
-- =====================================================================
select *
from public.activity_types;

-- =====================================================================
-- 2. Primary key (given or identified, unique, not null)
-- =====================================================================
-- Primary key declared in the task's init.sql. type is a second unique column and is the one activities reference.
select 'id' as primary_key, 'task (init.sql)' as given_by,
       count(*) as n_rows, count(distinct id) as n_distinct,
       count(*) filter (where id is null) as n_null,
       count(*) = count(distinct id) as is_unique,
       count(*) filter (where id is null) = 0 as is_not_null
from public.activity_types;

-- =====================================================================
-- 3. Foreign keys (nulls, matches, orphans, parent unique)
-- =====================================================================
-- No foreign keys: a dictionary points at nothing. It is referenced by activity.type (see 6a).

-- =====================================================================
-- 4. Nulls and not nulls per column
-- =====================================================================
select key as col, count(*) as n_rows,
       count(*) - count(*) filter (where value = 'null'::jsonb) as n_not_null,
       count(*) filter (where value = 'null'::jsonb) as n_null,
       count(*) filter (where value = '""'::jsonb) as n_blank
from public.activity_types t, jsonb_each(to_jsonb(t)) group by key order by key;

-- =====================================================================
-- 5. Outliers (IQR rule)
-- =====================================================================
-- Not applicable: 4 rows and no numeric or date column that measures anything.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================

-- 6a. Usage: which types the activities use, and how many are done
select t.id, t.type, t.name, t.active, count(a.activity_id) as n_activities, count(a.activity_id) filter (where a.done) as n_done
from public.activity_types t left join public.activity a on a.type = t.type
group by 1, 2, 3, 4 order by 1;
