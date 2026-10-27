-- One row per month and funnel step (FUNNEL_MONTH in the logical model), by cohort: month is the month the deals were
-- created in, as in Pipedrive's deal conversion report. Stage steps: distinct deals created in the month that
-- reached the stage at any time (recorded or inferred, D1), so a row reads as the conversion of that month's deals
-- and no step exceeds the one before. Call steps 2.1 and 3.1: their deal ids are not in the deal history (A2) and
-- have no creation date, so they stay counted by due month: distinct deal ids with a done call of that type due in
-- the month. The report runs from the first to the last month with any step in the data; months without deals show 0.

-- the 11 funnel steps, with the stage of each stage step and the position of each step in the funnel
with steps as (
    select
        funnel_step,
        kpi_name,
        stage_id,
        sort_order
    from {{ ref('dim_funnel_step') }}
),

-- stage steps: every stage each funnel deal reached, in the month the deal was created (DUP-6 already excluded upstream)
stage_entries as (
    select
        e.deal_id,
        e.stage_id,
        c.cohort_month as month
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }} e
    inner join {{ ref('int_pipedrive__deal_cohorts') }} c
        on c.deal_id = e.deal_id
),

-- deals per stage step and month
stage_counts as (
    select
        s.funnel_step,
        e.month,
        count(distinct e.deal_id) as deals_count
    from stage_entries e
    inner join steps s
        on s.stage_id = e.stage_id
    group by
        s.funnel_step,
        e.month
),

-- call steps: the held calls with the month they were due (no creation date for these deal ids, A2)
calls as (
    select
        funnel_step,
        deal_id,
        date_trunc('month', due_at)::date as month
    from {{ ref('int_pipedrive__sales_calls') }}
    -- held calls only: marked done. Every call in this export was due before the export ended, but only about half
    -- are marked done (A4). If Enpal confirms that reps hold calls without marking them done, add
    -- "or is_due_before_export_end" (steps 2.1 and 3.1 would about double).
    where is_done
),

-- deal ids per call step and month
call_counts as (
    select
        funnel_step,
        month,
        count(distinct deal_id) as deals_count
    from calls
    group by
        funnel_step,
        month
),

-- stage and call steps together
step_counts as (
    select
        funnel_step,
        month,
        deals_count
    from stage_counts
    union all
    select
        funnel_step,
        month,
        deals_count
    from call_counts
),

-- the report window: the first and the last month with any step in the data
report_window as (
    select
        min(month) as first_month,
        max(month) as last_month
    from step_counts
),

-- one row per month of the report window, sized by the number of months in it
months as (
    select
        dateadd(month, o.value::integer, w.first_month) as month
    from report_window w
    inner join lateral flatten(input => array_generate_range(0, datediff(month, w.first_month, w.last_month) + 1)) o
)

-- every month and step, zero-filled
select
    m.month,
    s.kpi_name,
    s.funnel_step,
    cast(s.sort_order as integer) as sort_order,  -- funnel order for charts: 1, 2, 2.1, 3, 3.1, 4 to 9
    cast(coalesce(c.deals_count, 0) as integer) as deals_count
from months m
cross join steps s
left join step_counts c
    on c.month = m.month
    and c.funnel_step = s.funnel_step
