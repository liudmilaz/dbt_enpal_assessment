---
tags:
  - project/enpal
  - type/model
---

# Logical model

The business entities behind the six raw tables and how they relate. The dbt layers (staging, intermediate, marts) implement this model. The diagram is maintained by hand and follows the dbt models as built: each model names its entity in `meta.logical_entity` (table under the diagram), and the solid lines are tested with relationships tests or, on the marts, declared as key constraints. Each relationship shows its **cardinality** (the maximum number of related instances: one or many) and its **ordinality** (the minimum: zero or one) in crow's foot notation; the counts in the labels were measured on the loaded data. A dotted line marks a relationship the business expects but the export does not support.

## Notation

| End of the line | Meaning | Mermaid (left end / right end) |
|---|---|---|
| ─┼ | One | drawn as one and only one: `\|\|` / `\|\|` |
| ─< | Many | drawn with its minimum: `}o` / `o{` or `}\|` / `\|{` |
| ─┼┼ | One (and only one) | `\|\|` / `\|\|` |
| ─○┼ | Zero or one | `\|o` / `o\|` |
| ─┼< | One or many | `}\|` / `\|{` |
| ─○< | Zero or many | `}o` / `o{` |

Read a line from one entity to the other: the symbol at the far end says how many instances of the far entity one instance of the near entity has. Example: `DEAL ||--|{ DEAL_EVENT`: one deal has one or many events; one event belongs to one and only one deal. Mermaid always draws the minimum, so a plain "One" or "Many" is shown with its ordinality.

```mermaid
erDiagram
    DEAL ||--|{ DEAL_EVENT : "has: 1 deal, 1..N events"
    DEAL ||--|{ STAGE_ENTRY : "reaches: 1 deal, 1..N stages"
    DEAL ||--|{ OWNER_ASSIGNMENT : "is assigned: 1 deal, 1..N owners"
    DEAL |o..o{ ACTIVITY : "intended: a call of a funnel deal, not supported by the data (A2)"
    DEAL ||--o{ FUNNEL_EVENT : "reaches: 1 deal, 0..N events"
    STAGE_ENTRY ||--|| FUNNEL_EVENT : "is one event"
    ACTIVITY |o--o| FUNNEL_EVENT : "Sales Call 1 or 2 is one event"
    FUNNEL_STEP ||--|{ FUNNEL_EVENT : "classifies: 1 step, 1..N events"
    STAGE ||--o{ STAGE_ENTRY : "is reached: 1 stage, 0..N entries"
    STAGE |o--o{ DEAL_EVENT : "stage move: 0..1 stage per event"
    LOST_REASON |o--o{ DEAL_EVENT : "closes: 0..1 reason per event"
    USER ||--o{ OWNER_ASSIGNMENT : "owns: 1 user, 0..N deals"
    USER ||--o{ ACTIVITY : "is assigned: 1 user, 0..N activities"
    ACTIVITY_TYPE ||--o{ ACTIVITY : "classifies: 1 type, 0..N activities"
    STAGE |o--o| FUNNEL_STEP : "steps 1 to 9"
    ACTIVITY_TYPE |o--o| FUNNEL_STEP : "steps 2.1 and 3.1"
    FUNNEL_STEP ||--|{ FUNNEL_MONTH : "report row: 1 step, 1..N months"

    DEAL {
        int deal_id PK "deal of the history, or deal id known only from activities (A2)"
        timestamp cohort_at "first add_time (D3); first activity for activity-only deal ids"
        varchar cohort_source "deal_created or first_activity"
        date cohort_month "the report month of every step of the deal"
    }
    DEAL_EVENT {
        varchar deal_change_key PK "deal_id, field key, change time"
        int deal_id FK
        int stage_id FK "stage moves"
        int lost_reason_id FK "lost reasons"
    }
    OWNER_ASSIGNMENT {
        int deal_id FK
        int owner_user_id FK
    }
    STAGE_ENTRY {
        int deal_id PK, FK
        int stage_id PK, FK
        timestamp entered_at "first entry"
        boolean is_inferred "skipped stage counted as reached (D1, D2)"
    }
    STAGE {
        int stage_id PK
    }
    LOST_REASON {
        int option_id PK
        varchar option_label
    }
    USER {
        int user_id PK
    }
    ACTIVITY {
        int activity_id PK "deduplicated (A1)"
        varchar activity_type FK
        int assigned_user_id FK
        int deal_id "not a tested foreign key (A2)"
        boolean is_done
        timestamp due_at
    }
    ACTIVITY_TYPE {
        varchar activity_type PK
        boolean is_active
    }
    FUNNEL_STEP {
        varchar funnel_step PK
        varchar kpi_name
        varchar source_type "stage or activity"
        int stage_id FK
        varchar activity_type FK
        int sort_order
    }
    FUNNEL_EVENT {
        varchar funnel_event_key PK "event_source, deal_id, funnel_step, activity_id"
        varchar event_source "stage_entry or sales_call"
        varchar funnel_step FK
        int deal_id FK
        int activity_id "calls only"
        timestamp event_at "stage entry, or the call's due time"
        boolean is_inferred "stage entries only"
        boolean is_done "calls only"
        date cohort_month "from DEAL"
    }
    FUNNEL_MONTH {
        date month PK "cohort month of the deals, for every step"
        varchar funnel_step PK, FK
        int deals_count
    }
```

