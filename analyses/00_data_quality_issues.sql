-- MAIN DATA QUALITY ISSUES of the six raw Pipedrive tables, one block per issue, grouped by table.
-- Each block: the issue, the query that proves it, the result, and what it means for the model.
-- Category: process = comes from how data is entered or exported (needs the business owner); data = defect in the records.

-- =====================================================================
-- deal_changes
-- =====================================================================
-- D1. Stages are skipped (process): reps move deals over several stages at once.
with stage_moves as (  -- filter first: only stage events, so the cast is safe
    select
        deal_id,
        new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as move
    from public.deal_changes
    where changed_field_key = 'stage_id'
),
deals as (  -- one row per deal: did any move skip a stage?
    select
        deal_id,
        bool_or(move > 1) as skips_a_stage
    from stage_moves
    group by 1
)
select
    count(*) as nr_deals,
    count(*) filter (where skips_a_stage) as nr_deals_skipping,
    round(100.0 * count(*) filter (where skips_a_stage) / count(*), 1) as pct_deals_skipping
from deals;
-- 1995 | 1684 | 84.4
-- Model: backfill skipped stages with is_inferred (decided).

-- D2. After-sale stages without a recorded Closing (process): installation or after-sales without a signed contract.
with entries as (  -- each stage a deal entered, once
    select distinct
        deal_id,
        new_value::int as stage_id
    from public.deal_changes
    where changed_field_key = 'stage_id'
),
per_deal as (  -- one row per deal: after-sale stage reached, and Closing recorded?
    select
        deal_id,
        bool_or(stage_id >= 7) as reached_after_sale,
        bool_or(stage_id = 6) as has_closing
    from entries
    group by 1
)
select
    count(*) filter (where reached_after_sale) as nr_deals_after_sale,
    count(*) filter (where reached_after_sale and not has_closing) as nr_without_closing
from per_deal;
-- 1081 | 683
-- Model: with backfill these deals count under Closing although no contract was recorded; document it.

-- D3. Two lifecycles in one deal (process): two creation events, overlapping in time, like a merged duplicate lead.
select
    deal_id,
    count(*) as nr_creations
from public.deal_changes
where changed_field_key = 'add_time'
group by 1
having count(*) > 1;
-- 5 deals; they explain all 8 backward stage moves and the 5 deals with two lost reasons
-- Model: count each deal once per step, by its first entry.

-- D4. A lost reason on every deal, unrelated to how far it got (process).
with highest as (  -- the furthest stage each deal reached
    select
        deal_id,
        max(new_value::int) as highest_stage
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1
),
lost as (  -- one row per deal and reason
    select distinct
        deal_id,
        new_value as reason_id
    from public.deal_changes
    where changed_field_key = 'lost_reason'
)
select
    l.reason_id,
    count(*) as nr_deals,
    count(*) filter (where h.highest_stage >= 6) as nr_reached_closing,
    count(*) filter (where h.highest_stage = 9) as nr_reached_renewal
from lost l
join highest h
    on h.deal_id = l.deal_id
group by 1
order by 1;
-- every reason 377 to 422 deals, 69 to 73% reached Closing; reason 5 (Duplicate Entry): 377 deals, 274 reached Closing
-- Model: lost reason is not a deal outcome; not used for the funnel.

-- D5. Generated timing (data): every change has the deal's creation time of day.
with created as (  -- each deal's first creation time
    select
        deal_id,
        min(change_time) as created_at
    from public.deal_changes
    where changed_field_key = 'add_time'
    group by 1
)
select
    count(*) as nr_changes,
    round(100.0 * count(*) filter (where d.change_time::time = c.created_at::time) / count(*), 1) as pct_same_clock_time
from public.deal_changes d
join created c
    on c.deal_id = d.deal_id;
-- 15406 | 99.8: dates are creation + whole days; time spent per stage says nothing about the real sales speed.

-- D6. One value column with mixed types (data): new_value holds timestamps, user ids, stage ids and reason ids.
select
    changed_field_key,
    min(new_value) as min_value,
    max(new_value) as max_value
from public.deal_changes
group by 1
order by 1;
-- add_time: timestamps as text; lost_reason 1-5; stage_id 1-9; user_id: ids (min / max sorted as text)
-- Model: filter by key before casting; typed columns per key in staging.

