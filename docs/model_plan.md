# Model plan

Intended design, from the exploration. The owner writes the models herself; this file is the spec, not code. Items marked *open* depend on decisions not yet confirmed (see `NOTES.md`).

## Layout

`dbt_project.yml` sets `+schema: pipedrive_analytics` and `+materialized: table` for the whole project; override per folder: staging and intermediate as views, marts as tables. YAML next to the models, prefixed with an underscore (`_pipedrive__sources.yml`, `_stg_pipedrive__models.yml`, ...). Sources are declared in `models/staging/pipedrive/_pipedrive__sources.yml` (`postgres_public`).

## Staging (view, one model per raw table, rename and cast only)

| Model | Grain | Key | Notes |
|---|---|---|---|
| `stg_pipedrive__deal_changes` | one field change | (`deal_id`, `changed_field_key`, `change_time`) unique | typed `change_time`; keep `new_value` text; add typed columns by key (stage id as int for `stage_id`, owner id as int for `user_id`, timestamp for `add_time`) |
| `stg_pipedrive__activity` | one activity row | surrogate `activity_key` (hash of all columns) | source `activity_id` repeats for 11 ids; rename `type` to `activity_type`, `done` to `is_done`, `due_to` to `due_at`, `assigned_to_user` to `assigned_user_id` |
| `stg_pipedrive__activity_types` | one activity type | `activity_type` (source `type`) unique | `active` to boolean `is_active`; `type` is Pipedrive's key string |
| `stg_pipedrive__stages` | one stage | `stage_id` unique | name casing: "Qualified lead" here, "Qualified Lead" in `fields`; the report uses the names from the task |
| `stg_pipedrive__field_options` | one option of a list field | (`field_key`, `option_id`) | unnest `fields.field_value_options` (JSONB): stage labels and lost-reason options |
| `stg_pipedrive__users` | one user | `user_id` unique | email is not unique (4 shared); never key on email |

## Intermediate (view, one business rule or grain change per model)

| Model | Grain | Key | Rule |
|---|---|---|---|
| `int_pipedrive__deals` | one row per deal | `deal_id` unique, not null | `created_at` = earliest `add_time`; first and last owner; latest `lost_reason`; `has_two_lifecycles` when more than one `add_time`; one row for each of the 1,995 deals |
| `int_pipedrive__deal_stage_entries` | one deal at one stage (recorded) | (`deal_id`, `stage_id`) | `entered_at` = `min(change_time)` of the stage events; `is_inferred` = false; use `min() group by`, no self joins |
| `int_pipedrive__deal_stage_entries_backfilled` | one deal at one stage reached (recorded and inferred) | (`deal_id`, `stage_id`) | stages 1 to the highest stage the deal reached; inferred rows get `entered_at` = earliest recorded entry of a higher stage and `is_inferred` = true. Controlled by var `funnel_backfill_skipped_stages` (default true, decided) |
| `int_pipedrive__sales_calls` | one activity | `activity_key` | only `meeting` (Sales Call 1) and `sc_2` (Sales Call 2); funnel step from the step mapping; `is_done`, `due_at`, `deal_id` |

## Marts (table)

| Model | Grain | Key | Notes |
|---|---|---|---|
| `dim_funnel_step` (seed `funnel_steps.csv` plus model) | one funnel step | `funnel_step` | 11 rows: 1, 2, 2.1, 3, 3.1, 4 to 9. Columns: `funnel_step` (text), `kpi_name`, `source_type` (`stage` or `activity`), `stage_id` or `activity_type`, `sort_order`. Step names are the task's: Lead Generation, Qualified Lead, Sales Call 1, Needs Assessment, Sales Call 2, Proposal/Quote Preparation, Negotiation, Closing, Implementation/Onboarding, Follow-up/Customer Success, Renewal/Expansion |
| `fct_deal_stage_entries` | one deal at one stage | (`deal_id`, `stage_id`) | the chosen int model plus keys to `dim_funnel_step` (optional; the report may read the intermediate directly) |
| `fct_sales_calls` | one activity | `activity_key` | optional wrapper over the int model |
| `rep_sales_funnel_monthly` | one funnel step in one month | (`month`, `funnel_step`) unique | contract enforced; columns exactly `month` (date, first day of the month), `kpi_name`, `funnel_step`, `deals_count` (integer) |

## Metric definitions

- **Stage steps (1, 2, 3, 4, 5, 6, 7, 8, 9):** `deals_count` = `count(distinct deal_id)` whose first entry into that stage falls in the month (event cohort, not cumulative). With backfill on, inferred entries count and are dated as described above. A deal with two lifecycles counts once per step, by its first entry.
- **Step 1:** first entry into stage 1 (*open*; alternative is `add_time`).
- **Steps 2.1 and 3.1:** `count(distinct deal_id)` over `activity` rows of type `meeting` (2.1) and `sc_2` (3.1) with `done = true`, by month of `due_at` (*open*; var `calls_done_only`, default true). These `deal_id`s do not match the deal history, so the figure is "distinct deal ids with a call due in the month", not a subset of the funnel deals.
- **Month spine:** one row per month and funnel step from 2024-01 to 2025-02 (*proposed*), zero-filled with a left join from a bounded spine; the calls are 0 from 2024-10 because activity ends 2024-09-13.
- Convention: write the grain of every model in its description; ratios are never stored.

## Expected totals (reconciliation targets)

Distinct deals per stage over all months: step 1 = 1,995 (both rules). Recorded: 2: 1,479; 3: 1,305; 4: 1,086; 5: 894; 6: 741; 7: 588; 8: 479; 9: 324. Backfilled: 2: 1,990; 3: 1,951; 4: 1,862; 5: 1,693; 6: 1,424; 7: 1,081; 8: 723; 9: 324. Under the stage-1-entry rule, month counts for step 1 are not the creation counts (2024-01: 30 entries vs 247 created).

## Tests to put in the models (see `docs/findings.md` for severities)

- Staging: keys `unique`/`not_null`, `accepted_values` (event key, stage ids 1 to 9), `relationships` (stage and owner ids, assignee, activity type), the full-grain `unique_combination_of_columns` on `deal_changes` (catches a double load), email uniqueness at warn.
- Intermediate: `unique` on `deal_id` and on (`deal_id`, `stage_id`); first stage is 1; no stage event before creation.
- Marts: `unique_combination_of_columns [month, funnel_step]`, `deals_count >= 0`, `relationships` of `funnel_step` to `dim_funnel_step`, singular reconciliations: step 1 total equals distinct deals; monthly sums equal the totals above; with `calls_done_only` off the call totals rise.
- One unit test on the activity de-duplication or the backfill rule.

## Efficiency notes for the README

`min() ... group by` instead of self joins, filters before joins, indexes on `deal_id`, `changed_field_key`, `change_time` through a post-hook (a small macro to write), `EXPLAIN ANALYZE` before and after. No incremental models: about 15k rows.
