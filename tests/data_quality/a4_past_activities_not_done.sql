{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'A4', 'owner': 'sales_ops', 'quality_dimension': 'consistency', 'description': 'Found (EDA 00 A4): only about half of every activity type is marked done, although all of them are due before the export cut-off. Handled: steps 2.1 and 3.1 count a call as held when it is marked done or was due before the export ended.'}
) }}

-- the export cut-off: the last change of the deal history
with export_end as (
    select
        max(change_time) as export_last_at
    from {{ source('pipedrive', 'deal_changes') }}
)

-- one failed row per raw activity due before the cut-off and never marked done
select
    a.activity_id,
    a.type,
    a.assigned_to_user,
    a.deal_id,
    a.done,
    a.due_to
from {{ source('pipedrive', 'activity') }} a
cross join export_end e
where not a.done                     -- not marked done
    and a.due_to < e.export_last_at  -- already due at the cut-off
