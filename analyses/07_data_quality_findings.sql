-- OVERALL DATA QUALITY FINDINGS for the six raw Pipedrive tables.
-- One result row per check. violations = number of rows (or deals, ids, users: see the finding text) that break the rule.
-- result: pass (0 violations), flag (violations found) or info (expected or descriptive, not an error).
-- class: field (nulls, domain, spelling), record (keys, duplicates), referential (foreign keys), business logic (sequence, meaning), coverage.
-- severity: proposed dbt test severity. error = our own pipeline would be wrong; warn = known upstream defect, fixed in staging; info = documented only.
-- detail_in: the file and section of the detail query.
-- Business context: vault/project/business_context.md.
--
-- Not queryable (not in the export): deal status (open, won, lost), pipeline, value, person and organization, who changed a field,
-- the previous value, and when an activity was completed. See vault/project/findings.md (Pipedrive terms).

-- ---------- shared building blocks ----------
with deal_changes_base as materialized (  -- read deal_changes once; every per-key CTE below filters this copy instead of scanning the table again
    select
        deal_id,
        change_time,
        changed_field_key,
        new_value
    from public.deal_changes
),
stage_events as (  -- filter first: only stage events, so the cast to int below is safe
    select
        deal_id,
        change_time,
        new_value::int as stage_id,
        new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as move
    from deal_changes_base
    where changed_field_key = 'stage_id'
),
deal_stages as (
    select
        deal_id,
        max(stage_id) as highest_stage,
        max(change_time) as last_stage_at,
        (array_agg(stage_id order by change_time))[1] as first_stage
    from stage_events
    group by 1
),
deal_events as (
    select
        deal_id,
        min(change_time) filter (where changed_field_key = 'add_time') as created_at,
        count(*) filter (where changed_field_key = 'add_time') as n_created,
        count(*) filter (where changed_field_key = 'lost_reason') as n_lost_reasons
    from deal_changes_base
    group by 1
),
owner_events as (  -- filter first: only owner events, so the cast to int is safe
    select
        new_value::int as user_id
    from deal_changes_base
    where changed_field_key = 'user_id'
),
lost_reasons as (  -- filter first: only lost-reason events
    select
        deal_id,
        new_value::int as reason_id,
        change_time
    from deal_changes_base
    where changed_field_key = 'lost_reason'
),
stage_ties as (
    select
        deal_id,
        change_time
    from stage_events
    group by 1, 2
    having count(*) > 1
),
repeated_activity_ids as (
    select
        activity_id
    from public.activity
    group by 1
    having count(*) > 1
),
shared_emails as (
    select
        email
    from public.users
    group by 1
    having count(*) > 1
),
deal_ids as (
    select distinct
        deal_id
    from deal_changes_base
),
stage_labels as (  -- unpack the JSON array once: one row per stage option
    select
        o.id as stage_id,
        o.label as stage_label
    from public.fields f
    cross join jsonb_to_recordset(f.field_value_options) as o(id int, label text)  -- typed columns declared once
    where f.field_key = 'stage_id'  -- unpack only the stage field's array
),
null_rows as (
    select
        count(*) as n_rows
    from deal_changes_base t
    where not (t is not null)
    union all
    select
        count(*) as n_rows
    from public.activity t
    where not (t is not null)
    union all
    select
        count(*) as n_rows
    from public.activity_types t
    where not (t is not null)
    union all
    select
        count(*) as n_rows
    from public.users t
    where not (t is not null)
    union all
    select
        count(*) as n_rows
    from public.stages t
    where not (t is not null)
    union all
    select
        count(*) as n_rows
    from public.fields
    where id is null
        or field_key is null
        or name is null
),
referenced_users as (
    select
        assigned_to_user as user_id
    from public.activity
    union
    select
        user_id
    from owner_events
),
stage_months as (
    select distinct
        date_trunc('month', change_time) as month
    from stage_events
),
activity_months as (
    select distinct
        date_trunc('month', due_to) as month
    from public.activity
),

