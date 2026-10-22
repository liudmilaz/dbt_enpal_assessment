-- Descriptive analysis: what the data contains. Sections A to I; each section starts with its own Question / Finding / Consequence.
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).

-- ===================================================================
-- A. Size and date coverage
-- ===================================================================
-- Question: how big is each source and what dates does it cover?
-- Finding:  deal_changes 15,406 rows / 1,995 deals, 2024-01-01 to 2025-03-11; activity 4,579 rows, 2024-01-01 to 2024-09-13;
--           users 1,787; stages 9; fields 4; activity_types 4. A double docker load would show activity = 9,158.
-- Consequence: counts are the reference for the loader test; report window starts 2024-01.
select 'deal_changes' as tbl_name, count(*) as n_rows, min(change_time)::date as first_dt, max(change_time)::date as last_dt from public.deal_changes
union all select 'activity', count(*), min(due_to)::date, max(due_to)::date from public.activity
union all select 'users', count(*), min(modified)::date, max(modified)::date from public.users
union all select 'stages', count(*), null, null from public.stages
union all select 'fields', count(*), null, null from public.fields
union all select 'activity_types', count(*), null, null from public.activity_types;

-- ===================================================================
-- B. What the event log tracks
-- ===================================================================
-- Question: what does deal_changes track, and for how many deals?
-- Finding:  an event log with four keys: stage_id 8,906, user_id 2,500, add_time 2,000, lost_reason 2,000 (each key covers all 1,995 deals).
-- Consequence: build the funnel from stage_id events; cast new_value per changed_field_key in staging.
select changed_field_key, count(*) as n_events, count(distinct deal_id) as n_deals
from public.deal_changes group by 1 order by 2 desc;

-- ===================================================================
-- C. How deals move between stages
-- ===================================================================
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

-- ===================================================================
-- D. Deals with two creation events
-- ===================================================================
-- Question: are there deals with more than one creation event?
-- Finding:  5 deals have two add_time events; they hold two full lifecycles (paths like 1>2>3>4>5>8>1>2>4>5)
--           and explain every backward move.
-- Consequence: count each deal once per step and month (first entry wins); list the ids as an open question.
select deal_id, count(*) as n_creations,
       (select string_agg(new_value, '>' order by change_time) from public.deal_changes s
        where s.deal_id = a.deal_id and s.changed_field_key = 'stage_id') as stage_path
from public.deal_changes a where changed_field_key = 'add_time'
group by deal_id having count(*) > 1 order by 1;

-- ===================================================================
-- E. What lost_reason means
-- ===================================================================
-- Question: what does lost_reason mean here?
-- Finding:  every deal has one (values 1-5, roughly uniform), including deals that reached stage 9; for 4 of the 5 two-lifecycle deals it is dated before the last stage event.
-- Consequence: lost_reason marks the end of a lifecycle, not a lost deal; it does not remove deals from the funnel.
with mx as (select deal_id, max(new_value::int) as max_stage from public.deal_changes where changed_field_key = 'stage_id' group by 1)
select l.new_value as lost_reason, count(*) as n_deals, round(avg(mx.max_stage), 2) as avg_max_stage
from public.deal_changes l join mx using (deal_id)
where l.changed_field_key = 'lost_reason' group by 1 order by 1;

-- ===================================================================
-- F. Activity types and the done flag
-- ===================================================================
-- Question: what activity types exist and how many are done?
-- Finding:  four types (meeting, sc_2, follow_up, after_close_call), about 1,100 each, about 50% done; 11 activity_ids appear twice with different content.
-- Consequence: steps 2.1 / 3.1 use meeting and sc_2 only; surrogate key for activity; source uniqueness test at warn.
select type, done, count(*) as n from public.activity group by 1, 2 order by 1, 2;
-- repeated activity ids
select activity_id, count(*) as n from public.activity group by 1 having count(*) > 1 order by 1;

-- ===================================================================
-- G. Can activities be joined to deals
-- ===================================================================
-- Question: can activities be joined to deals?
-- Finding:  only 8 of 4,572 distinct activity deal_ids exist in deal_changes; both id ranges are 6 digits, so random overlap is about as large.
-- Consequence: calls cannot be attributed to deals; count Sales Call 1/2 by due_to month and raise the question with Enpal.
select count(*) as n_activity_deals,
       sum(case when d.deal_id is not null then 1 else 0 end) as n_found_in_deal_changes
from (select distinct deal_id from public.activity) a
left join (select distinct deal_id from public.deal_changes) d using (deal_id);

-- ===================================================================
-- H. Which date defines Step 1
-- ===================================================================
-- Question: which date should define Step 1 (Lead Generation)?
-- Finding:  deals enter stage 1 a median of 35 days after add_time (min 2, max 83, IQR 25-45); 2024-01 has 247 created but 30 entering stage 1.
-- Consequence: Step 1 = stage 1 entry (consistent with the other steps); add_time stays documented as the alternative.
with a as (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1),
     s as (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'stage_id' and new_value = '1' group by 1)
select percentile_cont(0.5) within group (order by extract(epoch from s.ts - a.ts) / 86400) as median_days,
       min(extract(epoch from s.ts - a.ts) / 86400) as min_days, max(extract(epoch from s.ts - a.ts) / 86400) as max_days
from a join s using (deal_id);

-- ===================================================================
-- I. Effect of backfilling skipped stages
-- ===================================================================
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
