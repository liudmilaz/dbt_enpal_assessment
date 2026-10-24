{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'T1', 'owner': 'crm_admin', 'quality_dimension': 'validity', 'description': 'T1. Activities of a type marked inactive (Follow Up Call): 1,133 on 2026-10-23. A deactivated type keeps its past activities; new ones should not appear.'}
) }}

-- types switched off in the CRM
with inactive_types as (
    select
        type
    from {{ source('pipedrive', 'activity_types') }}
    where active = 'No'  -- the flag is text in the export
)

-- one failed row per activity of an inactive type
select
    a.activity_id,
    a.type,
    a.due_to
from {{ source('pipedrive', 'activity') }} a
join inactive_types t
    on t.type = a.type
