# EDA findings

The business context (company, the sale, each KPI's meaning and its data) is in `docs/business_context.md`; field descriptions with links to the Pipedrive documentation in `docs/data_dictionary.md`.

Exploratory analysis of the six raw Pipedrive tables, loaded into schema `public` of the Docker Postgres. One analysis file per raw table in `analyses/`, one overall data-quality file, and one file of business questions. Numbers were checked against the loaded data on 2026-10-22. Each finding ends with its consequence for the model.

| File | Table | Class |
|---|---|---|
| `01_deal_changes.sql` | `deal_changes` | fact |
| `02_activity.sql` | `activity` | fact |
| `03_activity_types.sql` | `activity_types` | dictionary |
| `04_users.sql` | `users` | dictionary (master data) |
| `05_stages.sql` | `stages` | dictionary |
| `06_fields.sql` | `fields` | dictionary (metadata) |
| `07_data_quality_findings.sql` | all | the overall list of data-quality findings |
| `08_business_questions.sql` | all | the funnel KPIs read against the business: what Enpal's sales process would lead us to expect, and what the data shows |
| `09_review_later.sql` | `deal_changes` | statistical checks (IQR on stage gaps, gap shape, month spine) and open questions to go through later |

Every per-table file has the same sections: 1 rows and columns, 2 primary key (rows that share the candidate key, found with `count(*) over (partition by ...)`), 3 foreign keys (rows whose value is missing in the parent), 4 nulls per column, 5 outliers (facts only: rows per month, quarter and year, per dimension, and per dimension and month; not applicable for dictionaries), 6 descriptive analytics. The result of each query is written as a comment under it.

**Facts** have one row per event or transaction, a timestamp, grow over time and refer to the dictionaries by key. **Dictionaries** are small reference tables that decode ids or codes into names, are static and are referenced by the facts. `users` is master data: 1,787 rows, current state only, no history.

## 01_deal_changes.sql: `deal_changes` (fact, 15,406 rows)
- **Primary key:** none given by the task. (`deal_id`, `changed_field_key`, `change_time`) is unique and not null (identified). `deal_id` alone repeats (7.7 events per deal) and there is no deals table.
- **Foreign keys:** field key to `fields.field_key`; `new_value` to `users.id` (owner), `stages.stage_id` (stage) and the lost-reason option ids, depending on the key. All hold at 100% with 0 nulls.
- **Nulls:** none.
- **Outliers:** none in the gaps between stage events (max 35 days, upper fence 45.5). Creation lag to the first stage 1 entry: fence 75 days, 12 deals above (76 to 83 days), all plausible.
- **Descriptive:** an event log with four field keys: `stage_id` 8,906, `user_id` 2,500, `add_time` 2,000, `lost_reason` 2,000, over 1,995 deals. Every deal starts at stage 1. 2,502 stage moves skip a stage (1,684 deals, 84%), 8 move backward, 2 repeat a stage. 5 deals have two creation events and hold two full lifecycles; they explain every backward move. Every deal has a `lost_reason` (option ids 1 to 5: Customer Not Ready, Pricing Issues, Unreachable Customer, Product Mismatch, Duplicate Entry), also the 324 deals that reached the last stage. The reason does not describe where a deal stopped: the average highest stage is 6.4 to 6.7 for every reason; 377 deals are lost as Duplicate Entry although 274 of them reached Closing, and 422 are Unreachable Customer although 411 reached Needs Assessment or later. Creation to first stage 1 entry: median 35 days (IQR 25 to 45). Gaps between stage events are flat from 0 to about 30 days (mean 15.6, median 16, skewness -0.01, excess kurtosis -1.19; a uniform distribution has -1.2): the timing looks generated. Events per deal range 4 to 17.
- **Backfilled vs recorded deals per stage:** 1: 1,995 / 1,995; 2: 1,479 / 1,990; 3: 1,305 / 1,951; 4: 1,086 / 1,862; 5: 894 / 1,693; 6: 741 / 1,424; 7: 588 / 1,081; 8: 479 / 723; 9: 324 / 324 (backfill adds 4,152 stage entries).
- **Consequence:** build the funnel from the `stage_id` events; cast `new_value` per key; the deal model counts a deal once (earliest `add_time`, flag for two lifecycles); backfill skipped stages with an `is_inferred` flag (decided); `lost_reason` marks the end of a lifecycle, not a lost deal, and its coded reasons are inconsistent with the stages (ask the CRM admin how it is entered; duplicates should be merged, not carried through the funnel); Step 1 date is an open decision (stage 1 entry recommended).

## 02_activity.sql: `activity` (fact, 4,579 rows)
- **Primary key:** none given by the task. `activity_id` is the intended key (table name + `_id`) but is not unique: 11 ids repeat (22 of 4,579 rows, 0.48%). Proven a data quality issue, not a composite key: user, deal and due date differ in every pair, `(activity_id, type)` still repeats, chance predicts 11.6 collisions. **Decided by the owner:** treated as duplicates and marked as a data quality issue; the cleansing can follow the process within the domain and needs a review by the business stakeholder responsible for the KPIs and the data entry. The full row is unique, so the model can carry a surrogate key.
- **Foreign keys:** `assigned_to_user` to `users.id` and `type` to `activity_types.type` hold at 100% with 0 nulls. `deal_id` to `deal_changes.deal_id` fails: 8 of 4,579 rows match and the parent column repeats.
- **Nulls:** none. **Outliers:** none in `due_to`.
- **Descriptive:** four types (`after_close_call` 1,177, `meeting` 1,145, `follow_up` 1,133, `sc_2` 1,124), about 50% done in every type (2,290 true, 2,289 false). The 11 repeated `activity_id`s are collisions of unrelated activities: deal, user and due date differ in every pair (type in 9 of 11). 4,579 ids from a 900,000-wide range predict about 11.6 chance collisions; 11 were observed. Only 8 of 4,572 distinct activity deal ids exist in `deal_changes`, about what chance gives for two six-digit ranges. Activities fall in 2024-01-01 to 2024-09-13, about 500 a month, the same window as the deal creations.
- **Consequence:** calls (`meeting` = Sales Call 1, `sc_2` = Sales Call 2) cannot be attributed to deals; count them by `due_to` month from `activity` alone and raise the question with Enpal; `follow_up` and `after_close_call` are not funnel steps; calls are 0 from 2024-10.

## 03_activity_types.sql: `activity_types` (dictionary, 4 rows)
- **Primary key:** `id`, given by the task, unique and not null. `type` is also unique and is the column activities reference. **Foreign keys:** none (referenced by `activity.type`, 4 of 4 types used). **Nulls:** none. **Outliers:** not applicable.
- **Descriptive:** `follow_up` is inactive yet used by 1,133 activities; `after_close_call` is not a funnel step.
- **Consequence:** staging lookup keyed on `type`; Sales Call 1 and 2 come from the seed mapping.

## 04_users.sql: `users` (dictionary, 1,787 rows)
- **Primary key:** `id`, given by the task, unique and not null. `email` is not a key. **Foreign keys:** none (referenced by `activity.assigned_to_user` and the owner events). **Nulls:** none. **Outliers:** none in `modified`.
- **Descriptive:** 4 emails are shared by 2 users each (8 rows). `modified` spans 2024-01-02 to 2024-10-28. 1,757 of 1,787 users are referenced; 30 never.
- **Consequence:** key users on `id`, never on email; email uniqueness test at warn.

## 05_stages.sql: `stages` (dictionary, 9 rows)
- **Primary key:** `stage_id`, given by the task, unique and not null. **Foreign keys:** none (referenced by the stage events, 9 of 9 used). **Nulls:** none. **Outliers:** not applicable.
- **Descriptive:** the second stage is spelled "Qualified lead" here and "Qualified Lead" in `fields`. The order of `stage_id` is the funnel order.
- **Consequence:** step names come from a seed using the task's spelling.

## 06_fields.sql: `fields` (dictionary, 4 rows)
- **Primary key:** `id`, given by the task, unique and not null. `field_key` is also unique and is the column `deal_changes` references. **Foreign keys:** none. **Nulls:** only `field_value_options`, 2 of 4 rows (`user_id` and `add_time` have no option list; not applicable). **Outliers:** not applicable.
- **Descriptive:** stage labels and lost-reason options sit in `field_value_options` as JSON.
- **Consequence:** unnest the JSON in staging for stage labels and lost-reason options; leave `field_value_options` nullable.

## 08_business_questions.sql: the funnel read against the business

Each block starts from what a household energy sale would lead us to expect; the expectation, the result and the consequence are tabled in `docs/business_context.md` (What the business would expect, and what the data shows).

- **B1 Lead Generation:** a deal is created, gets an owner after a median 15 days and enters stage 1 after 35 days (owner first for all 1,995). Creation and stage 1 entry give different monthly Step 1 counts (2024-01: 247 vs 30).
- **B2 Stages:** the funnel barely narrows (5 deals stop at stage 1, 399 at stage 8, 324 reach stage 9); 84% skip a stage; 5 deals run the pipeline twice.
- **B3 Sale length:** stage 1 to Closing median 50 days (IQR 35 to 66): plausible.
- **B4 Sales calls:** flat ~130 per type per month from 2024-01, when only 6 deals had reached stage 2; end 2024-09-13; 50% done for every type; of the 8 activities whose deal id matches, only one fits the deal's timeline.
- **B5 Lost reason:** set 1 to 30 days after the last stage event for every deal, evenly spread over all stages: a closure label, not an outcome.
- **B6 Owners:** 1,347 owners for 1,995 deals; 499 of 505 owner changes happen before stage 1.

## 07_data_quality_findings.sql: all data-quality findings (28 checks)

One result row per check; the detail query of each finding is in the per-table file named in its last column. Severity is the proposed dbt test severity (error: our own pipeline would be wrong; warn: known upstream defect, fixed in staging; info: documented only).

| # | Table | Class | Finding | Violations | Severity |
|---|---|---|---|---|---|
| 1 | activity | record | full-row duplicates (a table loaded twice) | 0 | error |
| 2 | deal_changes | record | duplicate events on (deal_id, field key, time) | 0 | error |
| 3 | activity | record | activity_id repeated (ids): duplicates, data quality issue; cleansing per domain process after business stakeholder review | 11 | warn |
| 4 | users | record | rows sharing an email (4 emails, 2 users each) | 8 | warn |
| 5 | deal_changes | record | deals with two creation events (add_time) | 5 | warn |
| 6 | deal_changes | record | deals with two lost_reason events | 5 | warn |
| 7 | deal_changes | record | same-timestamp stage events of one deal (ambiguous order) | 0 | error |
| 8 | all | field | NULLs in required columns (all tables, fields.field_value_options excluded) | 0 | error |
| 9 | fields | field | NULL field_value_options (expected: user_id and add_time have no option list) | 2 | info |
| 10 | stages | field | stage names spelled differently from the labels in fields (Qualified lead vs Qualified Lead) | 1 | info |
| 11 | deal_changes | field | stage ids outside 1 to 9 | 0 | error |
| 12 | deal_changes | referential | owner ids (user_id events) missing from users | 0 | error |
| 13 | deal_changes | referential | stage ids missing from stages | 0 | error |
| 14 | activity | referential | assigned users missing from users | 0 | error |
| 15 | activity | referential | activity types missing from activity_types | 0 | error |
| 16 | activity | referential | activity rows whose deal_id is not in deal_changes (no deals table; ids look unrelated) | 4,571 | warn |
| 17 | deal_changes | business logic | deals not starting at stage 1 | 0 | error |
| 18 | deal_changes | business logic | stage events dated before the deal was created | 0 | error |
| 19 | deal_changes | business logic | lost_reason dated before the last stage event (deals) | 4 | warn |
| 20 | deal_changes | business logic | stage moves that skip a stage | 2,502 | info |
| 21 | deal_changes | business logic | stage moves that go backward | 8 | info |
| 22 | deal_changes | business logic | stage moves that repeat the same stage | 2 | info |
| 23 | deal_changes | business logic | deals that reached the last stage but also carry a lost_reason (reason is not a deal outcome) | 324 | info |
| 24 | deal_changes | business logic | deals lost as Duplicate Entry (duplicates kept as deals, not merged) | 377 | warn |
| 25 | deal_changes | business logic | Duplicate Entry deals that reached Closing or later | 274 | warn |
| 26 | deal_changes | business logic | Unreachable Customer deals that reached Needs Assessment or later | 411 | warn |
| 27 | activity | coverage | months with stage events but no activities (activities end 2024-09-13) | 5 | info |
| 28 | users | coverage | users never referenced by an activity or an owner event | 30 | info |

Not in the export: deal status (open, won, lost), pipeline, value, person and organization, who changed a field, the previous value, and when an activity was completed.

**Consequence:** tests per class in the staging YAML with the severities above; the failing `warn` findings stay documented and are fixed in staging (surrogate key for `activity`, one row per deal for the two-lifecycle deals); the open business questions are in `docs/approach.md`.

### Proposed dbt tests (by check)

| Check | Class | Proposed dbt test (layer) | Severity |
|---|---|---|---|
| Duplicate events (double load) | record | `unique_combination_of_columns [deal_id, changed_field_key, change_time]` (stg deal_changes) | error |
| Nulls in required columns | field | `not_null` on keys, key, time, value (staging) | error |
| Event key outside the four known | field | `accepted_values` on `changed_field_key` (staging) | error |
| Stage id outside 1 to 9 | field | `accepted_values` on the cast stage id (staging) | error |
| Stage id missing from `stages` | referential | `relationships` stage events to `stg_pipedrive__stages` (staging) | error |
| Owner id missing from `users` | referential | `relationships` owner events to `stg_pipedrive__users` (staging) | error |
| Activity assignee missing from `users` | referential | `relationships` (staging) | error |
| Activity type missing from `activity_types` | referential | `relationships` (staging) | error |
| First stage is not 1 | business logic | singular or `expression_is_true` (intermediate) | error |
| Stage event before creation | business logic | singular (intermediate) | error |
| Same-timestamp stage ties | record | `unique_combination_of_columns [deal_id, change_time]` filtered to stage events (intermediate) | error |
| Deals with two `add_time` | record | `unique` on `deal_id` in the raw filter at warn; `unique` on `int_pipedrive__deals.deal_id` at error | warn on raw, error after dedupe |
| Two `lost_reason` per deal | record | same pattern | warn |
| `lost_reason` before last stage event | business logic | singular | warn |
| Users sharing an email | record | `unique` on email in `stg_pipedrive__users` | warn |
| Repeated `activity_id` | record | `unique` on `activity_id` in raw at warn; `unique` on the surrogate key at error | warn on raw |
| Activity `deal_id` missing from `deal_changes` | referential | `relationships` kept as a documented known failure, not promoted as an error | warn |
| Stage moves not exactly +1 | business logic | informational probe only, do not promote | none |
| Report total of step 1 equals distinct deals (1,995) | reconciliation | singular (marts) | error |

## dbt test probe run (44 tests: 37 pass, 7 fail)

Files: `models/staging/pipedrive/_pipedrive__sources.yml`, `tests/exploration/explore_*.sql`. Failing rows are in schema `public_dbt_test__audit`.

| Failing test | Rows |
|---|---|
| `activity.deal_id` relationships to `deal_changes.deal_id` | 4,571 |
| `explore_stage_moves_not_forward_by_one` (informational) | 2,512 (2,502 skips + 8 backward + 2 repeats) |
| `activity.activity_id` unique | 11 |
| `users.email` unique | 4 |
| one `add_time` per deal | 5 |
| one `lost_reason` per deal | 5 |
| `explore_lost_before_last_stage` | 4 |

Gotchas: two tests with the same generated name need `name:`; `source('a', 'b')` inside a YAML flow mapping breaks the parse (use block style); `relationships` cannot cast text to integer, so use a singular test.

## Pipedrive terms that explain the data

`activity.type` is Pipedrive's activity-type `key_string`, generated at creation and not changeable. `deal_changes` looks like a deal flow or changelog log flattened to the new value only. Not in the export: deal status (open, won, lost), value, pipeline, probability, persons, organizations, change author, previous value, activity completion time. Moving a deal to any stage is normal Pipedrive behaviour (general product knowledge, not verified in the pages read).
