{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_duplicates'],
    meta={'issue': 'D3', 'owner': 'crm_admin', 'quality_dimension': 'uniqueness', 'description': 'Found (EDA 01 §6b, 08 B5a, 00 D3): some deal_ids hold two creation events with different timestamps, owners, stage paths and lost reasons: two lifecycles under one id. Assumption: a Pipedrive merge, where the surviving deal inherits the merged deal\'s history. Improve (CRM admin): prevent merges that produce ambiguous history, or export the merge record. Handled: int_pipedrive__deals takes the first creation and the last lost reason; int_pipedrive__deal_stage_entries keeps the first entry per deal and stage. Per-owner reporting per lifecycle needs a stakeholder decision.'}
) }}

-- creation events only
with creations as (
    select
        deal_id,
        changed_field_key,
        change_time,
        new_value
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'add_time'  -- one creation per deal expected
),

-- deal_ids created more than once
repeated_deals as (
    select
        deal_id
    from creations
    group by deal_id
    having count(*) > 1
)

-- one failed row per raw creation event of a repeated deal_id
select
    c.deal_id,
    c.changed_field_key,
    c.change_time,
    c.new_value
from creations c
inner join repeated_deals r
    on r.deal_id = c.deal_id
