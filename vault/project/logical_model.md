---
tags:
  - project/enpal
  - type/model
---

# Logical model

The business entities behind the six raw tables and how they relate, **before** any dbt model is designed. The physical layers (staging, intermediate, marts) in [[model_plan]] implement this model. Cardinalities were measured on the loaded data (min to max per entity); "intended" marks a relationship the business expects but the export does not support.

```mermaid
erDiagram
    DEAL ||--|{ DEAL_EVENT : "has (4 to 17 events)"
    DEAL_FIELD ||--o{ DEAL_EVENT : "classifies (changed_field_key)"
    DEAL_FIELD ||--o{ FIELD_OPTION : "lists options (stage, lost_reason)"
    DEAL ||--|{ STAGE_ENTRY : "enters (1 to 8 stages)"
    STAGE ||--|{ STAGE_ENTRY : "is entered by (324 to 1,995 deals)"
    STAGE ||--|| FIELD_OPTION : "has label"
    DEAL ||--|{ OWNER_ASSIGNMENT : "is assigned (1 to 3 times)"
    USER ||--o{ OWNER_ASSIGNMENT : "owns (0 to 7 deals)"
    LOST_REASON ||--|{ DEAL : "closes (1 per lifecycle; 5 deals have 2)"
    LOST_REASON ||--|| FIELD_OPTION : "is option of lost_reason"
    ACTIVITY_TYPE ||--|{ ACTIVITY : "classifies (1,124 to 1,177 each)"
    USER ||--o{ ACTIVITY : "is assigned (0 to 11)"
    DEAL |o..o{ ACTIVITY : "intended link (8 of 4,579 match)"
    FUNNEL_STEP |o--o| STAGE : "steps 1 to 9"
    FUNNEL_STEP |o--o| ACTIVITY_TYPE : "steps 2.1 and 3.1"
    FUNNEL_STEP ||--o{ FUNNEL_MONTH : "one report row per month"

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
        text activity_key PK "surrogate; activity_id repeats"
        int activity_id
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

| Relationship | Type | Measured | Consequence for the model |
|---|---|---|---|
| Deal : deal event | 1 to many | 4 to 17 events per deal | A deal table must be derived (`int_pipedrive__deals`); there is no deals table |
| Deal field : deal event | 1 to many | 4 keys, all used | Typed per-key models in staging (stage, owner, creation, lost reason) |
| Deal : stage entry | 1 to many | 1 to 8 stages per deal (no deal enters all 9) | Grain deal x stage, first entry; backfill adds inferred entries |
| Stage : stage entry | 1 to many | 324 to 1,995 deals per stage | `relationships` test from entries to stages |
| Stage : field option | 1 to 1 | 9 labels, one spelling differs | Report uses the task's names |
| Deal : owner assignment | 1 to many | 1 to 3 per deal | Owner over time needs the events; `users` is current state |
| User : owner assignment | 1 to many (optional) | 1,347 owners, 1 to 7 deals each | Not needed for the report |
| Lost reason : deal | 1 to many | 377 to 422 deals per reason; 5 deals carry 2 | Not a deal outcome; not used for the funnel |
| Activity type : activity | 1 to many | 1,124 to 1,177 per type; type key is 1 to 1 with the id | Join on the key string `type` |
| User : activity | 1 to many (optional) | 1,650 users, 1 to 11 each | `relationships` test |
| Deal : activity | intended 1 to many, not supported | 8 of 4,579 match | Calls counted by due month, not per funnel deal |
| Funnel step : stage / activity type | 1 to 1 (one or the other) | 9 stage steps, 2 call steps | `dim_funnel_step` seed with `source_type` |
| Funnel step : funnel month | 1 to many | one row per month and step | Report grain (`month`, `funnel_step`), unique |
