-- TABLE public.deal_changes    CLASS: FACT    ROWS: 15,406
-- What a row is: one change of one field of one deal (an event log); timestamp change_time, 2024-01-01 to 2025-03-11
-- Sections: 1 all columns, 2 primary key, 3 foreign keys, 4 nulls and not nulls, 5 outliers, 6 descriptive analytics.
-- Findings in short:
--   - primary key: none given by the task; (deal_id, changed_field_key, change_time) is unique and not null; deal_id repeats (7.7 events per deal), there is no deals table
--   - foreign keys: all hold at 100% with 0 nulls (field key, owner, stage, lost reason)
--   - nulls: none
--   - outliers: none in the gaps between stage events; 12 deals above the fence in the creation lag (76 to 83 days), all plausible
--   - descriptive: 4 field keys; 84% of deals skip a stage; 5 deals carry two lifecycles; every deal has a lost_reason; stage timing is flat (looks generated)
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).
--
-- BUSINESS CONTEXT (company description provided with the task): Enpal is a Berlin-based energy company that sells residential and commercial
-- energy solutions (PV systems, battery storage, EV wallboxes, heat pumps, smart meters) with zero-upfront-cost rental or purchase; over 115,000
-- customers; Enpal Energy is its electricity division. Such a sale is long (consultation, offer, contract, installation, after-sales), so the sales
-- funnel is a core KPI. This export has 1,995 deals and 4,579 activities: a small sample, not Enpal's scale. The role needs governed metric
-- definitions and machine-readable documentation, so every field below is described once, with a link to the system's own documentation.
-- Reading of the funnel in Enpal's business (interpretation, to confirm with Enpal): Lead Generation = a household shows interest; Qualified Lead = fits
-- a product; Sales Call 1 / 2 = consultation calls; Needs Assessment = roof, consumption and budget; Proposal/Quote Preparation = system design and
-- offer (rental or purchase); Negotiation; Closing = contract signed; Implementation/Onboarding = installation and grid connection; Follow-up/Customer
-- Success = after-sales; Renewal/Expansion = add-ons (storage, wallbox, heat pump, electricity). Each stage needs one documented metric definition.
-- FIELDS USED (only the fields the analysis needs; each with a link to the Pipedrive documentation and whether the docs define it):
--   deal_id: the deal the change belongs to.
--     Docs: https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog (documented as the path parameter of the deal changelog endpoint)
--   changed_field_key: key of the field that changed (field_key of a changelog entry).
--     Docs: https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog (the endpoint is documented but its response fields are not defined on the official page; third-party reference (unofficial): https://developers.qodex.ai/pipedrive-api-collection/pipedrive-api-v1-2/deals-6/list-updates-about-deal-field-values-1)
--   change_time: when the change happened (time of a changelog entry).
--     Docs: https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog (not defined on the official page; the export has one timestamp per change)
--   new_value: value after the change: an id for stage_id and user_id, an option id for lost_reason, a timestamp for add_time.
--     Docs: https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog (new_value is listed by third-party references only; there is no previous value and no author in the export)
--   key stage_id: the stage the deal moved into: 'The ID of the deal stage'.
--     Docs: https://developers.pipedrive.com/docs/api/v1/Deals#addDeal (documented)
--   key user_id: the deal owner: 'The ID of the user who owns the deal' (the API calls the field owner_id).
--     Docs: https://developers.pipedrive.com/docs/api/v1/Deals#addDeal (documented under the name owner_id)
--   key add_time: when the deal was created ('Deal created' in the UI under Settings, Data fields).
--     Docs: https://developers.pipedrive.com/docs/api/v1/Deals#getDeals (add_time appears only as a sort field in the docs, not defined)
--   key lost_reason: 'The reason for losing the deal'; a predefined list set by an admin (Company settings, Lost reasons) or free text.
--     Docs: https://support.pipedrive.com/en/article/lost-reasons (documented; also https://developers.pipedrive.com/docs/api/v1/Deals#addDeal)

-- =====================================================================
-- 1. All columns
-- =====================================================================
select *
from public.deal_changes;

-- =====================================================================
-- 2. Primary key (given or identified, unique, not null)
-- =====================================================================
-- No key is declared for this table. This composite is the smallest column set that is unique; deal_id alone repeats.
select '(deal_id, changed_field_key, change_time)' as primary_key, 'identified' as given_by,
       count(*) as n_rows, count(distinct (deal_id, changed_field_key, change_time)) as n_distinct,
       count(*) filter (where deal_id is null or changed_field_key is null or change_time is null) as n_null,
       count(*) = count(distinct (deal_id, changed_field_key, change_time)) as is_unique,
       count(*) filter (where deal_id is null or changed_field_key is null or change_time is null) = 0 as is_not_null
from public.deal_changes;

-- =====================================================================
-- 3. Foreign keys (nulls, matches, orphans, parent unique)
-- =====================================================================
-- Foreign keys of this table. None is declared in the task; these are the column pairs found by value overlap.
-- new_value is a conditional foreign key: its parent depends on changed_field_key. deal_id has no parent table (no deals table exists).
select fk, n_child_rows, n_null, n_matched, n_child_rows - n_null - n_matched as n_orphans, parent_is_unique
from (
  select 'deal_changes.changed_field_key -> fields.field_key' as fk, count(*) as n_child_rows, count(*) filter (where c.changed_field_key is null) as n_null, count(p.field_key) as n_matched,
         (select count(*) = count(distinct field_key) from public.fields) as parent_is_unique
  from public.deal_changes c left join public.fields p on p.field_key = c.changed_field_key
  union all
  select 'deal_changes.new_value [user_id] -> users.id', count(*), count(*) filter (where c.new_value is null), count(p.id),
         (select count(*) = count(distinct id) from public.users)
  from public.deal_changes c left join public.users p on p.id = c.new_value::int where c.changed_field_key = 'user_id'
  union all
  select 'deal_changes.new_value [stage_id] -> stages.stage_id', count(*), count(*) filter (where c.new_value is null), count(p.stage_id),
         (select count(*) = count(distinct stage_id) from public.stages)
  from public.deal_changes c left join public.stages p on p.stage_id = c.new_value::int where c.changed_field_key = 'stage_id'
  union all
  -- the lost_reason options sit inside fields.field_value_options (JSON), keyed by option id
  select 'deal_changes.new_value [lost_reason] -> fields option id', count(*), count(*) filter (where c.new_value is null), count(o.id),
         (select count(*) = count(distinct j ->> 'id') from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'lost_reason')
  from public.deal_changes c
  left join (select j ->> 'id' as id from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'lost_reason') o on o.id = c.new_value
  where c.changed_field_key = 'lost_reason'
) f;

-- =====================================================================
-- 4. Nulls and not nulls per column
-- =====================================================================
select key as col, count(*) as n_rows,
       count(*) - count(*) filter (where value = 'null'::jsonb) as n_not_null,
       count(*) filter (where value = 'null'::jsonb) as n_null,
       count(*) filter (where value = '""'::jsonb) as n_blank
from public.deal_changes t, jsonb_each(to_jsonb(t)) group by key order by key;

-- =====================================================================
-- 5. Outliers (IQR rule, fences q1 - 1.5 IQR and q3 + 1.5 IQR)
-- =====================================================================
-- 5a. Days between consecutive stage events of the same deal (first events have no gap and are excluded below)
with t0 as (select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x from public.deal_changes where changed_field_key = 'stage_id'),
t as (select x from t0 where x is not null),
b as (select percentile_cont(0.25) within group (order by x) as q1, percentile_cont(0.75) within group (order by x) as q3 from t)
select count(*) as n_values, round(q1::numeric, 1) as q1, round(q3::numeric, 1) as q3,
       round((q1 - 1.5 * (q3 - q1))::numeric, 1) as lower_fence, round((q3 + 1.5 * (q3 - q1))::numeric, 1) as upper_fence,
       count(*) filter (where x < q1 - 1.5 * (q3 - q1) or x > q3 + 1.5 * (q3 - q1)) as n_outliers,
       round(min(x)::numeric, 1) as min_value, round(max(x)::numeric, 1) as max_value
from t, b group by q1, q3;

-- 5b. Days from creation (add_time) to the first stage 1 entry
with t as (select extract(epoch from s.ts - a.ts) / 86400 as x from (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1) a join (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'stage_id' and new_value = '1' group by 1) s using (deal_id)),
b as (select percentile_cont(0.25) within group (order by x) as q1, percentile_cont(0.75) within group (order by x) as q3 from t)
select count(*) as n_values, round(q1::numeric, 1) as q1, round(q3::numeric, 1) as q3,
       round((q1 - 1.5 * (q3 - q1))::numeric, 1) as lower_fence, round((q3 + 1.5 * (q3 - q1))::numeric, 1) as upper_fence,
       count(*) filter (where x < q1 - 1.5 * (q3 - q1) or x > q3 + 1.5 * (q3 - q1)) as n_outliers,
       round(min(x)::numeric, 1) as min_value, round(max(x)::numeric, 1) as max_value
from t, b group by q1, q3;

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================

-- 6a. Size and date coverage; 6b. what the log tracks (rows and deals per field key)
-- Question: what does deal_changes track, and for how many deals?
-- Finding:  an event log with four keys: stage_id 8,906, user_id 2,500, add_time 2,000, lost_reason 2,000 (each key covers all 1,995 deals).
-- Consequence: build the funnel from stage_id events; cast new_value per changed_field_key in staging.
select changed_field_key, count(*) as n_events, count(distinct deal_id) as n_deals
from public.deal_changes group by 1 order by 2 desc;

-- 6c. How deals move between stages
-- Question: do deals move through the stages one by one?
-- Finding:  every deal starts at stage 1; 2,502 moves skip at least one stage (1,684 deals); 8 backward moves; 2 repeats.
-- Consequence: recorded-only counts under-count the middle steps -> backfill skipped stages with an is_inferred flag.
with s as (
  select deal_id, new_value::int as stage_id,
         lag(new_value::int) over (partition by deal_id order by change_time) as prev_stage
  from public.deal_changes where changed_field_key = 'stage_id'
)
select stage_id - prev_stage as move, count(*) as n_events
from s where prev_stage is not null group by 1 order by 1;

-- 6d. Deals with two creation events
-- Question: are there deals with more than one creation event?
-- Finding:  5 deals have two add_time events; they hold two full lifecycles (paths like 1>2>3>4>5>8>1>2>4>5)
--           and explain every backward move.
-- Consequence: count each deal once per step and month (first entry wins); list the ids as an open question.
select deal_id, count(*) as n_creations,
       (select string_agg(new_value, '>' order by change_time) from public.deal_changes s
        where s.deal_id = a.deal_id and s.changed_field_key = 'stage_id') as stage_path
from public.deal_changes a where changed_field_key = 'add_time'
group by deal_id having count(*) > 1 order by 1;

-- 6e. What lost_reason means
-- Question: what does lost_reason mean here?
-- Finding:  every deal has one (values 1-5, roughly uniform), including deals that reached stage 9; for 4 of the 5 two-lifecycle deals it is dated before the last stage event.
-- Consequence: lost_reason marks the end of a lifecycle, not a lost deal; it does not remove deals from the funnel.
with mx as (select deal_id, max(new_value::int) as max_stage from public.deal_changes where changed_field_key = 'stage_id' group by 1)
select l.new_value as lost_reason, count(*) as n_deals, round(avg(mx.max_stage), 2) as avg_max_stage
from public.deal_changes l join mx using (deal_id)
where l.changed_field_key = 'lost_reason' group by 1 order by 1;

-- 6f. Which date defines Step 1
-- Question: which date should define Step 1 (Lead Generation)?
-- Finding:  deals enter stage 1 a median of 35 days after add_time (min 2, max 83, IQR 25-45); 2024-01 has 247 created but 30 entering stage 1.
-- Consequence: Step 1 = stage 1 entry (consistent with the other steps); add_time stays documented as the alternative.
with a as (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1),
     s as (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'stage_id' and new_value = '1' group by 1)
select percentile_cont(0.5) within group (order by extract(epoch from s.ts - a.ts) / 86400) as median_days,
       min(extract(epoch from s.ts - a.ts) / 86400) as min_days, max(extract(epoch from s.ts - a.ts) / 86400) as max_days
from a join s using (deal_id);

-- 6g. Effect of backfilling skipped stages
-- Question: how much does backfilling skipped stages change each step?
-- Finding:  recorded vs backfilled deals per stage: 1: 1,995/1,995; 2: 1,479/1,990; 3: 1,305/1,951; 4: 1,086/1,862; 5: 894/1,693;
--           6: 741/1,424; 7: 588/1,081; 8: 479/723; 9: 324/324. Backfill adds 4,152 stage entries.
-- Consequence: the choice changes the report by up to 90% on the middle steps; make it a variable, document both.
with s as (select deal_id, new_value::int as st from public.deal_changes where changed_field_key = 'stage_id'),
     mx as (select deal_id, max(st) as max_st from s group by 1)
select n as stage,
       (select count(distinct deal_id) from s where st = n) as recorded,
       (select count(*) from mx where max_st >= n) as backfilled
from generate_series(1, 9) n order by 1;

-- 6h. Shape of the data: numeric summary (x = days between consecutive events)
with t as (
  select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
  from deal_changes where changed_field_key = 'stage_id'
), v as (select x from t where x is not null),
s as (select avg(x) as mu, stddev_samp(x) as sd, count(*) as n from v)
select s.n, round(s.mu::numeric, 2) as mean,
       round((percentile_cont(0.5) within group (order by v.x))::numeric, 2) as median,
       round(s.sd::numeric, 2) as stddev, round(min(v.x)::numeric, 2) as min, round(max(v.x)::numeric, 2) as max,
       round((sum(power((v.x - s.mu) / s.sd, 3)) / s.n)::numeric, 2) as skewness,
       round((sum(power((v.x - s.mu) / s.sd, 4)) / s.n - 3)::numeric, 2) as excess_kurtosis
from v, s group by s.n, s.mu, s.sd;

-- 6h. quantiles
with v as (select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
           from deal_changes where changed_field_key = 'stage_id')
select percentile_cont(array[0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99]) within group (order by x) as qs from v where x is not null;

-- 6h. histogram with text bars
with v as (select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
           from deal_changes where changed_field_key = 'stage_id'),
t as (select x from v where x is not null),
b as (select min(x) as lo, max(x) + 1e-9 as hi from t),
h as (select width_bucket(t.x, b.lo, b.hi, 10) as bucket, min(t.x) as bin_min, max(t.x) as bin_max, count(*) as n from t, b group by 1)
select bucket, round(bin_min::numeric, 1) as bin_min, round(bin_max::numeric, 1) as bin_max, n,
       repeat('#', (40.0 * n / max(n) over ())::int) as bar
from h order by bucket;

-- 6h. deciles
with v as (select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
           from deal_changes where changed_field_key = 'stage_id'),
d as (select x, ntile(10) over (order by x) as decile from v where x is not null)
select decile, count(*) as n, round(min(x)::numeric, 1) as lo, round(max(x)::numeric, 1) as hi
from d group by decile order by decile;

-- 6h. distribution of a count per entity (events per entity)
select n_events, count(*) as n_entities from (
  select deal_id, count(*) as n_events from deal_changes group by 1) x group by 1 order by 1;

-- 6i. Lost reasons with their labels (from fields) and how far those deals got.
-- Finding: the five reasons are Customer Not Ready, Pricing Issues, Unreachable Customer, Product Mismatch and Duplicate Entry, and each applies to
--          about 400 deals. The average highest stage is 6.4 to 6.7 for every reason, so the reason says nothing about where a deal stopped:
--          377 deals are 'Duplicate Entry' yet 274 of them reached Closing; 422 are 'Unreachable Customer' yet 411 reached Needs Assessment or later.
-- Consequence: duplicates are kept as deals instead of being merged, and the reasons are not consistent with the stages; ask the CRM admin how the
--              lost reason is entered; do not use lost_reason as a deal outcome.
with m as (select deal_id, max(new_value::int) as highest_stage from public.deal_changes where changed_field_key = 'stage_id' group by 1),
lr as (
  select distinct l.deal_id, o.id as reason_id, o.label
  from public.deal_changes l
  join (select j ->> 'id' as id, j ->> 'label' as label from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'lost_reason') o on o.id = l.new_value
  where l.changed_field_key = 'lost_reason'
)
select lr.reason_id, lr.label, count(*) as n_deals, round(avg(m.highest_stage), 2) as avg_highest_stage,
       count(*) filter (where m.highest_stage >= 3) as reached_needs_assessment, count(*) filter (where m.highest_stage >= 6) as reached_closing,
       count(*) filter (where m.highest_stage = 9) as reached_last_stage
from lr join m using (deal_id) group by 1, 2 order by 1;
