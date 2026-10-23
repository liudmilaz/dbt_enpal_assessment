-- TABLE public.fields    CLASS: DICTIONARY    ROWS: 4
-- What a row is: one deal field: key, display name and, for single-option fields, the option list as JSON
-- Sections: 1 all columns, 2 primary key, 3 foreign keys, 4 nulls and not nulls, 5 outliers, 6 descriptive analytics.
-- Findings in short:
--   - primary key: id, given by the task, unique and not null; field_key is also unique and is the column deal_changes references
--   - foreign keys: none; referenced by deal_changes.changed_field_key (4 of 4 keys used)
--   - nulls: only field_value_options, 2 of 4 rows (user_id and add_time have no option list; not applicable)
--   - outliers: not applicable (4 rows)
--   - descriptive: stage labels and lost-reason options sit inside the JSON column
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).
--
-- BUSINESS CONTEXT (company description provided with the task): Enpal is a Berlin-based energy company that sells residential and commercial
-- energy solutions (PV systems, battery storage, EV wallboxes, heat pumps, smart meters) with zero-upfront-cost rental or purchase; over 115,000
-- customers; Enpal Energy is its electricity division. Such a sale is long (consultation, offer, contract, installation, after-sales), so the sales
-- funnel is a core KPI. This export has 1,995 deals and 4,579 activities: a small sample, not Enpal's scale. The role needs governed metric
-- definitions and machine-readable documentation, so every field below is described once, with a link to the system's own documentation.
-- fields is the CRM's field metadata. It turns field keys and option ids into names and labels: the machine-readable context a semantic layer needs.
-- FIELDS USED (only the fields the analysis needs; each with a link to the Pipedrive documentation and whether the docs define it):
--   field_key: the field's key, as used in the change log (default fields have readable keys, custom fields a generated key).
--     Docs: https://developers.pipedrive.com/docs/api/v1/DealFields (keys are mentioned, not defined, on the official page)
--   name: the field's display name (field_name), for example 'Deal created'.
--     Docs: https://developers.pipedrive.com/docs/api/v1/DealFields (documented as field_name)
--   field_value_options: the options of a single-option field: id and label ('The option label'); here stage labels and lost-reason options.
--     Docs: https://developers.pipedrive.com/docs/api/v1/DealFields (documented for single-option (enum) fields)
--   id: the field's id in the export (primary key).
--     Docs: https://developers.pipedrive.com/docs/api/v1/DealFields (not defined on the official page)

-- =====================================================================
-- 1. All columns
-- =====================================================================
select *
from public.fields;

-- =====================================================================
-- 2. Primary key (given or identified, unique, not null)
-- =====================================================================
-- Primary key declared in the task's init.sql. field_key is a second unique column and is the one deal_changes references.
select 'id' as primary_key, 'task (init.sql)' as given_by,
       count(*) as n_rows, count(distinct id) as n_distinct,
       count(*) filter (where id is null) as n_null,
       count(*) = count(distinct id) as is_unique,
       count(*) filter (where id is null) = 0 as is_not_null
from public.fields;

-- =====================================================================
-- 3. Foreign keys (nulls, matches, orphans, parent unique)
-- =====================================================================
-- No foreign keys: a dictionary points at nothing. It is referenced by deal_changes.changed_field_key (see 6b).

-- =====================================================================
-- 4. Nulls and not nulls per column
-- =====================================================================
select key as col, count(*) as n_rows,
       count(*) - count(*) filter (where value = 'null'::jsonb) as n_not_null,
       count(*) filter (where value = 'null'::jsonb) as n_null,
       count(*) filter (where value = '""'::jsonb) as n_blank
from public.fields t, jsonb_each(to_jsonb(t)) group by key order by key;

-- =====================================================================
-- 5. Outliers (IQR rule)
-- =====================================================================
-- Not applicable: 4 rows and no numeric or date column that measures anything.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================

-- 6a. The option lists inside field_value_options (stage labels and lost-reason options)
select f.field_key, f.name, j ->> 'id' as option_id, j ->> 'label' as label
from public.fields f, jsonb_array_elements(f.field_value_options) j
order by f.field_key, (j ->> 'id')::int;

-- 6b. Usage: events per field key in deal_changes
select f.field_key, f.name, count(d.deal_id) as n_events
from public.fields f left join public.deal_changes d on d.changed_field_key = f.field_key
group by 1, 2 order by 3 desc;