-- =====================================================================
-- activity
-- =====================================================================
-- A1. activity_id is not unique (data): 11 ids shared by two unrelated activities each.
with counted as (  -- window count in a CTE: Postgres has no qualify
    select
        activity_id,
        count(*) over (partition by activity_id) as n_dup
    from public.activity
)
select
    count(*) filter (where n_dup > 1) as nr_duplicate_rows,
    count(distinct activity_id) filter (where n_dup > 1) as nr_duplicate_ids,
    count(*) as nr_rows
from counted;
-- 22 | 11 | 4579
-- Decided: duplicates, a data quality issue; cleansing per the domain process after review by the business stakeholder.

-- A2. Activities do not belong to the deals (process or export): deal_id almost never matches.
with deals as (  -- the deals known from the change log
    select distinct
        deal_id
    from public.deal_changes
)
select
    count(*) as nr_activities,
    count(d.deal_id) as nr_matching_a_deal
from public.activity a
left join deals d
    on d.deal_id = a.deal_id;
-- 4579 | 8
-- Model: calls (steps 2.1, 3.1) counted by due month, not per funnel deal.

-- A3. Calls that cannot have happened (process or export): after-close calls due before any deal reached Closing.
with first_closing as (  -- the first time any deal entered Closing
    select
        min(change_time) as first_closed_at
    from public.deal_changes
    where changed_field_key = 'stage_id'
        and new_value = '6'
)
select
    count(*) as nr_after_close_calls_before_first_closing
from public.activity a
cross join first_closing f
where a.type = 'after_close_call'
    and a.due_to < f.first_closed_at;
-- 157 (first Closing: 2024-02-02)

-- A4. The done flag carries no signal (process): every type is about half done, although all are due before the export ends.
select
    type,
    count(*) as nr_activities,
    round(100.0 * avg(done::int), 1) as pct_done
from public.activity
group by 1
order by 1;
-- 49.6 to 50.6% done for every type
-- Model: done-only vs all scheduled calls is an open decision; it halves steps 2.1 and 3.1.

-- =====================================================================
-- activity_types
-- =====================================================================
-- T1. An inactive type still in use, and a text flag (data): Follow Up Call is inactive; active holds 'Yes' / 'No'.
select
    t.name,
    t.active,
    count(a.activity_id) as nr_activities
from public.activity_types t
left join public.activity a
    on a.type = t.type
group by 1, 2
order by 1;
-- Follow Up Call | No | 1133
-- Model: cast active to a boolean is_active in staging.

-- =====================================================================
-- users
-- =====================================================================
-- U1. Email is not unique (data): 4 emails shared by two users each.
select
    email,
    count(*) as nr_users
from public.users
group by 1
having count(*) > 1;
-- 4 rows
-- Model: never join on email.

-- U2. Not the shape of a sales team (data): 1,347 different owners for 1,995 deals.
select
    count(distinct new_value) as nr_owners,
    count(distinct deal_id) as nr_deals
from public.deal_changes
where changed_field_key = 'user_id';
-- 1347 | 1995

-- =====================================================================
-- stages and fields
-- =====================================================================
-- S1. The same stage spelled two ways (data): stages vs the stage labels in fields.
with stage_labels as (  -- unpack the stage options once
    select
        o.id as stage_id,
        o.label as stage_label
    from public.fields f
    cross join jsonb_to_recordset(f.field_value_options) as o(id int, label text)
    where f.field_key = 'stage_id'  -- only the stage field's options
)
select
    s.stage_id,
    s.stage_name,
    l.stage_label
from public.stages s
join stage_labels l
    on l.stage_id = s.stage_id
where s.stage_name <> l.stage_label;
-- 2 | Qualified lead | Qualified Lead
-- Model: the report uses the task's step names.

-- =====================================================================
-- across tables
-- =====================================================================
-- X1. The tables were exported at different times (export): each ends on another date.
with table_ends as (  -- last date per table
    select
        'deal_changes' as table_name,
        max(change_time) as last_at
    from public.deal_changes
    union all
    select
        'activity' as table_name,
        max(due_to) as last_at
    from public.activity
    union all
    select
        'users' as table_name,
        max(modified) as last_at
    from public.users
)
select
    table_name,
    last_at
from table_ends
order by 2;
-- activity 2024-09-13 | users 2024-10-28 | deal_changes 2025-03-11
-- Model: steps 2.1 and 3.1 are 0 from 2024-10; the report window has to say so.
