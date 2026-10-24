-- One row per month and funnel step (FUNNEL_MONTH in the logical model): the number of deals that reached the step in
-- that month. Stage steps: distinct deals whose first entry into the stage (recorded or inferred, D1) falls in the
-- month. Call steps 2.1 and 3.1: distinct deal ids with a call of that type due in the month (A2: these ids are not the
-- funnel deals), done calls only when var calls_done_only is true. Months without deals show 0.
-- Open decisions with defaults as vars (vault/project/NOTES.md): step_1_date, calls_done_only, report window.

-- one row per month of the report window
with months as (
    select
        dateadd(month, g.month_offset, to_date('{{ var("report_start_month") }}')) as month
    from (
        select
            row_number() over (order by seq4()) - 1 as month_offset
        from table(generator(rowcount => 120))
    ) g
    where dateadd(month, g.month_offset, to_date('{{ var("report_start_month") }}'))
        <= to_date('{{ var("report_end_month") }}')  -- stop at the last month of the window
),

steps as (
    select
        funnel_step,
        kpi_name,
        source_type,
        stage_id,
        sort_order
    from {{ ref('dim_funnel_step') }}
),

-- stage steps: the month each deal first reached each stage
stage_entries as (
    select
        deal_id,
        stage_id,
        date_trunc('month', entered_at)::date as month
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }}
    {% if var('step_1_date') == 'created' %}
    where stage_id <> 1  -- step 1 comes from the creation date below
    union all
    select
        deal_id,
        1 as stage_id,
        date_trunc('month', created_at)::date as month
    from {{ ref('int_pipedrive__deals') }}
    {% endif %}
),

stage_counts as (
    select
        s.funnel_step,
        e.month,
        count(distinct e.deal_id) as deals_count
    from stage_entries e
    join steps s
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
    {% if var('calls_done_only') %}
    where is_done  -- held calls only, not planned ones
    {% endif %}
),

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
order by
    m.month,
    s.sort_order
