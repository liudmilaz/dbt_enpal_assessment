-- REVIEW LATER: statistical checks and open questions to go through again (reminder for the owner).
-- These are not needed for the report; they test how the data was produced. Moved here from 01_deal_changes (sections 5 and 6d).
-- Go through the questions at the end of each block and write the answer under it.
-- Run one statement at a time (cursor in the statement, Cmd+E, Cmd+E in SQLTools).

-- =====================================================================
-- R1. Outliers in the gaps between stage events (IQR rule: below q1 - 1.5 * iqr or above q3 + 1.5 * iqr)
-- =====================================================================
-- Days between consecutive stage events of one deal
with gaps as (  -- one row per stage event: days since the deal's previous stage event
    select
        extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as days
    from public.deal_changes
    where changed_field_key = 'stage_id'  -- filter first: gaps between stage events only, not owner or lost-reason events
),
quartiles as (  -- the fences need q1 and q3 of all gaps, computed once
    select
        percentile_cont(0.25) within group (order by days) as q1,
        percentile_cont(0.75) within group (order by days) as q3
    from gaps
)
select
    count(*) as n_gaps,
    round(min(days)::numeric, 1) as min_days,
    round(max(days)::numeric, 1) as max_days,
    count(*) filter (where days < q1 - 1.5 * (q3 - q1) or days > q3 + 1.5 * (q3 - q1)) as n_outliers
from gaps
cross join quartiles
where days is not null  -- the first stage event of a deal has no previous one
group by q1, q3;
-- 6911 gaps, 0.5 to 35.1 days, 0 outliers
-- Questions:
--   - Is the IQR rule the right test for a distribution that is flat (uniform) rather than bell-shaped?
--   - Would a z-score or a fixed business threshold (for example "more than 30 days in one stage") be more useful?

-- =====================================================================
-- R2. Shape of the gaps between stage events (days, 3-day bins)
-- =====================================================================
with gaps as (  -- same gaps as R1
    select
        extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as days
    from public.deal_changes
    where changed_field_key = 'stage_id'  -- filter first: stage events only
)
select
    floor(days / 3) * 3 as from_day,
    count(*) as n_gaps
from gaps
where days is not null  -- the first stage event of a deal has no previous one
group by 1
order by 1;
-- 670 to 740 gaps in every 3-day bin from 3 to 30 days, fewer at the edges (464 below 3, 233 above 30): flat, which looks generated
-- Questions:
--   - Does a flat 0-35 day gap mean the export was generated (random dates), and should the README say so?
--   - Should the time spent per stage be reported at all, if the timing is synthetic?

-- =====================================================================
-- R3. Months without any change (holes) on a month spine
-- =====================================================================
with months as (  -- every month between the first and the last change, so empty months show as 0
    select
        generate_series(
            date_trunc('month', min(change_time)),
            date_trunc('month', max(change_time)),
            interval '1 month'
        )::date as change_month
    from public.deal_changes
),
changes_per_month as (  -- aggregate before the join: 15,406 changes become 15 month rows
    select
        date_trunc('month', change_time)::date as change_month,
        count(*) as nr_changes
    from public.deal_changes
    group by 1
)
select
    m.change_month,
    coalesce(c.nr_changes, 0) as nr_changes
from months m
left join changes_per_month c
    on c.change_month = m.change_month
order by 1;
-- 15 months, none empty (2024-01 to 2025-03)
-- Questions:
--   - The report needs the same spine (zero-filled months). Which window: 2024-01 to 2025-02, or include the partial 2025-03?

-- =====================================================================
-- R4. Date range of users.modified (moved from 04_users, section 5: outliers are checked on fact tables only)
-- =====================================================================
select
    min(modified) as first_modified,
    max(modified) as last_modified
from public.users;
-- 2024-01-02 to 2024-10-28: inside the deal window
-- Questions:
--   - modified is the last change of a user record; users is current state only. Does a change after 2024-09-13 (the last
--     activity) mean the user list was exported later than the activities?

-- =====================================================================
-- R5. Open questions from the time distribution (01 and 02, section 5)
-- =====================================================================
-- - 157 After Close Calls are due before the first deal reaches Closing (2024-02-02). Is the activity export from another
--   pipeline or a sample unrelated to these deals? (Question for the CRM admin.)
-- - Activities are flat from the first month while deal changes ramp up: does the activity export cover a different period
--   or population?
-- - activity_id: 11 ids repeat (22 rows, 0.48%), with different user, deal and due date in every pair (02_activity, section 2).
--   Decided (2026-10-23): duplicates, marked as a data quality issue. Cleansing can follow the process within the domain and needs
--   a review by the business stakeholder responsible for the KPIs (Sales Call 1 / 2) and the CRM data entry.
-- - Owner events lag creations (148 vs 247 in 2024-01): is the owner assigned by a routing rule after a waiting time?
