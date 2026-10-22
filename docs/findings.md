# EDA findings

One section per query in `analyses/`. Each ends with its consequence for the model. Raw tables are in schema `public` of the Docker Postgres. Numbers were checked against the loaded data on 2026-10-22.

Analysis files: `00` select all, `01` nulls and keys, `02` distributions, `03` outliers, `04` descriptive analysis (sections A to I), `05` quality checks.

## 00_select_all_raw.sql: plain select of each raw table
Convenience file for browsing. No finding.

## 01_nulls_and_keys.sql: nulls, primary keys and foreign keys

### Nulls and blanks in every column
- 24 columns in six tables. The only NULLs are in `fields.field_value_options`: 2 of 4 rows (the `user_id` and `add_time` fields have no option list; not applicable, not missing). No blank strings in any column.
- **Consequence:** `not_null` on every key and every other column can be a hard error. `field_value_options` stays nullable by design and must not be coalesced. No imputation or NULL filtering is needed.

### Primary and foreign keys
- Declared in Postgres: primary keys on `activity_types.id`, `fields.id`, `stages.stage_id`, `users.id`. None on `activity` or `deal_changes`, and no foreign key declared anywhere (the CSVs were loaded with `init.sql` only).
- Found by testing (rows = distinct and no NULLs):
  - `deal_changes` is unique only on (`deal_id`, `changed_field_key`, `change_time`). `deal_id` repeats (7.7 events per deal), so there is no deal master table in the export.
  - `activity_id` is not unique (4,568 distinct of 4,579 rows); the full row is. Activity needs a surrogate key.
  - Alternate keys that are the ones actually referenced: `activity_types.type` (not the primary key `id`) and `fields.field_key` (not the primary key `id`).
  - `users.email` is not a key (1,783 distinct of 1,787); `stages.stage_name` is unique.
- Foreign key candidates (child rows found in the parent): `activity.assigned_to_user` to `users.id` 4,579 of 4,579; `activity.type` to `activity_types.type` 4,579 of 4,579; `deal_changes.changed_field_key` to `fields.field_key` 15,406 of 15,406; owner events to `users.id` 2,500 of 2,500; stage events to `stages.stage_id` 8,906 of 8,906; lost-reason events to the `fields` option ids 2,000 of 2,000; **`activity.deal_id` to `deal_changes.deal_id` only 8 of 4,579**.
- **Consequence:** the key register below drives the tests: `unique` + `not_null` on every key, `relationships` on every foreign key that holds, a surrogate key for `activity`, a composite key for `deal_changes`, and `activity.deal_id` documented as an unrelated key (known failure).

#### Key register

| Table | Primary key | Declared? | Alternate or natural key | Foreign keys (match) |
|---|---|---|---|---|
| `deal_changes` | (`deal_id`, `changed_field_key`, `change_time`), composite | No | none | `changed_field_key` to `fields.field_key` (100%); `new_value` to `users.id` when key = `user_id` (100%), to `stages.stage_id` when `stage_id` (100%), to the `lost_reason` option ids when `lost_reason` (100%); `deal_id` has no parent table |
| `activity` | none; surrogate key needed (`activity_id` repeats for 11 ids) | No | full row | `assigned_to_user` to `users.id` (100%); `type` to `activity_types.type` (100%); `deal_id` to `deal_changes.deal_id` (8 of 4,579) |
| `activity_types` | `id` | Yes | `type` (the key string activities reference) | none |
| `users` | `id` | Yes | none (`email` is not unique) | none |
| `stages` | `stage_id` | Yes | `stage_name` | none |
| `fields` | `id` | Yes | `field_key` (referenced by `deal_changes`) | none |

## 02_distributions.sql: shape of the data

- Gaps between stage events are flat from 0 to about 30 days: mean 15.6, median 16, skewness -0.01, excess kurtosis -1.19 (a uniform distribution has -1.2); every decile holds 691 gaps; only 2 gaps exceed 30 days. Activity types are about 25% each; about 500 activities a month until mid September. Events per deal range 4 to 17; the 5 deals with 15 to 17 events are the two-lifecycle deals.
- **Consequence:** the timing looks generated; do not read business meaning into stage durations.

## 03_outliers.sql: outliers in timing

- Gaps between consecutive stage events: max 35 days, IQR upper fence 45.5, none above. Creation lag: fence 75 days, 12 deals above (76 to 83 days), all plausible.
- **Consequence:** no outlier treatment; do not drop or cap.

## 04_descriptive_analysis.sql: what the data contains

### A. Size and date coverage
- `deal_changes` 15,406 rows, 2024-01-01 to 2025-03-11. `activity` 4,579 rows, 2024-01-01 to 2024-09-13. `users` 1,787, `stages` 9, `fields` 4, `activity_types` 4.
- A double Docker load would show `activity` = 9,158 (this happened once and was reset).
- **Consequence:** these counts are the reference for the load check. Activity ends 2024-09-13, so calls are 0 from 2024-10.

