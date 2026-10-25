{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_duplicates'],
    meta={'issue': 'A1', 'owner': 'crm_admin', 'quality_dimension': 'uniqueness', 'description': 'Found (EDA 02 §2, 00 A1): some activity_ids are shared by unrelated activities (different user, deal and date). Improve (CRM admin): check the id generation of the export. Handled: staging keeps the row with the latest due_at per id (DUP-3) and tests activity_id unique at error.'}
) }}

-- activity_ids that occur more than once
with repeated_ids as (
    select
        activity_id
    from {{ source('pipedrive', 'activity') }}
    group by activity_id
    having count(*) > 1
)

-- one failed row per raw activity that shares its id
select
    a.activity_id,
    a.type,
    a.assigned_to_user,
    a.deal_id,
    a.done,
    a.due_to
from {{ source('pipedrive', 'activity') }} a
inner join repeated_ids r
    on r.activity_id = a.activity_id
