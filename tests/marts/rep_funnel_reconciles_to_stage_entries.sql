{{ config(
    meta={'quality_dimension': 'accuracy', 'description': 'Per stage step, the monthly counts of the report add up to the deals that reached the stage in the report window (each deal counts once per stage, in the month of its first entry).'}
) }}

-- the report's total per stage step
with report_totals as (
    select
        r.funnel_step,
        sum(r.deals_count) as report_deals
    from {{ ref('rep_sales_funnel_monthly') }} r
    join {{ ref('dim_funnel_step') }} s
        on s.funnel_step = r.funnel_step
    where s.source_type = 'stage'  -- stage steps only; calls are counted per month, not per deal
        {% if var('step_1_date') == 'created' %}and s.stage_id <> 1{% endif %}
    group by r.funnel_step
),

-- distinct deals per stage whose first entry falls in the report window
entry_totals as (
    select
        s.funnel_step,
        count(distinct e.deal_id) as entered_deals
    from {{ ref('int_pipedrive__deal_stage_entries_backfilled') }} e
    join {{ ref('dim_funnel_step') }} s
        on s.stage_id = e.stage_id
    -- match the report's DUP-6 exclusion
    inner join {{ ref('int_pipedrive__funnel_deals') }} f
        on f.deal_id = e.deal_id
    where date_trunc('month', e.entered_at) between '{{ var("report_start_month") }}' and '{{ var("report_end_month") }}'
    group by s.funnel_step
)

-- one failed row per stage step whose totals differ
select
    r.funnel_step,
    r.report_deals,
    e.entered_deals
from report_totals r
join entry_totals e
    on e.funnel_step = r.funnel_step
where r.report_deals <> e.entered_deals
