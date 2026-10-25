-- One row per deal (DEAL and OWNER_ASSIGNMENT in the logical model): there is no deals table, so the deal is derived
-- from its change history. Flags D1 to D3 make the known issues filterable per deal.
-- D3 (has_two_lifecycles): 5 deals carry two creation events — likely a Pipedrive merge where the surviving deal
-- inherits the merged deal's history. Each lifecycle has its own owners and stage path. The funnel counts such a
-- deal once per stage (by first entry). Per-user slicing should count the deal for each lifecycle's owner; the
-- users export has no role/team column, so the sales-vs-onboarding split needs a stakeholder conversation.

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
        count(lost_reason_id) as lost_reason_events
    from changes
    group by deal_id
),

-- the recorded stage path per deal
stage_path as (
    select
        deal_id,
        min_by(stage_id, entered_at) as first_stage_id,
        max(stage_id) as highest_stage_id,
        count(*) as recorded_stages,
        min(entered_at) as first_stage_entered_at,
        boolor_agg(stage_id = 6) as entered_closing
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
    s.recorded_stages,
    a.last_lost_reason_id,
    a.last_lost_reason_at,
    s.recorded_stages < s.highest_stage_id as has_skipped_stage,                          -- D1: fewer recorded stages than reached
    s.highest_stage_id >= 7 and not s.entered_closing as is_after_sale_without_closing,   -- D2: stage 7 to 9 without Closing
    a.creation_events > 1 as has_two_lifecycles,                                         -- D3: two creation events under one deal_id
    a.last_lost_reason_id = 5 as is_duplicate_entry                                      -- DUP-6: lost reason Duplicate Entry
from deal_attributes a
inner join stage_path s
    on s.deal_id = a.deal_id
