{{ config(
    tags=['dq_check', 'dq_process'],
    meta={'owner': 'data_team', 'quality_dimension': 'completeness', 'description': 'Every deal has a creation, an owner and a stage event: 0 deals missing one on 2026-10-23. int_pipedrive__deals relies on all three.'}
) }}

-- the events each deal has
with deal_events as (
    select
        deal_id,
        sum(case when changed_field_key = 'add_time' then 1 else 0 end) as creation_events,
        sum(case when changed_field_key = 'user_id' then 1 else 0 end) as owner_events,
        sum(case when changed_field_key = 'stage_id' then 1 else 0 end) as stage_events
    from {{ source('pipedrive', 'deal_changes') }}
    group by deal_id
)

-- one failed row per deal missing one of them
select
    deal_id,
    creation_events,
    owner_events,
    stage_events
from deal_events
where creation_events = 0
    or owner_events = 0
    or stage_events = 0
