{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'A3', 'owner': 'sales_ops', 'quality_dimension': 'accuracy', 'description': 'Found (EDA 00 A3): after-close calls are due before any deal entered Closing, so they cannot have happened. Improve (sales ops): check how after-close calls are planned. Handled: after-close calls are not a funnel step; only Sales Call 1 and 2 feed the report.'}
) }}

-- the first time any deal entered Closing (stage 6)
with first_closing as (
    select
        min(change_time) as first_closed_at
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- stage moves only
        and new_value = '6'               -- into Closing
)

-- one failed row per after-close call due before it
select
    a.activity_id,
    a.deal_id,
    a.due_to
from {{ source('pipedrive', 'activity') }} a
cross join first_closing f
where a.type = 'after_close_call'  -- only calls that need a signed contract
    and a.due_to < f.first_closed_at
