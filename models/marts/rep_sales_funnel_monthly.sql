-- One row per month and funnel step (FUNNEL_MONTH in the logical model), by cohort: month is the month the deals were
-- created in, as in Pipedrive's deal conversion report. Stage and call steps are first put together per deal, then
-- every step is counted in the cohort month of its deal: distinct deals of that month that reached the step at any
-- time (stages recorded or inferred, D1; calls held, A4), so a row reads as the conversion of that month's deals.
-- The calls' deal ids are almost never in the deal history (A2): their cohort is the month of their first activity.
-- The report runs from the first to the last month with any step in the data; months without deals show 0.

-- the 11 funnel steps, with the stage of each stage step and the position of each step in the funnel
with steps as (
    select
        funnel_step,
        kpi_name,
        stage_id,
        sort_order
    from {{ ref('dim_funnel_step') }}
),

-- stage steps: every stage each funnel deal reached, recorded or inferred (DUP-6 already excluded upstream)
stage_events as (
    select
        s.funnel_step,
        e.deal_id
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }} e
    inner join steps s
        on s.stage_id = e.stage_id
),

-- call steps: the deal ids with a held call of each type
call_events as (
    select
        funnel_step,
        deal_id
    from {{ ref('int_pipedrive__sales_calls') }}
    -- held calls only: marked done. Every call in this export was due before the export ended, but only about half
    -- are marked done (A4). If Enpal confirms that reps hold calls without marking them done, add
    -- "or is_due_before_export_end" (steps 2.1 and 3.1 would about double).
    where is_done
),

-- deals and calls together: every step each deal reached
funnel_events as (
    select
        funnel_step,
        deal_id
    from stage_events
    union all
    select
        funnel_step,
        deal_id
    from call_events
),

-- every step in the cohort month of its deal: the creation month, or the first activity's month for the calls'
-- deal ids that the deal history does not know (A2)
cohort_events as (
    select
        f.funnel_step,
        f.deal_id,
        c.cohort_month as month
    from funnel_events f
    inner join {{ ref('int_pipedrive__deal_cohorts') }} c
        on c.deal_id = f.deal_id
),

-- deals per step and cohort month
step_counts as (
    select
        funnel_step,
        month,
        count(distinct deal_id) as deals_count
    from cohort_events
    group by
        funnel_step,
        month
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
