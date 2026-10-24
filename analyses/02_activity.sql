-- TABLE enpal_raw.pipedrive.activity    CLASS: fact    GRAIN: one planned activity (call or meeting)
-- Business meaning: calls and meetings planned for a user and a deal; Sales Call 1 and 2 are funnel steps 2.1 and 3.1.
-- See vault/project/business_context.md; field definitions and Pipedrive links in vault/project/data_dictionary.md.
-- Findings in short:
--   - primary key: none declared; activity_id repeats (11 ids, 2 rows each); the full row has no duplicates, so the model needs a surrogate key
--   - foreign keys: assigned user and type match (0 orphans); deal_id does not match the deals in deal_changes (4,571 of 4,579 rows orphaned)
--   - nulls: none
--   - outliers: no outlier month or user; flat from the first month; 157 After Close Calls are due before the first Closing
--   - descriptive: four types, about 1,100 rows each, 50% done; due dates 2024-01-01 to 2024-09-13

-- =====================================================================
-- 1. Rows and columns
-- =====================================================================
select
    count(*) as n_rows
from enpal_raw.pipedrive.activity;
-- 4579 rows; columns: activity_id, type, assigned_to_user, deal_id, done, due_to

-- =====================================================================
-- 2. Primary key
-- =====================================================================
-- No key is declared. activity_id repeats (11 ids, 2 unrelated activities each: finding 3 in 07), so the key is the full row,
-- as a surrogate key (hash of all columns). Rows that share it:
with counted as (
    select
        *,
        count(*) over (partition by activity_id, type, assigned_to_user, deal_id, done, due_to) as n_dup
    from enpal_raw.pipedrive.activity
)
select
    *
from counted
where n_dup > 1;
-- 0 rows

-- =====================================================================
-- 3. Foreign keys (rows whose value is missing in the parent)
-- =====================================================================
-- assigned_to_user -> users.id
select
    count(*) as n_orphans
from enpal_raw.pipedrive.activity a
left join enpal_raw.pipedrive.users u
    on u.id = a.assigned_to_user
where u.id is null;
-- 0

-- type -> activity_types.type (activities reference the key string, not the id)
select
    count(*) as n_orphans
from enpal_raw.pipedrive.activity a
left join enpal_raw.pipedrive.activity_types t
    on t.type = a.type
where t.type is null;
-- 0

-- deal_id -> the deals of deal_changes (there is no deals table)
with deals as (
    select distinct
        deal_id
    from enpal_raw.pipedrive.deal_changes
)
select
    count(*) as n_orphans
from enpal_raw.pipedrive.activity a
left join deals d
    on d.deal_id = a.deal_id
where d.deal_id is null;
-- 4571 of 4579: activities cannot be joined to the funnel deals

-- =====================================================================
-- 4. Nulls per column
-- =====================================================================
select
    count(*) - count(activity_id)      as activity_id_nulls,
    count(*) - count(type)             as type_nulls,
    count(*) - count(assigned_to_user) as assigned_to_user_nulls,
    count(*) - count(deal_id)          as deal_id_nulls,
    count(*) - count(done)             as done_nulls,
    count(*) - count(due_to)           as due_to_nulls
from enpal_raw.pipedrive.activity;
-- 0 | 0 | 0 | 0 | 0 | 0

-- =====================================================================
-- 5. Outliers: time distribution and volume per dimension (spikes, drops and holes)
-- =====================================================================
-- 5a. Activities per due month, with quarter and year
select
    date_trunc('month',   due_to)::date as due_month,
    date_trunc('quarter', due_to)::date as due_quarter,
    date_trunc('year',    due_to)::date as due_year,
    count(*) as nr_activities
from enpal_raw.pipedrive.activity
group by 1, 2, 3
order by 1 desc;
-- 490 to 580 per month from 2024-01 to 2024-08, 234 in 2024-09 (data ends 2024-09-13, a partial month). Flat: no ramp-up, no outlier month.

-- 5b. Activities per dimension: type and done
select
    type,
    count(*) as nr_activities,
    count_if(done) as nr_done,
    count_if(not done) as nr_not_done
from enpal_raw.pipedrive.activity
group by 1
order by 2 desc;
-- after_close_call 1177 (595 done) | meeting 1145 (568) | follow_up 1133 (567) | sc_2 1124 (560): four equal types, each half done

-- 5b. Activities per dimension: assigned user (distribution of the count per user)
with per_user as (  -- one row per user: how many activities they hold
    select
        assigned_to_user,
        count(*) as nr_activities
    from enpal_raw.pipedrive.activity
    group by 1
)
select
    nr_activities,
    count(*) as nr_users
from per_user
group by 1
order by 1;
-- 1,650 users hold 1 to 11 activities each (most 2 or 3; one user 11): no user stands out

-- 5c. Activities per dimension and month
select
    date_trunc('month', due_to)::date as due_month,
    type,
    count(*) as nr_activities
from enpal_raw.pipedrive.activity
group by 1, 2
order by 1, 2 desc;
-- 36 rows: every type in every month from 2024-01 to 2024-09.
-- every type is flat at 115 to 165 per month from the first month; done stays at about half.
-- After Close Call has 143 activities in 2024-01, but the first deal reaches Closing on 2024-02-02 (157 after-close calls are due
-- before it): another sign that the activities do not belong to these deals.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================
-- Covered by section 5 (types, done, users, months).
