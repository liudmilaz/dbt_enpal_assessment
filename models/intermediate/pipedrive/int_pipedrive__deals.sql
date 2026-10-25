-- One row per deal (DEAL and OWNER_ASSIGNMENT in the logical model): there is no deals table, so the deal is derived
-- from its change history. Known issues are handled upstream (D1/D2: backfill, DUP-3: staging dedup).
-- DUP-6 (Duplicate Entry) deals are filtered out here; D3 (two lifecycles) is handled by first-entry logic.

-- the typed change log
with changes as (
    select
        deal_id,
        changed_field_key,
        change_time,
        deal_created_at,
        owner_user_id,
        stage_id,
        lost_reason_id
    from {{ ref('stg_pipedrive__deal_changes') }}
),

-- creation, owners and lost reason per deal (aggregate once over the log)
deal_attributes as (
    select
        deal_id,
        min(deal_created_at) as created_at,
        count(deal_created_at) as creation_events,
        min_by(owner_user_id, case when owner_user_id is not null then change_time end) as first_owner_user_id,
        max_by(owner_user_id, case when owner_user_id is not null then change_time end) as last_owner_user_id,
        count(owner_user_id) as owner_changes,
        max_by(lost_reason_id, case when lost_reason_id is not null then change_time end) as last_lost_reason_id,
        max(case when lost_reason_id is not null then change_time end) as last_lost_reason_at,
        count(lost_reason_id) as lost_reason_events,
        count_if(lost_reason_id = 5) as duplicate_entry_events
    from changes
    group by deal_id
),

-- the recorded stage path per deal
stage_path as (
    select
        deal_id,
        min_by(stage_id, entered_at) as first_stage_id,
        max(stage_id) as highest_stage_id,
        min(entered_at) as first_stage_entered_at
    from {{ ref('int_pipedrive__deal_stage_entries') }}
    group by deal_id
)

select
    a.deal_id,
    a.created_at,
    a.first_owner_user_id,
    a.last_owner_user_id,
    a.owner_changes,
    s.first_stage_id,
    s.first_stage_entered_at,
    s.highest_stage_id,
    a.last_lost_reason_id,
    a.last_lost_reason_at
from deal_attributes a
inner join stage_path s
    on s.deal_id = a.deal_id
-- DUP-6: reps label accidental duplicates as "Duplicate Entry" (lost reason 5);
-- these are not real sales opportunities and are excluded from the funnel,
-- also when Duplicate Entry is the first of two lifecycles' lost reasons (D3)
where a.duplicate_entry_events = 0
