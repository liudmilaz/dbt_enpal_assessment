{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'A2', 'owner': 'crm_admin', 'quality_dimension': 'consistency', 'description': 'Found (EDA 02 §3, 00 A2, 08 B4b): activity.deal_id almost never matches a deal of the deal history; the two exports come from different deal sets. Handled: calls are counted by due month with their own deal_id, not joined to the funnel deals.'}
) }}

-- the deals of the deal history
with history_deals as (
    select distinct
        deal_id
    from {{ source('pipedrive', 'deal_changes') }}
)

-- one failed row per raw activity whose deal is not in the deal history
select
    a.activity_id,
    a.type,
    a.assigned_to_user,
    a.deal_id,
    a.done,
    a.due_to
from {{ source('pipedrive', 'activity') }} a
left join history_deals h
    on h.deal_id = a.deal_id
where h.deal_id is null  -- no matching deal
