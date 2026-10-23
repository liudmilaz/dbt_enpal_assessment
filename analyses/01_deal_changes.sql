-- TABLE public.deal_changes    CLASS: fact (event log)    GRAIN: one change of one field of one deal
-- Business meaning: the history of each deal (created, owner assigned, stage entered, lost reason set). See docs/business_context.md;
-- field definitions and Pipedrive links in docs/data_dictionary.md.
-- Findings in short:
--   - primary key: none declared; (deal_id, changed_field_key, change_time) has no duplicates and no nulls
--   - foreign keys: field key, owner, stage and lost reason all match their dictionaries (0 orphans); there is no deals table
--   - nulls: none
--   - outliers: no outlier month; changes ramp up to 2024-08 and run off to 2025-03 (partial); creations stop 2024-09-13
--   - descriptive: 4 field keys; 84% of deals skip a stage; 5 deals carry two lifecycles
-- Business questions about the funnel are in 08_business_questions.sql.
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).

-- =====================================================================
-- 1. Rows and columns
-- =====================================================================
select
    count(*) as n_rows
from public.deal_changes;
-- 15406 rows; columns: deal_id, change_time, changed_field_key, new_value

-- =====================================================================
-- 2. Primary key
-- =====================================================================
-- No key is declared. Candidate: (deal_id, changed_field_key, change_time). Rows that share it:
with counted as (
select *,
    count(*) over (partition by deal_id, changed_field_key, change_time) as n_dup
from public.deal_changes
    )
select *
from counted
where n_dup > 1
order by deal_id, changed_field_key, change_time; --postgres limitation: no qualify, so filter the window count in a cte
-- 0 rows: the candidate is unique

-- example of how I would identify a compound primary key in SF / BQ:
-- select
--     *
-- from public.deal_changes
-- qualify count(*) over (partition by deal_id, changed_field_key, change_time) > 1;

-- =====================================================================
-- 3. Foreign keys (rows whose value is missing in the parent)
-- =====================================================================
-- changed_field_key -> fields.field_key
select
    c.changed_field_key,
    count(*) as n_rows
from public.deal_changes c
left join public.fields f
    on f.field_key = c.changed_field_key
where f.field_key is null
group by 1;
-- 0 rows

-- new_value of the stage events -> stages.stage_id
-- filter the stage events first: new_value also holds timestamps (add_time), so the cast to int is only safe after the filter
with stage_events as (
    select
        new_value::int as stage_id
    from public.deal_changes
    where changed_field_key = 'stage_id'
)
select
    e.stage_id,
    count(*) as n_rows
from stage_events e
left join public.stages s
    on s.stage_id = e.stage_id
where s.stage_id is null
group by 1;
-- 0 rows

-- new_value of the owner events -> users.id
with owner_events as (
    select
        new_value::int as user_id
    from public.deal_changes
    where changed_field_key = 'user_id'
)
select
    e.user_id,
    count(*) as n_rows
from owner_events e
left join public.users u
    on u.id = e.user_id
where u.id is null
group by 1;
-- 0 rows

-- new_value of the lost reason events -> the option ids inside fields.field_value_options (JSON)
with lost_reason_counts as (  -- aggregate before the join: 2,000 events become 5 distinct reasons, so the join compares 5 rows, not 2,000
    select
        new_value::int as reason_id,  -- cast only after the filter: other keys hold timestamps
        count(*) as n_rows
    from public.deal_changes
    where changed_field_key = 'lost_reason'  -- filter first: only lost-reason events point at the option list
    group by 1
),
lost_reason_options as (  -- unpack the JSON array once: one row per option
    select
        o.id as option_id
    from public.fields f
    cross join jsonb_to_recordset(f.field_value_options) as o(id int, label text)  -- typed columns declared once, instead of o ->> 'id' at every use
    where f.field_key = 'lost_reason'  -- unpack only this field's array, not all four
)
select
    c.reason_id,
    c.n_rows
from lost_reason_counts c
left join lost_reason_options r
    on r.option_id = c.reason_id
where r.option_id is null;  -- anti-join: reasons with no matching option
-- 0 rows

-- =====================================================================
-- 4. Nulls per column
-- =====================================================================
select
    count(*) - count(deal_id)           as deal_id_nulls,
    count(*) - count(change_time)       as change_time_nulls,
    count(*) - count(changed_field_key) as changed_field_key_nulls,
    count(*) - count(new_value)         as new_value_nulls