| Entity | dbt models |
|---|---|
| DEAL | `int_pipedrive__deal_cohorts` (deals of the history and the calls' deal ids) |
| DEAL_EVENT, OWNER_ASSIGNMENT | `stg_pipedrive__deal_changes` (owner changes are its `user_id` rows) |
| STAGE_ENTRY | `int_pipedrive__deal_stage_entries` (recorded), `int_pipedrive__deal_stage_entries_backfilled` (with inferred stages) |
| STAGE | `stg_pipedrive__stages` |
| LOST_REASON | `stg_pipedrive__field_options` (field `lost_reason`) |
| USER | `stg_pipedrive__users` |
| ACTIVITY | `stg_pipedrive__activity`, `int_pipedrive__sales_calls` (the two call types) |
| ACTIVITY_TYPE | `stg_pipedrive__activity_types` |
| FUNNEL_STEP | `int_pipedrive__funnel_steps`, `dim_funnel_step` |
| FUNNEL_EVENT | `int_pipedrive__funnel_events` (union all of stage entries and calls, enriched with the cohort) |
| FUNNEL_MONTH | `rep_sales_funnel_monthly` |

## Relationships

Cardinality and ordinality read from the first entity to the second, then back.

| Relationship | First → second | Second → first | Measured | Consequence for the model |
|---|---|---|---|---|
| Deal : deal event | one or many | one and only one | 4 to 17 events per deal | There is no deals table: one row per deal with its first creation and cohort month is derived (`int_pipedrive__deal_cohorts`), plus one row per deal id known only from the activities, dated by its first activity (A2) |
| Deal field : deal event | zero or many | one and only one | 4 keys, all used | Typed per-key columns in staging (stage, owner, creation, lost reason) |
| Deal field : field option | zero or many | one and only one | `stage_id` 9 options, `lost_reason` 5, the others none | Options unpacked from JSON in staging |
| Deal : stage entry | one or many | one and only one | 1 to 8 stages per deal (no deal enters all 9) | Grain deal x stage, one row per stage reached; the backfill adds inferred entries (D1, D2) |
| Stage : stage entry | zero or many | one and only one | 324 to 1,995 deals per stage | `relationships` test from the stage moves to the stages |
| Stage : field option | one and only one | zero or one | 9 labels, one spelled differently (S1) | Step names from the field labels |
| Deal : owner assignment | one or many | one and only one | 1 to 3 per deal | Owner over time needs the events; `users` is current state |
| User : owner assignment | zero or many | one and only one | 1,347 owners, 1 to 7 deals each | Not needed for the report |
| Lost reason : deal | zero or many | zero or one per lifecycle | 377 to 422 deals per reason; every deal has one, 5 deals carry 2 (D3) | A closure label, not an outcome (D4); Duplicate Entry deals leave the funnel (DUP-6) |
| Lost reason : field option | one and only one | zero or one | 5 reasons | Labels from the field options |
| Activity type : activity | zero or many | one and only one | 1,124 to 1,177 per type | Join on the key string `type` |
| User : activity | zero or many | one and only one | 1 to 11 per user | `relationships` test |
| Deal : activity | zero or many (intended) | zero or one | 8 of 4,579 match (A2) | A call cannot be tied to a funnel deal; its deal id gets its own `DEAL` row, with the month of its first activity as cohort |
| Deal : funnel event | zero or many | one and only one | deals of the history: 1 to 10 events each; 2,257 of 4,556 activity-only deal ids have a call event (1 or 2), the others only other activity types | `int_pipedrive__funnel_events`: one cohort per deal, so every step adds up across months |
| Stage entry : funnel event | one and only one | zero or one | 10,580 stage entries = 10,580 events | Each stage entry (recorded or inferred) is one event (`event_source = 'stage_entry'`) |
| Activity : funnel event | zero or one | zero or one | 2,262 Sales Call 1 and 2 = 2,262 events; Follow Up and After Close Calls none | Each call, done or not, is one event (`event_source = 'sales_call'`); the report counts the done ones (A4) |
| Funnel step : funnel event | one or many | one and only one | 274 to 1,618 events per step | `relationships` test to `int_pipedrive__funnel_steps` |
| Funnel step : stage | zero or one | one and only one | 9 stage steps | `int_pipedrive__funnel_steps` with `source_type` |
| Funnel step : activity type | zero or one | zero or one | 2 call steps; Follow Up and After Close Call are none | `int_pipedrive__funnel_steps` with `source_type` |
| Funnel step : funnel month | one or many | one and only one | one row per month and step, zero-filled | Report grain (`month`, `funnel_step`); month = the cohort month of the deals for every step, counted from `FUNNEL_EVENT` |

## Assumptions reflected in the model

The model carries the default handling of the data quality issues ([[05_data_quality_issues_and_assumptions]]); each could change once the stakeholders confirm or reject it.

| Assumption | Where in the model |
|---|---|
| A deal belongs to the month it was created in (cohort), as in Pipedrive's deal conversion report | `DEAL.cohort_month` (`int_pipedrive__deal_cohorts`), carried into `FUNNEL_EVENT` and used as `FUNNEL_MONTH.month` for every step |
| Stage entries and calls are put together at the event grain before anything is counted; the report only applies the counting rules | `FUNNEL_EVENT` (`int_pipedrive__funnel_events`) |
| A deal with two lifecycles is one deal, counted once per stage, in the month of its first creation (D3) | `DEAL` (first `add_time`), `STAGE_ENTRY` (first entry) |
| A skipped stage counts as reached (D1, D2) | `STAGE_ENTRY.is_inferred` |
| Duplicate Entry deals leave the funnel (DUP-6) | filtered in staging, before `DEAL` |
| Calls cannot be linked to the funnel deals (A2); their deal ids belong to the month of their first activity, and calls count only when done (A4) | `DEAL : ACTIVITY` stays dotted; `DEAL.cohort_source = 'first_activity'`; `FUNNEL_EVENT.is_done` |
| The lost reason is a closure label, not an outcome (D4) | `LOST_REASON` is not used in the report |
