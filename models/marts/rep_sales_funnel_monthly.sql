-- One row per month and funnel step (FUNNEL_MONTH in the logical model): the number of deals that reached the step in
-- that month. Stage steps: distinct deals whose first entry into the stage (recorded or inferred, D1) falls in the
-- month. Call steps 2.1 and 3.1: distinct deal ids with a done call of that type due in the month (A2: these ids are
-- not the funnel deals). The report runs from the first to the last month with any step in the data; months
-- without deals show 0. Step 1 is dated like every other stage: the first entry into stage 1.

-- the 11 funnel steps, with the stage of each stage step
with steps as (
    select
        funnel_step,
        kpi_name,
        stage_id
    from {{ ref('dim_funnel_step') }}
),

-- stage steps: the month each funnel deal first reached each stage (DUP-6 already excluded upstream)
stage_entries as (
    select
        deal_id,
        stage_id,
        date_trunc('month', entered_at)::date as month
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }}
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

-- call steps: distinct deal ids with a call due in the month
calls as (
    select
        funnel_step,
        deal_id,
        date_trunc('month', due_at)::date as month
    from {{ ref('int_pipedrive__sales_calls') }}
    where is_done  -- held calls only, not planned ones
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
    cast(coalesce(c.deals_count, 0) as integer) as deals_count
from months m
cross join steps s
left join step_counts c
    on c.month = m.month
    and c.funnel_step = s.funnel_step
