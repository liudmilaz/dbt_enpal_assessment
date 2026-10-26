# Deal history, stage skipping, backfill and questions for Enpal

All queries below ran during the exploratory analysis on a local Postgres copy of the raw export (schema `public`; the same data as `ENPAL_RAW.PIPEDRIVE` in Snowflake); the result is under each query.

## 1. Query behind the deal history table (deal 399956)

```sql
with deal_events as (  -- filter first: only the deal we look at
    select
        change_time,
        changed_field_key,
        new_value
    from public.deal_changes
    where deal_id = 399956
),
lost_reason_labels as (  -- unpack the lost-reason options once
    select
        o.id as reason_id,
        o.label as reason_label
    from public.fields f
    cross join jsonb_to_recordset(f.field_value_options) as o(id text, label text)
    where f.field_key = 'lost_reason'
)
select
    e.change_time,
    e.change_time::time as clock_time,  -- separates the two lifecycles
    e.changed_field_key,
    coalesce(s.stage_name, u.name, r.reason_label, e.new_value) as decoded_value,
    round(extract(epoch from e.change_time - lag(e.change_time) over (order by e.change_time)) / 86400, 1) as days_since_previous
from deal_events e
left join public.stages s
    on s.stage_id::text = e.new_value
    and e.changed_field_key = 'stage_id'  -- decode only stage events; every event row is kept
left join public.users u
    on u.id::text = e.new_value
    and e.changed_field_key = 'user_id'
left join lost_reason_labels r
    on r.reason_id = e.new_value
    and e.changed_field_key = 'lost_reason'
order by e.change_time;
-- 17 rows: 06:45:44 = lifecycle A, 18:27:27 = lifecycle B
```

This is the one deliberate exception to the rule "no left-table condition in a left join's `on`": the goal is to **keep every event** and attach a label only where the key matches, so the condition belongs in `on`. Comparing as text (`stage_id::text = new_value`) also avoids the cast error on the timestamps.

Result:

| Time | Lifecycle A (always 06:45:44) | Lifecycle B (always 18:27:27) |
|---|---|---|
| 2024-04-06 | Deal created | |
| 2024-04-08 | Owner: Mark Schultz (+2 days) | |
| 2024-04-30 | Owner: Kurt Mckee (+22 days) | |
| 2024-05-07 | Lead Generation | |
| 2024-06-02 → 06-09 | Qualified Lead → Needs Assessment → Proposal/Quote, in 7 days | |
| 2024-06-29 | | Deal created again |
| 2024-07-09 | Negotiation | |
| 2024-07-17 | Follow-up/Customer Success: Closing and Implementation skipped | |
| 2024-07-22 | | Owner: April Mitchell |
| 2024-08-01 | Lost: Customer Not Ready | |
| 2024-08-18 → 09-06 | | Lead Generation → Qualified → Proposal (Needs Assessment skipped) → Negotiation |
| 2024-09-08 | | Lost: Customer Not Ready |

## 2. "84% of deals skip a stage"

```sql
with stage_moves as (  -- filter first: only stage events, so the cast is safe
    select
        deal_id,
        new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as move
    from public.deal_changes
    where changed_field_key = 'stage_id'
),
deals as (  -- one row per deal: did any move skip a stage?
    select
        deal_id,
        bool_or(move > 1) as skips_a_stage,
        count(*) filter (where move > 1) as nr_skipped_moves
    from stage_moves
    group by 1
)
select
    count(*) as nr_deals,
    count(*) filter (where skips_a_stage) as nr_deals_skipping,
    round(100.0 * count(*) filter (where skips_a_stage) / count(*), 1) as pct_deals_skipping,
    sum(nr_skipped_moves) as nr_skipped_moves
from deals;
-- 1995 | 1684 | 84.4 | 2502
```

## 3. What "backfilled" means

The report counts a deal at every stage **up to the highest stage it reached**, even where the log has no event for a stage in between. Those added entries are flagged `is_inferred = true`. That is the decision taken because of the 84% skipping: a deal in Negotiation must have passed the earlier stages, even if the rep never moved it there in the CRM. Example, deal 399956:

```sql
with entries as (  -- recorded: stages the deal actually entered (first entry each)
    select
        new_value::int as stage_id,
        min(change_time) as entered_at
    from public.deal_changes
    where changed_field_key = 'stage_id'
        and deal_id = 399956
    group by 1
),
highest as (  -- the furthest stage the deal reached
    select
        max(stage_id) as highest_stage
    from entries
)
select
    s.stage_id,
    s.stage_name,
    e.entered_at as recorded_entry,
    e.stage_id is null as is_inferred  -- below the highest stage but never recorded: backfilled
from public.stages s
cross join highest h
left join entries e
    on e.stage_id = s.stage_id
where s.stage_id <= h.highest_stage
order by 1;
-- stages 1-5 and 8 recorded; 6 Closing and 7 Implementation: is_inferred = true
```

So this deal is counted under **Closing** although no contract was ever recorded. That is the cost of backfilling, and the README has to say it.

## 4. Questions to Enpal, each with supporting SQL

### Q1: When duplicate deals are merged in Pipedrive, does the export keep both histories?

**Pipedrive documentation:**

