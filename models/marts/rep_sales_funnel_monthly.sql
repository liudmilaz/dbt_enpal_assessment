-- One row per month and funnel step (FUNNEL_MONTH in the logical model): the number of deals that reached the step in
-- that month. Stage steps: distinct deals whose first entry into the stage (recorded or inferred, D1) falls in the
-- month. Call steps 2.1 and 3.1: distinct deal ids with a done call of that type due in the month (A2: these ids are
-- not the funnel deals). Months without deals show 0.
-- Open decisions with defaults as vars (vault/project/NOTES.md): step_1_date, report window.

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

-- funnel-eligible deals (DUP-6 excluded by int_pipedrive__funnel_deals)
funnel_deals as (
    select
        deal_id,
        created_at
    from {{ ref('int_pipedrive__funnel_deals') }}
),

-- stage steps: the month each funnel deal first reached each stage
stage_entries as (
    select
        e.deal_id,
        e.stage_id,
        date_trunc('month', e.entered_at)::date as month
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }} e
    inner join funnel_deals f
        on f.deal_id = e.deal_id
    {% if var('step_1_date') == 'created' %}
    where e.stage_id <> 1  -- step 1 comes from the creation date below
    union all
    select
        f.deal_id,
        1 as stage_id,
        date_trunc('month', f.created_at)::date as month
    from funnel_deals f
    {% endif %}
),

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
