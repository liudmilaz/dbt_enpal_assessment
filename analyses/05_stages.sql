-- TABLE public.stages    CLASS: DICTIONARY    ROWS: 9
-- What a row is: one pipeline stage: id and name; the order of stage_id is the order of the funnel steps
-- Sections: 1 all columns, 2 primary key, 3 foreign keys, 4 nulls and not nulls, 5 outliers, 6 descriptive analytics.
-- Findings in short:
--   - primary key: stage_id, given by the task, unique and not null; stage_name is also unique
--   - foreign keys: none; referenced by the stage events in deal_changes (9 of 9 stages used)
--   - nulls: none
--   - outliers: not applicable (9 rows)
--   - descriptive: the spelling of the second stage differs between stages (Qualified lead) and fields (Qualified Lead)
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).
--
-- BUSINESS CONTEXT (company description provided with the task): Enpal is a Berlin-based energy company that sells residential and commercial
-- energy solutions (PV systems, battery storage, EV wallboxes, heat pumps, smart meters) with zero-upfront-cost rental or purchase; over 115,000
-- customers; Enpal Energy is its electricity division. Such a sale is long (consultation, offer, contract, installation, after-sales), so the sales
-- funnel is a core KPI. This export has 1,995 deals and 4,579 activities: a small sample, not Enpal's scale. The role needs governed metric
-- definitions and machine-readable documentation, so every field below is described once, with a link to the system's own documentation.
-- Stages are the steps of the sales pipeline. A stage also carries a win probability and a days-to-rotten setting in Pipedrive; the export has neither,
-- and the funnel order is taken from the order of stage_id.
-- FIELDS USED (only the fields the analysis needs; each with a link to the Pipedrive documentation and whether the docs define it):
--   stage_id: the stage's id ('The ID of the stage').
--     Docs: https://developers.pipedrive.com/docs/api/v1/Stages (documented)
--   stage_name: the stage's name ('The name of the stage'); stages are customised by the CRM admin.
--     Docs: https://developers.pipedrive.com/docs/api/v1/Stages (documented; see also https://support.pipedrive.com/en/article/how-can-i-customize-my-pipeline-stages)

-- =====================================================================
-- 1. All columns
-- =====================================================================
select *
from public.stages;

-- =====================================================================
-- 2. Primary key (given or identified, unique, not null)
-- =====================================================================
-- Primary key declared in the task's init.sql.
select 'stage_id' as primary_key, 'task (init.sql)' as given_by,
       count(*) as n_rows, count(distinct stage_id) as n_distinct,
       count(*) filter (where stage_id is null) as n_null,
       count(*) = count(distinct stage_id) as is_unique,
       count(*) filter (where stage_id is null) = 0 as is_not_null
from public.stages;

-- =====================================================================
-- 3. Foreign keys (nulls, matches, orphans, parent unique)
-- =====================================================================
-- No foreign keys: a dictionary points at nothing. It is referenced by the stage events in deal_changes (see 6a).

-- =====================================================================
-- 4. Nulls and not nulls per column
-- =====================================================================
select key as col, count(*) as n_rows,
       count(*) - count(*) filter (where value = 'null'::jsonb) as n_not_null,
       count(*) filter (where value = 'null'::jsonb) as n_null,
       count(*) filter (where value = '""'::jsonb) as n_blank
from public.stages t, jsonb_each(to_jsonb(t)) group by key order by key;

-- =====================================================================
-- 5. Outliers (IQR rule)
-- =====================================================================
-- Not applicable: 9 rows and no numeric or date column that measures anything.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================

-- 6a. Usage and spelling: deals per stage, and the stage label in fields (stage names differ in spelling for stage 2)
select s.stage_id, s.stage_name, o.label as label_in_fields, s.stage_name = o.label as same_spelling,
       count(distinct d.deal_id) as n_deals_entered
from public.stages s
left join (select (j ->> 'id')::int as id, j ->> 'label' as label from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'stage_id') o on o.id = s.stage_id
left join public.deal_changes d on d.changed_field_key = 'stage_id' and d.new_value::int = s.stage_id
group by 1, 2, 3 order by 1;