from public.deal_changes;
-- 0 | 0 | 0 | 0

-- =====================================================================
-- 5. Outliers: time distribution and volume per dimension (spikes, drops and holes)
-- =====================================================================
-- 5a. Changes per month, with quarter and year
select
    date_trunc('month',   change_time)::date as change_month,    -- 2024-03-01
    date_trunc('quarter', change_time)::date as change_quarter,  -- 2024-01-01
    date_trunc('year',    change_time)::date as change_year,     -- 2024-01-01
    count(*) as nr_changes
from public.deal_changes
group by 1, 2, 3
order by 1 desc;
-- 2024-01: 432, rises to ~1,900 in 2024-07 / 2024-08, then falls to 3 in 2025-03 (data ends 2025-03-11, a partial month).
-- No hole, no single spike: a ramp-up while deals are created (to 2024-09) and a run-off while they finish.

-- 5b. Changes per dimension (the field key)
select
    changed_field_key,
    count(*) as nr_changes,
    count(distinct deal_id) as nr_deals
from public.deal_changes
group by 1
order by 2 desc;
-- stage_id 8906 | user_id 2500 | add_time 2000 | lost_reason 2000; every key covers all 1995 deals

-- 5c. Changes per dimension and month (one column per field key)
select
    date_trunc('month', change_time)::date as change_month,
    count(*) filter (where changed_field_key = 'add_time')    as nr_add_time,
    count(*) filter (where changed_field_key = 'user_id')     as nr_user_id,
    count(*) filter (where changed_field_key = 'stage_id')    as nr_stage_id,
    count(*) filter (where changed_field_key = 'lost_reason') as nr_lost_reason
from public.deal_changes
group by 1
order by 1 desc;
-- add_time: ~240 per month 2024-01 to 2024-08, 92 in 2024-09, then none (creations stop on 2024-09-13, like the activities).
-- user_id follows creation with a lag (148 in 2024-01 vs 247 created); stage_id peaks 2024-08 (1,150) and runs to 2025-02;
-- lost_reason starts at 0 in 2024-01 and is the only key left in 2025-03. Each key's curve is smooth: no outlier month.
-- The statistical outlier check on the gaps between stage events is in 09_review_later.sql.

-- 5d. Average number of changes per deal per month
-- Why monthly: the export covers 15 months (2024-01 to 2025-03) and the report is monthly, so the month is the grain that shows
-- ramp-up, run-off and outlier months at this range. Weeks or days would mostly show noise on 1,995 deals; quarters would hide
-- the ramp-up. A specific question (seasonality, sales-team performance, time per stage) is a separate deep dive per domain,
-- with its own grain and its own data, not part of this profile.
with changes_per_deal_month as (  -- aggregate first: one row per deal and month with its number of changes
    select
        date_trunc('month', change_time)::date as change_month,
        deal_id,
        count(*) as nr_changes
    from public.deal_changes
    group by 1, 2
)
select
    change_month,
    count(*) as nr_deals_changed,  -- deals with at least one change in the month
    sum(nr_changes) as nr_changes,
    round(avg(nr_changes), 2) as avg_changes_per_deal,
    max(nr_changes) as max_changes_per_deal
from changes_per_deal_month
group by 1
order by 1 desc;
-- 1.74 to 1.84 changes per active deal per month from 2024-01 to 2024-10, falling to 1.0 in 2025-03 as deals finish;
-- max 8 changes for one deal in one month (2024-04). Overall: 8,834 deal-months, 1.74 changes each, 4.4 active months per deal.
-- Stable rate: the monthly totals in 5a move with the number of active deals, not with more activity per deal.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================
-- 6a. How deals move between stages (move = new stage - previous stage)
with moves as (  -- filter first: only stage events, so the cast to int is safe
    select
        new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as move
    from public.deal_changes
    where changed_field_key = 'stage_id'
)
select
    move,
    count(*) as n_moves
from moves
where move is not null  -- the first stage event of a deal has no previous stage
group by 1
order by 1;
-- +1: 4399 moves; +2 or more: 2502 (skipped stages); 0: 2 (repeats); negative: 8 (backward)

-- 6b. Deals with two creation events
select
    deal_id,
    count(*) as n_creations
from public.deal_changes
where changed_field_key = 'add_time'
group by 1
having count(*) > 1;
-- 5 deals; they hold two lifecycles and explain all 8 backward moves (see 08 B2)
