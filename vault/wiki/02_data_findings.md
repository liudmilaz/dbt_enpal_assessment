---
tags:
  - project/enpal
  - domain/dbt
  - domain/sql
  - type/reference
---

# Data findings — Pipedrive CSVs (verified)

| # | Finding | Consequence |
|---|---|---|
| 1 | `deal_changes` is an event log: 15,406 rows, 1,995 deals; `stage_id` 8,906, `user_id` 2,500, `add_time` 2,000, `lost_reason` 2,000 | Build the funnel from `stage_id` events |
| 2 | Every deal starts at stage 1; 2,502 jumps skip a step; 8 backward moves; 2 repeats | "Reached stage N" ≠ sequential; backfill decision |
| 3 | Deals entering each stage: 1,995 / 1,479 / 1,305 / 1,086 / 894 / 741 / 588 / 479 / 324 | Expected report totals |
| 4 | 5 deals have two `add_time` rows | Treat as one deal, document |
| 5 | `lost_reason` on every deal, even those that reached stage 9; labels only in `fields.field_value_options` (JSONB) | Marks end of lifecycle, not a lost deal |
| 6 | Only 8 of 4,579 `activity.deal_id` exist in `deal_changes` | Calls cannot be joined to deals; count calls by `due_to` month; open question for Enpal |
| 7 | 11 `activity_id` values repeat with different content | Surrogate key; source test at `warn` |
| 8 | Activity types: `meeting` (Sales Call 1), `sc_2` (Sales Call 2), `follow_up`, `after_close_call` | Last two are not funnel steps |
| 9 | Activity ends 2024-09-13; deal events run to 2025-03 | Calls are 0 from 2024-10 |
| 10 | "Qualified lead" (stages) vs "Qualified Lead" (fields JSON) | Names come from a seed |
| 11 | 4 emails shared by two users | Key users on `id`, not email |
| 12 | Docker loader appends on every `up` (activity/deal_changes have no PK) | See [[dbt_source_tests_and_loader_gotcha]] |
| 13 | Stage-1 entry is a median of 35 days after `add_time` | Step 1 definition choice |

Raw column types: `deal_changes.new_value` is `varchar(255)` — cast per `changed_field_key`.

## Added by the manual EDA run (2026-10-22, `analyses/00-05`, dashboard "Pipedrive funnel EDA")

| # | Finding | Consequence |
|---|---|---|
| 14 | Backfill changes the middle steps a lot: recorded vs backfilled deals per stage = 1,995/1,995; 1,479/1,990; 1,305/1,951; 1,086/1,862; 894/1,693; 741/1,424; 588/1,081; 479/723; 324/324 (+4,152 entries) | Decision 1 matters: up to about 90% on a step |
| 15 | The 5 deals with two `add_time` events are exactly the 5 deals with backward moves: each holds two lifecycles (e.g. `1>2>3>4>5>8>1>2>4>5`) | Explains the 8 backward moves; count a deal once per step |
| 16 | `lost_reason` is dated before the last stage event for 4 deals (all two-lifecycle deals). Correction: it is NOT always after the last stage change | Do not assume lost_reason is the final event |
| 17 | Deal creation window = 2024-01-01 to 2024-09-13, identical to the activity window; stage events continue to 2025-03 | Activities and creations share one window; calls end because creations end |
| 18 | Creation lag: IQR 25-45 days, fence 75; 12 deals above (76-83 days), all valid. Gaps between stage events: max 35 days, none above the fence | No outlier treatment |
| 19 | Median time between stage events is about 16 days at every stage | Stage durations carry no signal |
| 20 | Stage 1 entries per month: 30 in 2024-01 vs 247 created; entries continue to 2024-11 after creations stop in 2024-09 | Step 1 definition shifts months; see decision 2 |
| 21 | Done share is about 50% for every activity type; Sales Call 1 and 2 done-only about 55-75 distinct deals a month | Decision 3: done-only roughly halves the counts |
| 22 | Clean: 0 duplicate events, 0 same-timestamp ties, 0 nulls, 0 owner/assignee orphans, 0 stage events before creation | Those tests pass as hard errors |
| 23 | dbt test probes (44 tests): the same 5 two-lifecycle deals also have two `lost_reason` events (2,000 events for 1,995 deals) | Count each deal once; lost_reason per deal is not unique |
| 24 | Distributions (`analyses/01_deal_changes.sql` section 6): gaps between stage events are flat from 0 to about 30 days (mean 15.6, median 16, skewness -0.01, excess kurtosis -1.19, a uniform has -1.2; each decile holds 691 gaps; only 2 gaps above 30 days). Activity types ~25% each; ~500 activities a month until mid September. Events per deal range 4-17; the 5 deals with 15-17 events are the two-lifecycle deals | Timing looks generated: do not read business meaning into stage durations; events per deal confirms the 5 merged deals |
| 25 | The 11 repeated `activity_id`s are id collisions: in every pair deal, user and due date differ (type differs in 9). 4,579 ids from a 900,000 range predict about 11.6 chance collisions; 11 observed. Example 521731: Follow Up Call on deal 762400 vs Sales Call 1 on deal 968858 | Not duplicates to remove: surrogate key per row; ask the extraction owner; ids look randomly generated |
| 26 | Nulls and keys (sections 2 to 4 of `analyses/01` to `06`): NULLs only in `fields.field_value_options` (2 of 4, not applicable); no blanks. Declared PKs: `activity_types.id`, `fields.id`, `stages.stage_id`, `users.id`; none on `activity` or `deal_changes`; no FK declared. `deal_changes` key = (`deal_id`, `changed_field_key`, `change_time`); `activity` has no key (`activity_id` repeats, full row unique); alternate keys `activity_types.type`, `fields.field_key` are the referenced ones. All FK candidates hold 100% except `activity.deal_id` (8 of 4,579) | Key register in `docs/findings.md` drives unique, not_null and relationships tests |
| 27 | Lost reasons decoded (labels in `fields`): Customer Not Ready, Pricing Issues, Unreachable Customer, Product Mismatch, Duplicate Entry (about 400 deals each). Average highest stage 6.4 to 6.7 for every reason; 377 deals lost as Duplicate Entry, 274 of them reached Closing; 422 Unreachable Customer, 411 reached Needs Assessment or later | Reasons are inconsistent with the stages; duplicates are not merged; do not use lost_reason as an outcome; ask the CRM admin |
