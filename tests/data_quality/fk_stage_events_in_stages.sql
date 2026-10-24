{{ config(
    tags=['dq_check'],
    meta={'owner': 'data_team', 'quality_dimension': 'consistency', 'description': 'Foreign key deal_changes.new_value (key stage_id) to stages.stage_id. Rows here mean a stage the funnel does not know.'}
) }}

-- stage moves only, with the stage id typed after the filter
with stage_events as (
    select
        deal_id,
        change_time,
        new_value
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- new_value is a stage id only for this key
),

stage_events_typed as (
    select
        deal_id,
        change_time,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as stage_id
    from stage_events
),

-- the reference keys
stages as (
    select
        stage_id
    from {{ source('pipedrive', 'stages') }}
)

-- one failed row per stage move into an unknown stage
select
    e.deal_id,
    e.change_time,
    e.stage_id
from stage_events_typed e
left join stages s
    on s.stage_id = e.stage_id
where s.stage_id is null  -- no matching stage
