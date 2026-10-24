{{ config(
    tags=['dq_known_issue', 'dq_export'],
    meta={'issue': 'X1', 'owner': 'crm_admin', 'quality_dimension': 'freshness', 'description': 'Found (EDA 00 X1, 07 #24): the tables were exported at different times and end on different dates. Improve (CRM admin): one cut-off for all exports. Handled: the report keeps the late months, zero-filled for the call steps.'}
) }}

-- last date per table
with table_ends as (
    select
        'deal_changes' as table_name,
        max(change_time) as last_at
    from {{ source('pipedrive', 'deal_changes') }}
    union all
    select
        'activity' as table_name,
        max(due_to) as last_at
    from {{ source('pipedrive', 'activity') }}
    union all
    select
        'users' as table_name,
        max(modified) as last_at
    from {{ source('pipedrive', 'users') }}
),

-- the reference: the end of the deal history
deal_changes_end as (
    select
        last_at as deal_changes_last_at
    from table_ends
    where table_name = 'deal_changes'
)

-- one failed row per table that ends more than 31 days earlier
select
    t.table_name,
    t.last_at,
    e.deal_changes_last_at
from table_ends t
cross join deal_changes_end e
where t.last_at < {{ dbt.dateadd('day', -31, 'e.deal_changes_last_at') }}  -- 31 days before the end of the deal history
