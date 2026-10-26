---
tags:
  - project/enpal
  - type/model
---

# Logical model

The business entities behind the six raw tables and how they relate, before any dbt model is designed. The dbt layers (staging, intermediate, marts) implement this model. Each relationship shows its **cardinality** (the maximum number of related instances: one or many) and its **ordinality** (the minimum: zero or one) in crow's foot notation; the counts in the labels were measured on the loaded data. A dotted line marks a relationship the business expects but the export does not support.

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
    DEAL ||--|{ DEAL_EVENT : "has: 1 deal, 1..N events (4 to 17)"
    DEAL_FIELD ||--o{ DEAL_EVENT : "classifies: 1 field, 0..N events"
    DEAL_FIELD ||--o{ FIELD_OPTION : "lists: 1 field, 0..N options (2 of 4 fields)"
    DEAL ||--|{ STAGE_ENTRY : "enters: 1 deal, 1..N stages (1 to 8)"
    STAGE ||--o{ STAGE_ENTRY : "is entered: 1 stage, 0..N entries"
    STAGE |o--|| FIELD_OPTION : "is labelled: 1 option per stage, 0..1 stage per option"
    DEAL ||--|{ OWNER_ASSIGNMENT : "is assigned: 1 deal, 1..N times (1 to 3)"
    USER ||--o{ OWNER_ASSIGNMENT : "owns: 1 user, 0..N deals (0 to 7)"
    LOST_REASON |o--o{ DEAL : "closes: 0..1 reason per lifecycle, 0..N deals"
    LOST_REASON |o--|| FIELD_OPTION : "is listed: 1 option per reason, 0..1 reason per option"
    ACTIVITY_TYPE ||--o{ ACTIVITY : "classifies: 1 type, 0..N activities"
    USER ||--o{ ACTIVITY : "is assigned: 1 user, 0..N activities (0 to 11)"
    DEAL |o..o{ ACTIVITY : "intended: 0..1 deal, 0..N activities (8 of 4,579 match)"
    FUNNEL_STEP ||--o| STAGE : "steps 1 to 9: 1 step per stage, 0..1 stage per step"
    FUNNEL_STEP |o--o| ACTIVITY_TYPE : "steps 2.1 and 3.1: 0..1 each way"
    FUNNEL_STEP ||--|{ FUNNEL_MONTH : "report row: 1 step, 1..N months"

    DEAL {
        int deal_id PK
        timestamp created_at "first add_time"
        bool has_two_lifecycles
    }
    DEAL_EVENT {
        int deal_id FK
        text changed_field_key FK
        timestamp change_time
        text new_value
    }
    STAGE_ENTRY {
        int deal_id FK
        int stage_id FK
        timestamp entered_at "first entry"
        bool is_inferred "backfilled"
    }
    STAGE {
        int stage_id PK
        text stage_name
    }
    OWNER_ASSIGNMENT {
        int deal_id FK
        int user_id FK
        timestamp assigned_at
    }
    USER {
        int user_id PK
        text name
        text email "not unique"
    }
    LOST_REASON {
        int reason_id PK
        text label
    }
    DEAL_FIELD {
        text field_key PK
        text name
    }
    FIELD_OPTION {
        text field_key FK
        int option_id
        text label
    }
    ACTIVITY {
        int activity_id PK "deduplicated: latest due_at per id"
        text type FK
        int assigned_user_id FK
        int deal_id "intended FK"
        bool is_done
        timestamp due_at
    }
    ACTIVITY_TYPE {
        text type PK "key string, 1-1 with id"
        int id
        text name
        bool is_active
    }
    FUNNEL_STEP {
        text funnel_step PK
        text kpi_name
    }
    FUNNEL_MONTH {
        date month PK
        text funnel_step PK
        int deals_count
    }
```

## Relationships

Cardinality and ordinality read from the first entity to the second, then back.

| Relationship | First → second | Second → first | Measured | Consequence for the model |
|---|---|---|---|---|
| Deal : deal event | one or many | one and only one | 4 to 17 events per deal | A deal table is derived (`int_pipedrive__deals`); there is no deals table |
| Deal field : deal event | zero or many | one and only one | 4 keys, all used | Typed per-key columns in staging (stage, owner, creation, lost reason) |
| Deal field : field option | zero or many | one and only one | `stage_id` 9 options, `lost_reason` 5, the others none | Options unpacked from JSON in staging |
| Deal : stage entry | one or many | one and only one | 1 to 8 stages per deal (no deal enters all 9) | Grain deal x stage, first entry; the backfill adds inferred entries |
| Stage : stage entry | zero or many | one and only one | 324 to 1,995 deals per stage | `relationships` test from the stage moves to the stages |
| Stage : field option | one and only one | zero or one | 9 labels, one spelled differently (S1) | Step names from the field labels |
| Deal : owner assignment | one or many | one and only one | 1 to 3 per deal | Owner over time needs the events; `users` is current state |
| User : owner assignment | zero or many | one and only one | 1,347 owners, 1 to 7 deals each | Not needed for the report |
| Lost reason : deal | zero or many | zero or one per lifecycle | 377 to 422 deals per reason; every deal has one, 5 deals carry 2 (D3) | A closure label, not an outcome (D4); Duplicate Entry deals leave the funnel (DUP-6) |
| Lost reason : field option | one and only one | zero or one | 5 reasons | Labels from the field options |
| Activity type : activity | zero or many | one and only one | 1,124 to 1,177 per type | Join on the key string `type` |
| User : activity | zero or many | one and only one | 1 to 11 per user | `relationships` test |
| Deal : activity | zero or many (intended) | zero or one | 8 of 4,579 match (A2) | Calls counted by due month, not per funnel deal |
| Funnel step : stage | zero or one | one and only one | 9 stage steps | `int_pipedrive__funnel_steps` with `source_type` |
| Funnel step : activity type | zero or one | zero or one | 2 call steps; Follow Up and After Close Call are none | `int_pipedrive__funnel_steps` with `source_type` |
| Funnel step : funnel month | one or many | one and only one | one row per month and step, zero-filled | Report grain (`month`, `funnel_step`) |
