-- BUSINESS QUESTIONS: the funnel KPIs read against the business (docs/business_context.md).
-- Each block starts from what Enpal's sales process would lead us to expect, then checks the data, then says what it means for
-- rep_sales_funnel_monthly. The table profiles (keys, nulls, outliers) are in 01 to 06; the data quality list in 07.
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).

-- =====================================================================
-- B1. Step 1, Lead Generation: when does a lead start?
-- =====================================================================
-- Expectation: a household shows interest, the deal is created, a rep is assigned, the deal enters the pipeline.

-- B1a. Order of the first events of a deal (days after creation)
with created as (
    select
        deal_id,
        min(change_time) as created_at
    from public.deal_changes
    where changed_field_key = 'add_time'
    group by 1
),
first_owner as (
    select
        deal_id,
        min(change_time) as owner_at
    from public.deal_changes
    where changed_field_key = 'user_id'
    group by 1
),
stage_1 as (
    select
        deal_id,
        min(change_time) as stage_1_at
    from public.deal_changes
    where changed_field_key = 'stage_id'
        and new_value = '1'
    group by 1
)
select
    percentile_cont(0.5) within group (order by extract(epoch from owner_at - created_at) / 86400)   as median_days_to_owner,
    percentile_cont(0.5) within group (order by extract(epoch from stage_1_at - created_at) / 86400) as median_days_to_stage_1,
    count(*) filter (where owner_at < stage_1_at) as n_owner_before_stage_1,
    count(*) as n_deals
from created
join first_owner
    using (deal_id)
join stage_1
    using (deal_id);
-- owner after 15 days, stage 1 after 35 days; the owner comes first for all 1995 deals

-- B1b. Deals created vs deals entering stage 1, per month
with created as (
    select
        deal_id,
        date_trunc('month', min(change_time))::date as month
    from public.deal_changes
    where changed_field_key = 'add_time'
    group by 1
),
stage_1 as (
    select
        deal_id,
        date_trunc('month', min(change_time))::date as month
    from public.deal_changes
    where changed_field_key = 'stage_id'
        and new_value = '1'
    group by 1
),
created_per_month as (
    select
        month,
        count(*) as n_created
    from created
    group by 1
),
stage_1_per_month as (
    select
        month,
        count(*) as n_entered_stage_1
    from stage_1
    group by 1
)
select
    month,
    n_created,
    n_entered_stage_1
from created_per_month
full join stage_1_per_month
    using (month)
order by 1;
-- 2024-01: 247 created, 30 entered stage 1; creations stop in 2024-09, stage 1 entries run to 2024-11
-- Consequence: the two rules give different monthly Step 1 counts with the same total (1995). Open decision; recommended:
-- stage 1 entry, so that every stage step uses the same rule.

-- =====================================================================
-- B2. Steps 2 to 9: do deals pass the stages in order, and how does the funnel narrow?
-- =====================================================================
-- Expectation: a deal passes every stage in order; most deals drop out early.

-- B2a. Where deals stop (highest stage reached)
with highest as (
    select
        deal_id,
        max(new_value::int) as highest_stage
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1
)
select
    highest_stage,
    count(*) as n_deals
from highest
group by 1
order by 1;
-- 5, 39, 89, 169, 269, 343, 358, 399, 324: the later the stage, the more deals stop there.
-- A real funnel narrows early; this one barely narrows. The sample looks pre-filtered or generated.

-- B2b. Recorded vs backfilled deals per stage (backfilled = the deal reached this stage or a later one)
with entries as (
    select
        deal_id,
        new_value::int as stage_id
    from public.deal_changes
    where changed_field_key = 'stage_id'
),
highest as (
    select
        deal_id,
        max(stage_id) as highest_stage
    from entries
    group by 1
),
recorded as (
    select
        stage_id,
        count(distinct deal_id) as n_recorded
    from entries
    group by 1
),
backfilled as (
    select
        s.stage_id,
        count(*) as n_backfilled
    from public.stages s
    join highest h
        on h.highest_stage >= s.stage_id
    group by 1
)
select
    s.stage_id,
    s.stage_name,
    r.n_recorded,
    b.n_backfilled
from public.stages s
join recorded r
    using (stage_id)
join backfilled b
    using (stage_id)
order by 1;
-- 84% of deals skip a stage; backfill (decided) adds 4152 entries, up to +90% on the middle stages

-- B2c. The two-lifecycle deals: their stage path
with two_lifecycles as (
    select
        deal_id
    from public.deal_changes
    where changed_field_key = 'add_time'
    group by 1
    having count(*) > 1
),
stage_events as (
    select
        deal_id,
        new_value,
        change_time
    from public.deal_changes
    where changed_field_key = 'stage_id'
)
select
    e.deal_id,
    string_agg(e.new_value, ' > ' order by e.change_time) as stage_path
from stage_events e
join two_lifecycles t
    using (deal_id)
group by 1;
-- 5 deals run through the pipeline twice; they explain all 8 backward moves. Count each deal once per step, at its first entry.

-- =====================================================================
-- B3. How long does a sale take?
-- =====================================================================
-- Expectation: a household energy sale takes weeks to months from first contact to a signed contract.
with entries as (
    select
        deal_id,
        new_value::int as stage_id,
        min(change_time) as entered_at
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1, 2
)
select
    count(*) as n_deals,
    percentile_cont(array[0.25, 0.5, 0.75]) within group (order by extract(epoch from c.entered_at - l.entered_at) / 86400) as days_q1_median_q3
from entries l
join entries c
    on c.deal_id = l.deal_id
