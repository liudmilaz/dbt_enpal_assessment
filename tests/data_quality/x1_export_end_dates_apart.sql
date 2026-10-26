{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_export'],
    meta={'issue': 'X1', 'owner': 'crm_admin', 'quality_dimension': 'freshness', 'description': 'Found (EDA 00 X1, 07 #24): the activity export ends months before the deal history, although both come from one CRM. Handled: the report keeps the late months, zero-filled for the call steps 2.1 and 3.1.'}
) }}

-- the end of the deal history: the export cut-off
with deal_changes_end as (
    select
        max(change_time) as deal_changes_last_at
    from {{ source('pipedrive', 'deal_changes') }}
),

-- the end of the activity export
activity_end as (
    select
        max(due_to) as activity_last_at
    from {{ source('pipedrive', 'activity') }}
)

-- one failed row when the activity export ends more than 31 days before the deal history (the grain is the table)
select
    'activity' as table_name,
    a.activity_last_at,
    e.deal_changes_last_at,
    datediff('day', a.activity_last_at, e.deal_changes_last_at) as days_apart
from activity_end a
cross join deal_changes_end e
where a.activity_last_at < {{ dbt.dateadd('day', -31, 'e.deal_changes_last_at') }}  -- more than a month apart