-- ---------- one row per finding ----------
findings as (
    -- record: keys and duplicates
    select
        1 as no,
        'activity' as tbl,
        'record' as class,
        'full-row duplicates (a table loaded twice)' as finding,
        count(*) - count(distinct (activity_id, type, assigned_to_user, deal_id, done, due_to)) as violations,
        'error' as severity,
        '02_activity 2' as detail_in
    from public.activity
    union all

    select
        2 as no,
        'deal_changes' as tbl,
        'record' as class,
        'duplicate events on (deal_id, field key, time)' as finding,
        count(*) - count(distinct (deal_id, changed_field_key, change_time)) as violations,
        'error' as severity,
        '01_deal_changes 2' as detail_in
    from deal_changes_base
    union all

    select
        3 as no,
        'activity' as tbl,
        'record' as class,
        'activity_id repeated (ids): duplicates, data quality issue; cleansing per domain process after business stakeholder review' as finding,
        count(*) as violations,
        'warn' as severity,
        '02_activity 2' as detail_in
    from repeated_activity_ids
    union all

    select
        4 as no,
        'users' as tbl,
        'record' as class,
        'rows sharing an email (4 emails, 2 users each)' as finding,
        count(*) as violations,
        'warn' as severity,
        '04_users 2' as detail_in
    from public.users u
    join shared_emails e
        on e.email = u.email
    union all

    select
        5 as no,
        'deal_changes' as tbl,
        'record' as class,
        'deals with two creation events (add_time)' as finding,
        count(*) filter (where n_created > 1) as violations,
        'warn' as severity,
        '01_deal_changes 6b' as detail_in
    from deal_events
    union all

    select
        6 as no,
        'deal_changes' as tbl,
        'record' as class,
        'deals with two lost_reason events' as finding,
        count(*) filter (where n_lost_reasons > 1) as violations,
        'warn' as severity,
        '08 B5a' as detail_in
    from deal_events
    union all

    select
        7 as no,
        'deal_changes' as tbl,
        'record' as class,
        'same-timestamp stage events of one deal (ambiguous order)' as finding,
        count(*) as violations,
        'error' as severity,
        '01_deal_changes 6a' as detail_in
    from stage_ties
    union all

    -- field: nulls, domain, spelling
    select
        8 as no,
        'all' as tbl,
        'field' as class,
        'NULLs in required columns (all tables, fields.field_value_options excluded)' as finding,
        sum(n_rows) as violations,
        'error' as severity,
        'all tables, section 4' as detail_in
    from null_rows
    union all

    select
        9 as no,
        'fields' as tbl,
        'field' as class,
        'NULL field_value_options (expected: user_id and add_time have no option list)' as finding,
        count(*) as violations,
        'info' as severity,
        '06_fields 4' as detail_in
    from public.fields
    where field_value_options is null
    union all

    select
        10 as no,
        'stages' as tbl,
        'field' as class,
        'stage names spelled differently from the labels in fields (Qualified lead vs Qualified Lead)' as finding,
        count(*) as violations,
        'info' as severity,
        '05_stages 6a' as detail_in
    from public.stages s
    join stage_labels l
        on l.stage_id = s.stage_id
    where s.stage_name <> l.stage_label
    union all

    select
        11 as no,
        'deal_changes' as tbl,
        'field' as class,
        'stage ids outside 1 to 9' as finding,
        count(*) as violations,
        'error' as severity,
        '01_deal_changes 3' as detail_in
    from stage_events
    where stage_id not between 1 and 9
    union all

    -- referential: foreign keys
    select
        12 as no,
        'deal_changes' as tbl,
        'referential' as class,
        'owner ids (user_id events) missing from users' as finding,
        count(*) as violations,
        'error' as severity,
        '01_deal_changes 3' as detail_in
    from owner_events e
    left join public.users u
        on u.id = e.user_id
    where u.id is null
    union all

    select
        13 as no,
        'deal_changes' as tbl,
        'referential' as class,
        'stage ids missing from stages' as finding,
        count(*) as violations,
        'error' as severity,
        '01_deal_changes 3' as detail_in
    from stage_events e
    left join public.stages s
        on s.stage_id = e.stage_id
    where s.stage_id is null
    union all

    select
        14 as no,
        'activity' as tbl,
        'referential' as class,
        'assigned users missing from users' as finding,
        count(*) as violations,
        'error' as severity,
        '02_activity 3' as detail_in
    from public.activity a
    left join public.users u
        on u.id = a.assigned_to_user
    where u.id is null
    union all

    select
        15 as no,
        'activity' as tbl,
        'referential' as class,
        'activity types missing from activity_types' as finding,
        count(*) as violations,
        'error' as severity,
        '02_activity 3' as detail_in
    from public.activity a
    left join public.activity_types t
        on t.type = a.type
    where t.type is null
    union all

    select
        16 as no,
        'activity' as tbl,
        'referential' as class,
        'activity rows whose deal_id is not in deal_changes (no deals table; ids look unrelated)' as finding,
        count(*) as violations,
        'warn' as severity,
        '02_activity 3; 08 B4b' as detail_in
    from public.activity a
    left join deal_ids d
        on d.deal_id = a.deal_id
    where d.deal_id is null
    union all

    -- business logic: sequence and meaning
    select
        17 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'deals not starting at stage 1' as finding,
        count(*) as violations,
        'error' as severity,
        '01_deal_changes 6a' as detail_in
    from deal_stages
    where first_stage <> 1
    union all

    select
        18 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'stage events dated before the deal was created' as finding,
        count(*) as violations,
        'error' as severity,
        '08 B1a' as detail_in
    from stage_events s
    join deal_events d
        on d.deal_id = s.deal_id
    where s.change_time < d.created_at
    union all

    select
        19 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'lost_reason dated before the last stage event (deals)' as finding,
        count(distinct l.deal_id) as violations,
        'warn' as severity,
        '08 B5a' as detail_in
    from lost_reasons l
    join deal_stages d
        on d.deal_id = l.deal_id
    where l.change_time < d.last_stage_at
    union all

    select
        20 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'stage moves that skip a stage' as finding,
        count(*) as violations,
        'info' as severity,
        '01_deal_changes 6a' as detail_in
    from stage_events
    where move > 1
    union all

    select
        21 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'stage moves that go backward' as finding,
        count(*) as violations,
        'info' as severity,
        '01_deal_changes 6a' as detail_in
    from stage_events
    where move < 0
    union all

    select
        22 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'stage moves that repeat the same stage' as finding,
        count(*) as violations,
        'info' as severity,
        '01_deal_changes 6a' as detail_in
    from stage_events
    where move = 0
    union all

    select
        23 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'deals that reached the last stage but also carry a lost_reason (reason is not a deal outcome)' as finding,
        count(distinct l.deal_id) as violations,
        'info' as severity,
        '08 B5b' as detail_in
    from lost_reasons l
    join deal_stages d
        on d.deal_id = l.deal_id
    where d.highest_stage = 9
    union all

    select
        26 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'deals lost as Duplicate Entry (duplicates kept as deals, not merged)' as finding,
        count(distinct deal_id) as violations,
        'warn' as severity,
        '08 B5b' as detail_in
    from lost_reasons
    where reason_id = 5
    union all

    select
        27 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'Duplicate Entry deals that reached Closing or later' as finding,
        count(distinct l.deal_id) as violations,
        'warn' as severity,
        '08 B5b' as detail_in
    from lost_reasons l
    join deal_stages d
        on d.deal_id = l.deal_id
    where l.reason_id = 5
        and d.highest_stage >= 6
    union all

    select
        28 as no,
        'deal_changes' as tbl,
        'business logic' as class,
        'Unreachable Customer deals that reached Needs Assessment or later' as finding,
        count(distinct l.deal_id) as violations,
        'warn' as severity,
        '08 B5b' as detail_in
    from lost_reasons l
    join deal_stages d
        on d.deal_id = l.deal_id
    where l.reason_id = 3
        and d.highest_stage >= 3
    union all

    -- coverage
    select
        24 as no,
        'activity' as tbl,
        'coverage' as class,
        'months with stage events but no activities (activities end 2024-09-13)' as finding,
        count(*) as violations,
        'info' as severity,
        '08 B4a' as detail_in
    from stage_months s
    left join activity_months a
        on a.month = s.month
    where a.month is null
    union all

    select
        25 as no,
        'users' as tbl,
        'coverage' as class,
        'users never referenced by an activity or an owner event' as finding,
        count(*) as violations,
        'info' as severity,
        '04_users 6a' as detail_in
    from public.users u
    left join referenced_users r
        on r.user_id = u.id
    where r.user_id is null
)

select
    row_number() over (order by case class when 'record' then 1 when 'field' then 2 when 'referential' then 3 when 'business logic' then 4 else 5 end, no) as no,
    tbl,
    class,
    finding,
    violations,
    severity,
    case when violations = 0 then 'pass' when severity = 'info' then 'info' else 'flag' end as result,
    detail_in
from findings
order by no;