where l.stage_id = 1
    and c.stage_id = 6;
-- 741 deals reached Closing: median 50 days from stage 1 (q1 35, q3 66). Plausible.

-- =====================================================================
-- B4. Steps 2.1 and 3.1: are the sales calls part of the deals' journey?
-- =====================================================================
-- Expectation: Sales Call 1 happens around Qualified Lead, Sales Call 2 around Needs Assessment, both linked to the deal.

-- B4a. Calls per month next to stage 2 and stage 3 entries per month
with entries as (
    select
        deal_id,
        new_value::int as stage_id,
        min(change_time) as entered_at
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1, 2
),
calls_per_month as (
    select
        date_trunc('month', due_to)::date as month,
        count(*) filter (where type = 'meeting')          as sales_call_1,
        count(*) filter (where type = 'meeting' and done) as sales_call_1_done,
        count(*) filter (where type = 'sc_2')             as sales_call_2,
        count(*) filter (where type = 'sc_2' and done)    as sales_call_2_done
    from public.activity
    group by 1
),
entries_per_month as (
    select
        date_trunc('month', entered_at)::date as month,
        count(*) filter (where stage_id = 2) as entered_stage_2,
        count(*) filter (where stage_id = 3) as entered_stage_3
    from entries
    group by 1
)
select
    e.month,
    e.entered_stage_2,
    e.entered_stage_3,
    c.sales_call_1,
    c.sales_call_1_done,
    c.sales_call_2,
    c.sales_call_2_done
from entries_per_month e
left join calls_per_month c
    on c.month = e.month
order by 1;
-- Calls are flat (about 130 per type per month) from 2024-01, when only 6 deals entered stage 2; they stop on 2024-09-13 while
-- stage entries continue to 2025-01. The calls do not follow the deals.

-- B4b. The only activities whose deal_id exists in deal_changes, next to that deal's stage dates
with stage_dates as (
    select
        deal_id,
        string_agg(new_value || ' on ' || change_time::date, ', ' order by change_time) as stage_dates
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1
)
select
    a.deal_id,
    a.type,
    a.done,
    a.due_to::date as due_date,
    s.stage_dates
from public.activity a
join stage_dates s
    using (deal_id)
order by 1;
-- 8 rows; only one call (deal 264879, Sales Call 1 between stage 1 and stage 2) fits the deal's timeline. The match is coincidence.

-- B4c. Share of calls marked done
select
    type,
    count(*) as n_activities,
    round(100.0 * avg(done::int), 1) as pct_done
from public.activity
group by 1
order by 1;
-- every type 50% done, although every call is due before the export ends.
-- Consequence: steps 2.1 and 3.1 count calls by due month, not funnel deals; done-only (recommended) halves them. Open decision.

-- =====================================================================
-- B5. Lost reason: does it mean the deal was lost?
-- =====================================================================
-- Expectation: a lost reason is set when a deal is lost, and the reason matches where it stopped.

-- B5a. When the lost reason is set, relative to the deal's last stage event
with lost as (
    select
        deal_id,
        max(change_time) as lost_at
    from public.deal_changes
    where changed_field_key = 'lost_reason'
    group by 1
),
last_stage as (
    select
        deal_id,
        max(change_time) as last_stage_at
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1
)
select
    count(*) as n_deals,
    percentile_cont(array[0, 0.5, 1]) within group (order by extract(epoch from lost_at - last_stage_at) / 86400) as days_min_median_max
from lost
join last_stage
    using (deal_id);
-- every deal, 1 to 30 days after its last stage event (median 16): a closure label for every deal

-- B5b. Reason labels against how far the deals got
with highest as (
    select
        deal_id,
        max(new_value::int) as highest_stage
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1
),
reasons as (  -- unpack the JSON array once: one row per lost-reason option
    select
        o.id as reason_id,
        o.label as reason
    from public.fields f
    cross join jsonb_to_recordset(f.field_value_options) as o(id int, label text)  -- typed columns declared once
    where f.field_key = 'lost_reason'  -- unpack only this field's array
),
lost_reason_events as (  -- filter first: 2,000 lost-reason events out of 15,406 rows, before any join
    select
        deal_id,
        new_value::int as reason_id  -- cast only after the filter: other keys hold timestamps
    from public.deal_changes
    where changed_field_key = 'lost_reason'
)
select
    r.reason,
    count(distinct l.deal_id) as n_deals,
    round(avg(h.highest_stage), 1) as avg_highest_stage,
    count(distinct l.deal_id) filter (where h.highest_stage >= 6) as n_reached_closing,
    count(distinct l.deal_id) filter (where h.highest_stage = 9)  as n_reached_renewal
from lost_reason_events l
join reasons r
    on r.reason_id = l.reason_id
join highest h
    using (deal_id)
group by 1
order by 1;
-- about 400 deals per reason, average highest stage 6.4 to 6.7 for every reason; Duplicate Entry: 377 deals, 274 reached Closing.
-- Consequence: lost reason does not remove deals from the funnel; ask the CRM admin how it is entered.

-- =====================================================================
-- B6. Owners: does the ownership look like a sales team?
-- =====================================================================
-- Expectation: a few dozen reps, each owning many deals; a handover (for example to installation) after Closing.
select
    count(distinct new_value) as n_owners,
    count(*) as n_owner_events,
    count(distinct deal_id) as n_deals
from public.deal_changes
where changed_field_key = 'user_id';
-- 1347 owners for 1995 deals (median 2 deals each); 505 changes of owner, 499 of them before stage 1: no handover after Closing.
-- Consequence: owner is not needed for the report; the user data looks generated.