### B. What the event log tracks
- `deal_changes` is an event log, one row per field change: `stage_id` 8,906, `user_id` 2,500, `add_time` 2,000, `lost_reason` 2,000. 1,995 deals; each key covers all deals.
- `new_value` is `varchar(255)`.
- **Consequence:** build the funnel from `stage_id` events; cast `new_value` per `changed_field_key` in staging. Owner = `user_id` events.

### C. How deals move between stages
- Every deal starts at stage 1. Stage moves: 2,502 skip at least one stage (1,684 deals, 84%), 8 move backward, 2 repeat the same stage.
- **Consequence:** "reached stage N" cannot assume N-1 was logged. Owner decided: backfill skipped stages with an `is_inferred` flag.

### D. Deals with two creation events
- 5 deals (399956, 554294, 556338, 851850, 955417) have two creation events and hold two full lifecycles, for example `1>2>3>4>5>8>1>2>4>5`. They explain every backward move (8) and the 2 repeats.
- **Consequence:** one row per deal in the deal model (`created_at` = earliest `add_time`, flag `has_two_lifecycles`); count the deal once per step and month by its first entry. Raise the question with Enpal.

### E. What `lost_reason` means
- Every deal has one (values 1 to 5: 382, 401, 423, 417, 377). The average highest stage reached is 6.4 to 6.7 for every reason, including deals that reached stage 9. The same 5 deals have two `lost_reason` events (2,000 events for 1,995 deals). For 4 of them it is dated before the last stage event.
- Labels for reasons exist in `fields.field_value_options` (JSONB).
- **Consequence:** `lost_reason` marks the end of a lifecycle, not a lost deal; it must not remove deals from the funnel. Pipedrive only allows a lost reason on lost deals, so ask Enpal how the export was made. There is no deal status column.

### F. Activity types and the done flag
- Four types: `after_close_call` 1,177, `meeting` 1,145, `follow_up` 1,133, `sc_2` 1,124. `done` is true for 2,290 and false for 2,289 (about 50% in every type). 11 `activity_id` values appear twice with different content.
- The 11 repeated ids are collisions, not duplicates: in every pair the deal, assigned user and due date all differ (type differs in 9 of 11). Example: `activity_id` 521731 is a not-done Follow Up Call on deal 762400 (user 918, 2024-07-07) and a done Sales Call 1 on deal 968858 (user 441, 2024-01-09). With 4,579 ids drawn from a 900,000-wide range, chance alone predicts about 11.6 colliding pairs (n(n-1)/(2N)); 11 were observed. Pipedrive ids are unique within an account, so a collision points at the extraction or at generated data, not at the business process.
- **Consequence:** funnel calls are `meeting` (Sales Call 1) and `sc_2` (Sales Call 2); the other two types are excluded. Give activities a surrogate key. `activity_id` uniqueness test at warn.

### G. Can activities be joined to deals
- Only 8 of 4,572 distinct activity `deal_id` values exist in `deal_changes`. Both id ranges are six digits (100007 to 999826 and 100086 to 999037), so chance alone gives about as many.
- **Consequence:** calls cannot be attributed to deals. Count steps 2.1 and 3.1 by `due_to` month from `activity` alone, and document it as an open question for Enpal.

### H. Which date defines Step 1
- Days from creation to the first stage-1 event: median 35, min 2, max 83, quartiles 25 and 45. Created vs entering stage 1 in 2024-01: 247 vs 30. Deals are created 2024-01-01 to 2024-09-13; stage-1 entries continue to 2024-11.
- **Consequence:** the Step 1 definition moves deals between months. Open decision; recommendation is first entry into stage 1.

### I. Effect of backfilling skipped stages
- Distinct deals per stage, recorded vs backfilled: 1: 1,995 / 1,995; 2: 1,479 / 1,990; 3: 1,305 / 1,951; 4: 1,086 / 1,862; 5: 894 / 1,693; 6: 741 / 1,424; 7: 588 / 1,081; 8: 479 / 723; 9: 324 / 324. Backfill adds 4,152 stage entries.
- Backfill rule used here: a deal counts at every stage from 1 to the highest stage it reached; an inferred entry is dated at the earliest recorded entry of a higher stage.
- **Consequence:** these are the expected report totals under each rule. Make the rule a dbt variable.

## 05_quality_checks.sql: data-quality rules and proposed tests

Observed: 0 duplicate events, 0 stage events before creation, 0 owner ids missing from users, 0 same-timestamp ties, 0 nulls, 5 deals with two `add_time`, 8 user rows sharing 4 emails.

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
