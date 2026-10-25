{{ config(
    tags=['dq_known_issue', 'dq_duplicates'],
    meta={'issue': 'D3', 'owner': 'crm_admin', 'quality_dimension': 'consistency', 'description': 'Found (EDA 08 B5a, 00 D3): in the two-lifecycle deals the first lifecycle was lost and the second went on. Improve (CRM admin): as D3. Handled: the lost reason is not used for the funnel; int_pipedrive__deals keeps the last one.'}
) }}

-- the last stage move per deal
with last_stage_moves as (
    select
        deal_id,
        max(change_time) as last_stage_at
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- stage moves only
    group by deal_id
),

-- the lost reasons
lost_reasons as (
    select
        deal_id,
        change_time as lost_at
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'lost_reason'  -- lost reasons only
)

-- one failed row per lost reason followed by a stage move
select
    l.deal_id,
    l.lost_at,
    s.last_stage_at
from lost_reasons l
inner join last_stage_moves s
    on s.deal_id = l.deal_id
where l.lost_at < s.last_stage_at  -- the deal moved on after it was lost
