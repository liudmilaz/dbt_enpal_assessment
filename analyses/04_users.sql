-- TABLE enpal_raw.pipedrive.users    CLASS: dictionary (master data)    GRAIN: one user, current state only
-- Business meaning: the sales staff who own deals and activities. See vault/project/business_context.md;
-- field definitions and Pipedrive links in vault/project/data_dictionary.md.
-- Findings in short:
--   - primary key: id, declared by the task; email is not a key (4 emails shared by 2 users each)
--   - foreign keys: none; 1,757 of 1,787 users are referenced by an activity or an owner event
--   - nulls: none

-- =====================================================================
-- 1. Rows and columns
-- =====================================================================
select
    count(*) as n_rows
from enpal_raw.pipedrive.users;
-- 1787 rows; columns: id, name, email, modified

-- =====================================================================
-- 2. Primary key
-- =====================================================================
-- Declared in init.sql: id (email is not a key: 4 emails are shared, finding 4 in 07). Rows that share it:
with counted as (
    select
        *,
        count(*) over (partition by id) as n_dup
    from enpal_raw.pipedrive.users
)
select
    *
from counted
where n_dup > 1;
-- 0 rows

-- =====================================================================
-- 3. Foreign keys
-- =====================================================================
-- None: a dictionary points at nothing. Referenced by activity.assigned_to_user and the owner events in deal_changes.

-- =====================================================================
-- 4. Nulls per column
-- =====================================================================
select
    count(*) - count(id)       as id_nulls,
    count(*) - count(name)     as name_nulls,
    count(*) - count(email)    as email_nulls,
    count(*) - count(modified) as modified_nulls
from enpal_raw.pipedrive.users;
-- 0 | 0 | 0 | 0

-- =====================================================================
-- 5. Outliers
-- =====================================================================
-- Not applicable: a dictionary.

-- =====================================================================
-- 6. Descriptive analytics
-- =====================================================================
-- 6a. Users referenced by the facts
with referenced_users as (
    select
        assigned_to_user as user_id
    from enpal_raw.pipedrive.activity
    union
    select
        new_value::int as user_id
    from enpal_raw.pipedrive.deal_changes
    where changed_field_key = 'user_id'
)
select
    count(*) as n_users_referenced
from enpal_raw.pipedrive.users u
join referenced_users r
    on r.user_id = u.id;
-- 1757 of 1787
