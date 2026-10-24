{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D5', 'owner': 'crm_admin', 'quality_dimension': 'accuracy', 'description': 'D5. Deal changes at the exact clock time of the deal creation (generated history). A falling count means real timestamps arrive.'}
) }}

-- each deal's first creation time
with created as (
    select
        deal_id,
        min(change_time) as created_at
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'add_time'  -- creation events only
    group by deal_id
)

-- one failed row per change at the creation clock time
select
    d.deal_id,
    d.changed_field_key,
    d.change_time
from {{ source('pipedrive', 'deal_changes') }} d
join created c
    on c.deal_id = d.deal_id
where cast(d.change_time as time) = cast(c.created_at as time)  -- same time of day as the creation
