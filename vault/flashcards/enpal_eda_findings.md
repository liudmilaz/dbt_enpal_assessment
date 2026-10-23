---
tags:
  - project/enpal
  - domain/eda
  - domain/dbt
  - type/flashcard
---

# Flashcards — Pipedrive EDA findings (manual run)

---

How much does backfilling skipped stages change the funnel? #card
Recorded vs backfilled deals per stage: 1: 1,995/1,995; 2: 1,479/1,990; 3: 1,305/1,951; 4: 1,086/1,862; 5: 894/1,693; 6: 741/1,424; 7: 588/1,081; 8: 479/723; 9: 324/324. Backfill adds 4,152 stage entries, up to about 90% on a middle step.

---

What do the 5 deals with two `add_time` events have in common? #card
They are exactly the 5 deals with backward moves: each holds two full lifecycles (e.g. path 1>2>3>4>5>8>1>2>4>5). Four of them are also the only deals whose `lost_reason` is dated before the last stage event.

---

Is `lost_reason` always after the last stage event? #card
No. It is dated before the last stage event for 4 deals (all two-lifecycle deals). It still exists for every deal, including those that reached stage 9, so it marks the end of a lifecycle, not a lost deal.

---

What is the creation window, and how does it relate to activities? #card
Deals are created 2024-01-01 to 2024-09-13, the same window as the activities. Stage events continue to 2025-03, which is why Step 1 differs by definition (creation vs stage 1 entry).

---

Outlier result for the Pipedrive timing data? #card
Gaps between stage events: max 35 days, IQR fence 45.5 -> none above. Creation lag: fence 75 days, 12 deals (76-83 days) above, all plausible. No outlier treatment.

---

Which data-quality checks pass cleanly in the raw data? #card
0 duplicate events, 0 same-timestamp ties, 0 nulls in required columns, 0 owner or assignee orphans, 0 stage events before creation, 0 stage ids outside 1-9. Those can be hard-error tests.

---

Which checks flag known upstream defects? #card
5 deals with two add_time, 4 lost_reason before the last stage, 8 users sharing 4 emails, 11 repeated activity_ids, and 4,564 activity deal_ids missing from the deal history. These get severity warn.

---

How can you tell the two lifecycles apart inside deal 399956? #card
By the clock time: every event of the first lifecycle is at 06:45:44, every event of the second at 18:27:27. They overlap (second created 2024-06-29, first lost 2024-08-01), so it looks like a duplicate lead merged into one deal, not a re-opened deal.

---

What does "99.8% of changes share the deal's creation clock time" mean? #card
Every event is the creation time plus a whole number of days (1,990 deals have one clock time, the 5 two-lifecycle deals exactly two). Real CRM edits happen at random times of day, so the event times are generated.

---

What does "backfilled" mean in the Enpal funnel? #card
Every stage below the highest stage a deal reached counts as entered, even without a recorded event; those rows get `is_inferred = true`. Deal 399956 jumps Negotiation -> Follow-up, so Closing and Implementation are backfilled.

---

What does Pipedrive's merge tutorial say happens to two merged deals? #card
The `merge_with_id` deal survives and its field values win; the other deal is deleted; activities, emails, notes, products, followers and participants are transferred. It does not say what happens to the change history.

---

How many deals reach stage 7-9 without a recorded Closing? #card
683 of 1,081 (63%): after-sale stages without a signed contract in the log, so stage skipping is not a rare edge case.
