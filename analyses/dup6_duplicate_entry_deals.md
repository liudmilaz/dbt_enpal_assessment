# DUP-6: Duplicate Entry deals

## The issue

376 of 1,995 deals (18.8%) carry `lost_reason_id = 5` ("Duplicate Entry"). In Pipedrive, a
lost reason is set when a rep marks a deal as lost. "Duplicate Entry" means the household
already has another deal in the pipeline — the lead was entered twice (web form resubmission,
partner overlap, rep mistake, import). These deals inflate funnel stage counts because the same
household is counted twice.

The export has no household identifier (no address, phone, email or contact name), so the
"original" deal cannot be matched from this data. The lost reason label is the only signal.

## SQL on raw data

### 1. Every deal has a lost reason — that's unusual

In Pipedrive, only lost deals should carry a lost reason. Won or open deals should not.

```sql
select
    count(distinct deal_id) as total_deals,
    count(distinct case when changed_field_key = 'lost_reason' then deal_id end) as with_lost_reason
from {{ source('pipedrive', 'deal_changes') }}
```

Result: 1,995 total, 1,995 with a lost reason. Every deal has one → the field is a label of the
export, not an outcome (D4).

### 2. Lost reason distribution is uniform

```sql
with lost_reasons as (
    select
        dc.deal_id,
        dc.new_value::int as lost_reason_id
    from {{ source('pipedrive', 'deal_changes') }} dc
    where dc.changed_field_key = 'lost_reason'
    qualify row_number() over (partition by dc.deal_id order by dc.change_time desc) = 1
),

labels as (
    select
        o.value:id::int as option_id,
        o.value:label::varchar as option_label
    from {{ source('pipedrive', 'fields') }} f,
        lateral flatten(input => f.field_value_options) o
    where f.field_key = 'lost_reason'
)

select
    l.option_label as lost_reason,
    lr.lost_reason_id,
    count(*) as deals,
    round(count(*) * 100.0 / sum(count(*)) over (), 1) as pct
from lost_reasons lr
inner join labels l
    on l.option_id = lr.lost_reason_id
group by l.option_label, lr.lost_reason_id
order by deals desc
```

| lost_reason          | lost_reason_id | deals | pct  |
|----------------------|----------------|-------|------|
| Unreachable Customer | 3              | 422   | 21.2 |
| Product Mismatch     | 4              | 417   | 20.9 |
| Pricing Issues       | 2              | 399   | 20.0 |
| Customer Not Ready   | 1              | 381   | 19.1 |
| Duplicate Entry      | 5              | 376   | 18.8 |

Five reasons, each ~20%. Real CRM data would be skewed. Consistent with generated data (D5).

### 3. Duplicate Entry deals reach every stage at the same rate

```sql
with dup6 as (
    select distinct deal_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'lost_reason'
        and new_value = '5'
),

highest as (
    select
        deal_id,
        max(new_value::int) as highest_stage_id
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'stage_id'
    group by deal_id
)

select
    h.highest_stage_id,
    count_if(d.deal_id is not null) as dup6,
    count_if(d.deal_id is null) as non_dup6,
    round(count_if(d.deal_id is not null) * 100.0 / count(*), 1) as dup6_pct
from highest h
left join dup6 d
    on d.deal_id = h.deal_id
group by h.highest_stage_id
order by h.highest_stage_id
```

| highest_stage_id | dup6 | non_dup6 | dup6_pct |
|------------------|------|----------|----------|
| 1                | 1    | 4        | 20.0     |
| 2                | 7    | 32       | 17.9     |
| 3                | 19   | 70       | 21.3     |
| 4                | 24   | 145      | 14.2     |
| 5                | 52   | 217      | 19.3     |
| 6                | 70   | 273      | 20.4     |
| 7                | 67   | 291      | 18.7     |
| 8                | 87   | 312      | 21.8     |
| 9                | 49   | 275      | 15.1     |

Flat 15–22% at every stage. A real duplicate would be caught early and closed at stage 1–2.
87 reached stage 8 (Follow-up/Customer Success) — not mislabeled early, just the expected
~19% of deals at that stage in generated data.

### 4. The label is applied at the deal's highest stage

