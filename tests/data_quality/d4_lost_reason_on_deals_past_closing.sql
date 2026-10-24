{{ config(
    tags=['dq_known_issue', 'dq_process'],
    meta={'issue': 'D4', 'owner': 'crm_admin', 'quality_dimension': 'accuracy', 'description': 'D4. Deals with a lost reason that reached Closing or later: 1,424 of 1,995 on 2026-10-23. Every deal has a lost reason, so it is not a deal outcome and is not used for the funnel.'}
) }}

-- deals with a lost reason
with lost_deals as (
    select distinct
        deal_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'lost_reason'  -- lost reasons only
),

-- stage moves only, with the stage id typed after the filter
stage_events as (
    select
        deal_id,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as stage_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- new_value is a stage id only for this key
),

-- the furthest stage per deal
furthest_stages as (
    select
        deal_id,
        max(stage_id) as furthest_stage_id
    from stage_events
    group by deal_id
)

-- one failed row per lost deal that got to Closing or further
select
    l.deal_id,
    f.furthest_stage_id
from lost_deals l
join furthest_stages f
    on f.deal_id = l.deal_id
where f.furthest_stage_id >= 6  -- Closing or an after-sale stage
