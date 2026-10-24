{{ config(
    tags=['dq_known_issue', 'dq_duplicates'],
    meta={'issue': 'D3', 'owner': 'crm_admin', 'quality_dimension': 'consistency', 'description': 'D3 / DUP-2. Stage moves that go backward or repeat the same stage, expected only in the two-lifecycle deals. The funnel counts a stage once, by its first entry.'}
) }}

-- stage moves only, with the stage id typed after the filter
with stage_events as (
    select
        deal_id,
        change_time,
        {{ dbt.safe_cast('new_value', api.Column.translate_type('integer')) }} as stage_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'  -- new_value is a stage id only for this key
),

-- each move with the stage before it
stage_moves as (
    select
        deal_id,
        change_time,
        stage_id,
        lag(stage_id) over (
            partition by deal_id
            order by change_time
        ) as previous_stage_id
    from stage_events
)

-- one failed row per move that does not go forward
select
    deal_id,
    change_time,
    previous_stage_id,
    stage_id,
    case when stage_id < previous_stage_id then 'backward' else 'repeat' end as move_kind
from stage_moves
where stage_id <= previous_stage_id  -- backward or the same stage again