```sql
with dup6_lost as (
    select
        deal_id,
        change_time as lost_reason_at
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'lost_reason'
        and new_value = '5'
),

created as (
    select
        deal_id,
        min(change_time) as created_at
    from {{ source('pipedrive', 'deal_changes') }}
    where changed_field_key = 'add_time'
    group by deal_id
),

stage_at_marking as (
    select
        dl.deal_id,
        dl.lost_reason_at,
        c.created_at,
        max(dc.new_value::int) as stage_when_marked
    from dup6_lost dl
    inner join created c
        on c.deal_id = dl.deal_id
    inner join {{ source('pipedrive', 'deal_changes') }} dc
        on dc.deal_id = dl.deal_id
        and dc.changed_field_key = 'stage_id'
        and dc.change_time <= dl.lost_reason_at
    group by dl.deal_id, dl.lost_reason_at, c.created_at
)

select
    stage_when_marked,
    count(*) as deals,
    round(avg(datediff('day', created_at, lost_reason_at)), 0) as avg_days_to_marking
from stage_at_marking
group by stage_when_marked
order by stage_when_marked
```

| stage_when_marked | deals | avg_days_to_marking |
|-------------------|-------|---------------------|
| 1                 | 1     | 30                  |
| 2                 | 7     | 68                  |
| 3                 | 19    | 85                  |
| 4                 | 24    | 91                  |
| 5                 | 52    | 99                  |
| 6                 | 70    | 103                 |
| 7                 | 67    | 106                 |
| 8                 | 87    | 116                 |
| 9                 | 49    | 116                 |

Every deal is marked at its highest stage. The deal progresses normally, then is closed as a
duplicate. Consistent with "lost reason is set when the deal is marked lost" (Pipedrive docs).

### 5. No observable duplicate pairs in the data

```sql
with deal_attrs as (
    select
        deal_id,
        min(case when changed_field_key = 'add_time' then change_time end) as created_at,
        min(case when changed_field_key = 'user_id' then new_value::int end) as first_owner_id,
        max(case when changed_field_key = 'lost_reason' and new_value = '5' then 1 else 0 end) as is_dup6
    from {{ source('pipedrive', 'deal_changes') }}
    group by deal_id
)

select count(distinct d.deal_id) as dup6_with_same_day_same_owner_pair
from deal_attrs d
inner join deal_attrs s
    on s.first_owner_id = d.first_owner_id
    and s.created_at::date = d.created_at::date
    and s.deal_id <> d.deal_id
    and s.is_dup6 = 0
where d.is_dup6 = 1
```

Result: 0. No DUP-6 deal shares a creation day and owner with a non-duplicate deal.

### 6. Lost reason never changes

```sql
select
    max(case when new_value = '5' then 1 else 0 end) as is_dup6,
    count(*) as lost_reason_events,
    count(distinct new_value) as distinct_reasons,
    count(distinct deal_id) as deals
from {{ source('pipedrive', 'deal_changes') }}
where changed_field_key = 'lost_reason'
group by deal_id
having count(*) > 1 or max(case when new_value = '5' then 1 else 0 end) = 1
order by is_dup6, lost_reason_events
```

All 376 DUP-6 deals: one event, one reason, no re-labeling.

## What this means

The lost reason is randomly generated (D5), distributed uniformly across deals and stages.
In a real scenario:
- **False negatives** are possible: a rep forgets to mark a duplicate
- **False positives** are possible: a rep uses "Duplicate Entry" to quickly close an unresponsive lead
- **No household matching** is possible from this export (no address, phone, email)

Questions for the stakeholder:
1. When a rep marks "Duplicate Entry", what triggers it — manual search, or an automated dedup rule?
2. Can the household identifier (address, phone, email) be added to the export so the warehouse can verify?
3. The 87 deals that reached stage 8 before being marked — is that normal (duplicate found late) or a label misuse?

## Decision (owner, 2026-10-25)

Exclude Duplicate Entry deals from the funnel count. Keep them in `fct_deals` with a flag for
the Deals Overview dashboard.

## Implementation

Move the exclusion from scattered Jinja conditionals in `rep_sales_funnel_monthly` into a clean
intermediate model:

1. **Create `int_pipedrive__funnel_deals`**: selects from `int_pipedrive__deals`, applies
   `where not is_duplicate_entry` (behind the existing `exclude_duplicate_entry_deals` var).
2. **Simplify `rep_sales_funnel_monthly`**: replace the three `{% if var(...) %}` blocks with an
   `inner join` to `int_pipedrive__funnel_deals` on `deal_id`.
3. **`fct_deals` unchanged**: keeps all deals with the flag.
4. **Raw-layer test unchanged**: `tests/data_quality/dup6_duplicate_entry_deals_past_closing.sql`
   monitors the issue on the source.

DAG after the change:

```
stg_pipedrive__deal_changes
  └─► int_pipedrive__deals
        ├─► int_pipedrive__funnel_deals  (DUP-6 filter)
        │     └─► rep_sales_funnel_monthly
        └─► fct_deals                    (all deals, flag for dashboard)
```
