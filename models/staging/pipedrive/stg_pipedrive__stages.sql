-- One row per pipeline stage (STAGE in the logical model). The source spelling is kept (S1:
-- 'Qualified lead' here, 'Qualified Lead' in fields); the report uses the task's step names.

-- the raw stages
with source as (
    select
        stage_id,
        stage_name
    from {{ source('pipedrive', 'stages') }}
)

select
    stage_id,
    stage_name
from source