- The [merge tutorial](https://pipedrive.readme.io/docs/merging-two-deals) says the deal given as `merge_with_id` survives and its field values win. The other deal is **deleted**. Activities, emails, notes, products, followers and participants are transferred.
- It says **nothing about the change history**. Nor do the [Deals API](https://developers.pipedrive.com/docs/api/v1/Deals) page and the [deal detail view](https://support.pipedrive.com/en/article/deal-detail-view) article (which covers the History and Changelog tabs).
- The [Merge Duplicates](https://support.pipedrive.com/en/article/merge-duplicates) tool covers people and organisations only. Pipedrive does not flag duplicate deals at all.

The assumption is therefore not confirmed by the documentation. The data supports it: all 5 two-lifecycle deals **overlap**, meaning the second deal was created before the first was lost. That fits a duplicate lead that was later merged, not a deal re-opened after a loss. Open: test a merge in the trial account (datacanonic.pipedrive.com) and read the surviving deal's History tab; the merge deletes one deal and cannot be undone, so it needs the owner's approval.

```sql
with creations as (  -- number each creation event per deal: 1 = first lifecycle, 2 = second
    select
        deal_id,
        change_time,
        row_number() over (partition by deal_id order by change_time) as nr_lifecycle
    from public.deal_changes
    where changed_field_key = 'add_time'
),
losses as (  -- same numbering for the lost-reason events
    select
        deal_id,
        change_time,
        row_number() over (partition by deal_id order by change_time) as nr_lifecycle
    from public.deal_changes
    where changed_field_key = 'lost_reason'
)
select
    c1.deal_id,
    c1.change_time::date as first_created,
    l1.change_time::date as first_lost,
    c2.change_time::date as second_created,
    l2.change_time::date as second_lost,
    c2.change_time < l1.change_time as overlaps  -- second lead created while the first was still open
from creations c1
join creations c2
    on c2.deal_id = c1.deal_id
    and c2.nr_lifecycle = 2
join losses l1
    on l1.deal_id = c1.deal_id
    and l1.nr_lifecycle = 1
join losses l2
    on l2.deal_id = c1.deal_id
    and l2.nr_lifecycle = 2
where c1.nr_lifecycle = 1
order by 1;
-- 5 rows, overlaps = true for all 5 (e.g. 399956: created 04-06, second created 06-29, first lost 08-01)
```

### Q2: How does a rep choose between "Duplicate Entry" and the other lost reasons?

If "Duplicate Entry" were used correctly, those deals would stop early, as soon as someone spots the duplicate, and the merged deals would carry it. Neither is true. Duplicate Entry deals reach Closing as often as any other reason (about 72%). Of the 5 merged deals, 1 carries Duplicate Entry and the others carry business reasons. (A merged deal with two different reasons counts under both, so the last column adds up to 8.)

```sql
with highest as (  -- the furthest stage each deal reached
    select
        deal_id,
        max(new_value::int) as highest_stage
    from public.deal_changes
    where changed_field_key = 'stage_id'
    group by 1
),
reasons as (  -- unpack the lost-reason options once
    select
        o.id as reason_id,
        o.label as reason_label
    from public.fields f
    cross join jsonb_to_recordset(f.field_value_options) as o(id text, label text)
    where f.field_key = 'lost_reason'
),
lost as (  -- one row per deal and reason
    select distinct
        deal_id,
        new_value as reason_id
    from public.deal_changes
    where changed_field_key = 'lost_reason'
),
two_lifecycles as (  -- the merged deals
    select
        deal_id
    from public.deal_changes
    where changed_field_key = 'add_time'
    group by 1
    having count(*) > 1
)
select
    r.reason_label,
    count(*) as nr_deals,
    count(*) filter (where h.highest_stage >= 6) as nr_reached_closing,
    count(t.deal_id) as nr_two_lifecycle_deals
from lost l
join reasons r
    on r.reason_id = l.reason_id
join highest h
    on h.deal_id = l.deal_id
left join two_lifecycles t
    on t.deal_id = l.deal_id
group by 1
order by 1;
-- Customer Not Ready 381 / 276 / 1 | Duplicate Entry 377 / 274 / 1 | Pricing Issues 401 / 291 / 2
-- Product Mismatch 417 / 294 / 3 | Unreachable Customer 422 / 292 / 1
```

### Q3: Can a deal reach Implementation, Customer Success or Renewal without passing Closing?

In a solar sale you cannot install without a signed contract. Yet **683 of the 1,081 deals in stages 7 to 9 (63%) have no recorded Closing**. Stage skipping is not a rare edge case.

```sql
with entries as (  -- each stage a deal entered, once
    select distinct
        deal_id,
        new_value::int as stage_id
    from public.deal_changes
    where changed_field_key = 'stage_id'
),
per_deal as (  -- one row per deal: after-sale stage reached, and Closing recorded?
    select
        deal_id,
        bool_or(stage_id >= 7) as reached_after_sale,
        bool_or(stage_id = 6) as has_closing
    from entries
    group by 1
)
select
    count(*) filter (where reached_after_sale) as nr_deals_after_sale,
    count(*) filter (where reached_after_sale and not has_closing) as nr_without_closing,
    round(100.0 * count(*) filter (where reached_after_sale and not has_closing) / count(*) filter (where reached_after_sale), 1) as pct_without_closing
from per_deal;
-- 1081 | 683 | 63.2
```
