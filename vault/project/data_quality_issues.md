---
tags:
  - project/enpal
  - type/data-quality
---

# Data quality issues: query, business case, fix

One section per issue found in the exploratory analysis: a query that lists the affected raw rows at the table's own grain (Snowflake, `ENPAL_RAW.PIPEDRIVE`), the result, my assumption of the business case, and how the pipeline cleanses or transforms it. Every business case is an **assumption to confirm with the stakeholders** ([[approach -- keep]]). Format checks (one type per key in `deal_changes.new_value`, the 'Yes' / 'No' text flag of `activity_types.active`) are not listed here: they are generic dbt tests in the source and staging YAML. The same issues are tested in `tests/data_quality/` and shown in the Elementary report; decisions are in [[cleansing_proposals]].

| Issue | Table | Result |
|---|---|---|
| [[#D1: Skipped stages\|D1]] Skipped stages | deal_changes | 2,502 stage moves (84% of deals) |
| [[#D2: After-sale without a recorded Closing\|D2]] After-sale without a recorded Closing | deal_changes | 3,207 stage moves of 683 deals |
| [[#D3: One deal_id, two lifecycles\|D3]] One deal_id, two lifecycles | deal_changes | 10 lifecycles of 5 deals |
| [[#D4: Lost reason on deals that reached Closing or later\|D4]] Lost reason on deals that reached Closing or later | deal_changes | 1,429 lost reasons |
| [[#D5: Changes at the creation's clock time\|D5]] Changes at the creation's clock time | deal_changes | 13,373 of 13,406 changes after creation |
| [[#DUP-6: Duplicate Entry deals that reached Closing\|DUP-6]] Duplicate Entry deals that reached Closing | deal_changes | 274 deals |
| [[#A1: One activity_id, two activities\|A1]] One activity_id, two activities | activity | 22 activities, 11 ids |
| [[#A2: Activities not linked to the deal history\|A2]] Activities not linked to the deal history | activity | 4,571 of 4,579 activities |
| [[#A3: After Close Calls before any Closing\|A3]] After Close Calls before any Closing | activity | 157 calls |
| [[#A4: Past activities never marked done\|A4]] Past activities never marked done | activity | 2,289 activities (about half of every type) |
| [[#T1: Inactive activity type in use\|T1]] Inactive activity type in use | activity, activity_types | 1,133 Follow Up Calls |
| [[#U1: Users sharing an email\|U1]] Users sharing an email | users | 8 users, 4 emails |
| [[#U2: Several owners per deal\|U2]] Several owners per deal | deal_changes | 501 deals with more than one owner |
| [[#S1: Stage spelled two ways\|S1]] Stage spelled two ways | stages, fields | stage 2: 'Qualified lead' vs 'Qualified Lead' |
| [[#X1: Exports end on different dates\|X1]] Exports end on different dates | deal_changes, activity | creations and calls end 2024-09-13, owners 2024-11-02, stage moves 2025-02-24, lost reasons 2025-03-11 |

## D1: Skipped stages

**Table:** `deal_changes`. **Grain:** one row per stage move that jumps over at least one stage, with the skipped stages and the deal's recorded path. **Result:** 2,502 stage moves (84% of deals).

```sql
-- stage moves that jump over at least one stage, with the skipped stages and the deal's recorded path
select
    deal_id,
    change_time,
    lag(new_value::int) over (partition by deal_id order by change_time) as previous_stage_id,
    new_value::int as stage_id,
    array_to_string(array_generate_range(previous_stage_id + 1, stage_id), ',') as skipped_stage_ids,  -- stages between the two moves
    listagg(new_value, '>') within group (order by change_time) over (partition by deal_id) as recorded_stages  -- every stage the deal entered
from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
where changed_field_key = 'stage_id'  -- stage moves only
qualify stage_id - previous_stage_id > 1  -- skipped at least one stage
order by
    deal_id,
    change_time
```

**Business case (assumption):** Data entry behaviour, not a system error: with a high workload, reps update the pipeline after the fact and move a deal several stages at once. Pipedrive allows this unless the stages are mandatory.

**Cleansing / transformation:** Count a skipped stage as reached (`is_inferred`), dated by the deal's earliest entry into a higher stage.

## D2: After-sale without a recorded Closing

**Table:** `deal_changes`. **Grain:** the stage moves of deals that reached stage 7 to 9 but never stage 6. **Result:** 3,207 stage moves of 683 deals.

```sql
-- stage moves of deals that reached an after-sale stage (7 to 9) without a recorded Closing (6)
select
    deal_id,
    change_time,
    new_value as stage_id
from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
where changed_field_key = 'stage_id'  -- stage moves only
qualify max(new_value::int) over (partition by deal_id) >= 7  -- after-sale reached
    and count_if(new_value = '6') over (partition by deal_id) = 0  -- Closing never recorded
order by
    deal_id,
    change_time
```

**Business case (assumption):** Same behaviour as D1 for Closing: the contract was signed (installation needs it), but the rep skipped the stage. Or after-sales runs in a separate pipeline that the export does not include.

**Cleansing / transformation:** Count Closing as reached (inferred) when a deal reached an after-sale stage.

## D3: One deal_id, two lifecycles

**Table:** `deal_changes`. **Grain:** one row per deal and lifecycle (each lifecycle has its own creation clock time). **Result:** 10 lifecycles of 5 deals.

```sql
-- one lifecycle per creation of a deal created more than once, identified by its clock time (D5)
with lifecycles as (
    select
        deal_id,
        change_time::time as clock_time,
        row_number() over (partition by deal_id order by change_time) as lifecycle_no
    from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
    where changed_field_key = 'add_time'  -- creations only
    qualify count(*) over (partition by deal_id) > 1  -- deals created more than once
)

-- per deal and lifecycle: creation and lost reason
select
    l.deal_id,
    l.lifecycle_no,
    min(d.change_time) as created_at,
    max(case when d.changed_field_key = 'lost_reason' then d.new_value end) as lost_reason_id
from lifecycles l
inner join ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES d
    on d.deal_id = l.deal_id
    and d.change_time::time = l.clock_time  -- the lifecycle's own clock time
group by
    l.deal_id,
    l.lifecycle_no
order by
    l.deal_id,
    l.lifecycle_no
```

**Business case (assumption):** Two deals were merged in Pipedrive: the deal that remains keeps one id and both histories. Business reason: the same household contacted Enpal twice through different channels (for example the web form and a partner or comparison site), two reps worked the two deals in parallel, and when the duplicate was found the deals were merged instead of one being closed. The two lifecycles overlap in time, which fits two parallel deals rather than a customer who came back later.

**Cleansing / transformation:** Count each deal once per stage, by its first entry.

## D4: Lost reason on deals that reached Closing or later

**Table:** `deal_changes`. **Grain:** one row per lost reason of a deal that reached Closing or an after-sale stage. **Result:** 1,429 lost reasons.

```sql
-- lost reasons on deals that reached Closing (6) or later
select
    deal_id,
    change_time,
    new_value as lost_reason_id
from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
qualify changed_field_key = 'lost_reason'  -- lost reasons only
    and max(iff(changed_field_key = 'stage_id', try_cast(new_value as int), null)) over (partition by deal_id) >= 6  -- Closing or later reached
order by
    deal_id,
    change_time
```

**Business case (assumption):** The export fills a lost reason for every deal, also for deals that reached Closing. In Pipedrive only lost deals have one.

**Cleansing / transformation:** Keep the lost reason as a closure label; do not use it as an outcome.

## D5: Changes at the creation's clock time

**Table:** `deal_changes`. **Grain:** one row per change after the creation that falls on the creation's time of day. **Result:** 13,373 of 13,406 changes after creation.

```sql
-- changes after the creation that happen at the creation's clock time
select
    deal_id,
    change_time,
    changed_field_key,
    new_value
from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
qualify changed_field_key <> 'add_time'  -- changes after the creation
    and change_time::time = min(iff(changed_field_key = 'add_time', change_time, null)) over (partition by deal_id)::time  -- same time of day as the creation
order by
    deal_id,
    change_time
```

**Business case (assumption):** Every change of a deal is recorded at the time of day of its creation, so the date of a change is reliable, its time of day is not.

**Cleansing / transformation:** Use dates only, never durations between stages.

**Remark:** Deals whose stages were moved within a short time, most likely because reps kept notes locally and entered them into Pipedrive later, can distort the results below the monthly grain, for example by week. An impact and driver analysis, also per user, would show whether there is a pattern in this behaviour, and whether to approach the stakeholders who report on the funnel KPIs proactively: explain how the calculation works, and agree whether to adjust the calculation, the process, or the guidance for data entry.


## DUP-6: Duplicate Entry deals that reached Closing

**Table:** `deal_changes`. **Grain:** one row per Duplicate Entry lost reason of a deal that reached Closing or later. **Result:** 274 deals.

```sql
-- Duplicate Entry lost reasons on deals that reached Closing (6) or later
select
    deal_id,
    change_time,
    new_value as lost_reason_id
from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
qualify changed_field_key = 'lost_reason'
    and new_value = '5'  -- Duplicate Entry
    and max(iff(changed_field_key = 'stage_id', try_cast(new_value as int), null)) over (partition by deal_id) >= 6  -- Closing or later reached
order by
    deal_id,
    change_time
```

**Business case (assumption):** Reps notice a duplicate late, after working the deal, or use Duplicate Entry for other cases.

**Cleansing / transformation:** Dedup deals in staging.

## A1: One activity_id, two activities

**Table:** `activity`. **Grain:** one row per activity that shares its id. **Result:** 22 activities, 11 ids.

```sql
-- activities that share their activity_id with another activity
select
    activity_id,
    type,
    assigned_to_user,
    deal_id,
    done,
    due_to
from ENPAL_RAW.PIPEDRIVE.ACTIVITY
qualify count(*) over (partition by activity_id) > 1  -- id used more than once
order by
    activity_id,
    due_to
```

**Business case (assumption):** The export gives two different activities the same id.

**Cleansing / transformation:** Keep one row per activity id, the one with the latest due date.

## A2: Activities not linked to the deal history

**Table:** `activity`. **Grain:** one row per activity whose deal_id is not in deal_changes. **Result:** 4,571 of 4,579 activities.

```sql
-- the deals of the deal history
with history_deals as (
    select distinct
        deal_id
    from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
)

-- activities whose deal is not in the deal history
select
    a.activity_id,
    a.type,
    a.deal_id,
    a.due_to
from ENPAL_RAW.PIPEDRIVE.ACTIVITY a
left join history_deals h
    on h.deal_id = a.deal_id
where h.deal_id is null  -- no matching deal
order by
    a.due_to
```

**Business case (assumption):** Activities and deals were exported from different sets of deals.

**Cleansing / transformation:** Count calls by due month with their own deal id; do not join them to the funnel deals.

## A3: After Close Calls before any Closing

**Table:** `activity`. **Grain:** one row per After Close Call due before the first Closing of any deal. **Result:** 157 calls.

```sql
-- the first Closing of any deal
with first_closing as (
    select
        min(change_time) as first_closing_at
    from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
    where changed_field_key = 'stage_id'
        and new_value = '6'  -- Closing
)

-- After Close Calls due before any deal was closed
select
    a.activity_id,
    a.deal_id,
    a.due_to,
    c.first_closing_at
from ENPAL_RAW.PIPEDRIVE.ACTIVITY a
cross join first_closing c
where a.type = 'after_close_call'  -- After Close Call
    and a.due_to < c.first_closing_at  -- before any Closing
order by
    a.due_to
```

**Business case (assumption):** These calls follow deals that are not in this export (see A2).

**Cleansing / transformation:** No change; After Close Call is not a funnel step.

## A4: Past activities never marked done

**Table:** `activity`. **Grain:** one row per activity due before the export cut-off and not done. **Result:** 2,289 activities (about half of every type).

```sql
-- the export cut-off: the last change of the deal history
with export_end as (
    select
        max(change_time) as export_last_at
    from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
)

-- activities due before the cut-off and never marked done
select
    a.activity_id,
    a.type,
    a.due_to,
    a.done
from ENPAL_RAW.PIPEDRIVE.ACTIVITY a
cross join export_end e
where not a.done  -- not marked done
    and a.due_to < e.export_last_at  -- already due
order by
    a.due_to
```

**Business case (assumption):** Data entry behaviour: with a high workload, reps hold the call but do not mark it as done.

**Cleansing / transformation:** Count done calls only.

## T1: Inactive activity type in use

**Table:** `activity, activity_types`. **Grain:** one row per activity of a type with active = 'No'. **Result:** 1,133 Follow Up Calls.

```sql
-- activities of an inactive type
select
    a.activity_id,
    a.type,
    t.active,
    a.due_to
from ENPAL_RAW.PIPEDRIVE.ACTIVITY a
inner join ENPAL_RAW.PIPEDRIVE.ACTIVITY_TYPES t
    on t.type = a.type
where t.active = 'No'  -- type deactivated; 'Yes' / 'No' is text
order by
    a.due_to
```

**Business case (assumption):** Normal Pipedrive behaviour: a deactivated activity type keeps its past activities.

**Cleansing / transformation:** Store active as true or false and keep the activities.

## U1: Users sharing an email

**Table:** `users`. **Grain:** one row per user whose email is used by another user. **Result:** 8 users, 4 emails.

```sql
-- users who share their email with another user
select
    id,
    name,
    email,
    modified
from ENPAL_RAW.PIPEDRIVE.USERS
qualify count(*) over (partition by email) > 1  -- email used more than once
order by
    email,
    id
```

**Business case (assumption):** A Pipedrive login email is unique, so a shared email points to edited user data, not to one person twice.

**Cleansing / transformation:** Join users on id, never on email.

## U2: Several owners per deal

**Table:** `deal_changes`. **Grain:** one row per deal with more than one owner. **Result:** 501 deals; the few with three owners are deals with two lifecycles (D3).

```sql
-- deals with more than one owner
select
    deal_id,
    count(distinct new_value) as owners,
    count(changed_field_key) as nr_changes
from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
where changed_field_key = 'user_id'  -- owner assignments only
group by deal_id
having count(distinct new_value) > 1  -- several owners
order by
    owners desc,
    deal_id
```

**Business case (assumption):** The deals are spread over many owners with few deals each, which requires an additional understanding of the domain and calls / meetings for stakeholder management, in case the slicing / dicing per rep is needed.

**Cleansing / transformation:** No per-rep KPIs from this export.

## S1: Stage spelled two ways

**Table:** `stages, fields`. **Grain:** one row per stage whose name differs from its label in the Stage field. **Result:** stage 2: 'Qualified lead' vs 'Qualified Lead'.

```sql
-- stage labels of the Stage field (JSON array of {id, label})
with stage_labels as (
    select
        o.value:id::int as stage_id,
        o.value:label::varchar as stage_label
    from ENPAL_RAW.PIPEDRIVE.FIELDS f
    inner join lateral flatten(input => f.field_value_options) o
    where f.field_key = 'stage_id'  -- the Stage field only
)

-- stages spelled differently from their label
select
    s.stage_id,
    s.stage_name,
    l.stage_label
from ENPAL_RAW.PIPEDRIVE.STAGES s
inner join stage_labels l
    on l.stage_id = s.stage_id
where s.stage_name <> l.stage_label
```

**Business case (assumption):** The stage was renamed in one place and not in the other.

**Cleansing / transformation:** Take the step names from the Stage field labels.

## X1: Exports end on different dates

**Table:** `deal_changes, activity`. **Grain:** one row per table and event type with its first and last date. **Result:** creations and calls end 2024-09-13, owners 2024-11-02, stage moves 2025-02-24, lost reasons 2025-03-11.

```sql
-- first and last date per table and event type
select
    'deal_changes: ' || changed_field_key as source,
    min(change_time) as first_at,
    max(change_time) as last_at
from ENPAL_RAW.PIPEDRIVE.DEAL_CHANGES
group by changed_field_key
union all
select
    'activity' as source,
    min(due_to) as first_at,
    max(due_to) as last_at
from ENPAL_RAW.PIPEDRIVE.ACTIVITY
order by last_at
```

**Business case (assumption):** The tables were exported at different times.

**Cleansing / transformation:** Report up to the last month with data; the call steps are 0 after 2024-09.
