---
tags:
  - project/enpal
  - type/plan
---

# Elementary report layout: tracking the data quality issues

> **As built (2026-10-25):** the tests were reduced to keys (primary, alternate and foreign) and one singular test per discovered issue in `tests/data_quality/`, which returns the affected raw rows and fails (severity error) in the Elementary report. The anomaly and schema monitors below are not implemented; they are the next step together with source freshness and custom tests per business process, once the export is loaded on a schedule. See [[approach]].

How the Elementary report should be organised so that every issue in [[cleansing_proposals]] and [[elementary_rollout]] can be followed run after run. Checked against the docs (docs.elementary-data.com) and the source code of the package `elementary-data/elementary` 0.26.1 and the CLI `elementary-data` 0.26.1 (2026-10-23).

## 1. Elementary test types (what each one watches)

All anomaly tests work the same way: split the data into time buckets on `timestamp_column`, compute a metric per bucket over the `training_period`, and flag a bucket in the `detection_period` whose z-score is at least `anomaly_sensitivity` away from the training mean. Defaults (package source): buckets daily, training 14 days (`days_back`), detection 2 days (`backfill_days`), sensitivity 3, at least 7 training buckets (`min_training_set_size`), direction `both`. Only complete buckets are tested. Without `timestamp_column` the test monitors the whole table's metric from run to run.

| Test | Metric | Fits | Quality dimension (default) |
|---|---|---|---|
| `volume_anomalies` | row count per bucket; `fail_on_zero` fails an empty bucket | double or partial loads, an export that stops | completeness |
| `volume_threshold` | row count change in %, `warn_threshold_percent` 5, `error_threshold_percent` 10 | when the acceptable range is known, instead of a z-score | |
| `freshness_anomalies` | longest time without new rows per bucket (`timestamp_column` required); direction `spike` | a table that stops updating | freshness |
| `event_freshness_anomalies` | delay between event time and load time (`event_timestamp_column`, `update_timestamp_column`) | streaming or near-real-time loads | freshness |
| `column_anomalies` | per column: nulls (`null_count`, `null_percent`); text (`missing_count`, `min_length`, ...); numbers (`min`, `max`, `average`, `zero_count`, ...; `sum` opt-in); booleans (`count_true`, `count_false`) | the rate of a flag column, nulls creeping in | none: set it in `meta` |
| `all_columns_anomalies` | the same, on every column (`exclude_prefix`, `exclude_regexp`) | broad cover on a wide table | none |
| `dimension_anomalies` | row count per value of `dimensions`; each value against its own history, so a value that drops to 0 is flagged | a stage, field key or activity type that stops arriving; a shifting mix | completeness |
| `schema_changes` / `schema_changes_from_baseline` | columns added, dropped or retyped, against the last run / against the columns declared in YAML (`fail_on_added`, `enforce_types`) | upstream export changes | validity |
| `exposure_schema_validity` | the columns an exposure (dashboard) needs still exist with their types | the Lightdash funnel dashboard | validity |
| `metric_stability` | a settled bucket's metric changes later (restatement) | rewritten history, such as merged or deleted deals; **not in the first iteration** (owner, 2026-10-23) | |
| `data_freshness_sla`, `execution_sla` | the data, or the model run, is done before a set time of day | production schedules | |
| `json_schema` | JSON column against a schema | not used here | validity |

Plain dbt tests (`unique`, `not_null`, `accepted_values`, `relationships`, `dbt_utils.*`, singular tests) are stored by Elementary too, with their failed row count and a sample of failed rows; the quality dimension is set for them automatically (`unique` uniqueness, `not_null` completeness, `accepted_values` validity, `relationships` consistency, `expression_is_true` accuracy, `recency` freshness).

**On this one-time export.** Today's date is outside the data, so every anomaly test needs the run date set inside the data with the var `custom_run_started_at` (ISO, confirmed in the package), for example `--vars '{custom_run_started_at: "2025-03-12T00:00:00"}'`, and a `training_period` that reaches back to 2024-01. Use weekly buckets: monthly buckets give 15 months for `deal_changes` and 9 for `activity`, too few with 7 training buckets needed. `dbt source freshness` and the freshness tests stay off locally.

## 2. What the report lets us lay out

The OSS report (`edr report`) has fixed pages; the layout is set by the dbt project, not in the report.

| Page | Shows | Controlled by |
|---|---|---|
| Dashboard | totals: tests, failed, warnings, tables with failed tests, results breakdown, model runs | nothing to set |
| Test results | latest result per test (last 7 days, `--days-back`); failures first; table with columns we can add or filter on: Test name, Table, Column, Last status, Failed rows, Severity, **Test tags**, **Test owners**, **Quality dimension**, Description, Asset owners and tags; expanding a row shows the anomaly chart, or the failed-row sample and the query | test `name`, `description`, `tags`, `meta.owner`, `meta.quality_dimension`, severity |
| Test runs | last 30 runs per test (`--executions-limit`), fail rate | as above |
| Model runs | run status and duration per model | |
| Lineage | upstream and downstream failures per node, down to exposures | exposures in YAML |
| Left navigation | the folder tree of the dbt project | where the YAML files sit |

`edr report --select` accepts only `last_invocation`, `invocation_id:` and `invocation_time:` (code check); the report refuses `tag:` (the rollout plan said otherwise, corrected there). Filtering by tag, owner or dimension happens in the report's table ("Add filter"), or for alerts with `edr monitor --filters tags:... owners:...`.

## 3. Proposed layout

### Three views, one per reader

| View | Filter in Test results | Reader | Question it answers |
|---|---|---|---|
| **A. Known source issues** | tag `dq_known_issue` | process owner (CRM admin, sales operations), KPI owner | how big is each known issue this run, and is it growing? |
| **B. Pipeline promises** | tags `dq_staging` + `dq_report`, severity error (and the raw `dq_check` tests, which should pass) | data team | did our cleansing and the report hold? any red stops the release |
| **C. Monitors** | tag `dq_monitor` | data team | did the data change shape (volume, freshness, mix, schema)? |

Tags, as built (2026-10-23): a **layer** tag from the folder (`dq_raw` on the sources YAML and `tests/data_quality/`; `dq_staging`, `dq_report` later; `dq_exploration` on the old probes), a **kind** tag per test (`dq_known_issue`, `dq_check`, `dq_monitor`) and a **family** tag (`dq_duplicates`, `dq_process`, `dq_types`, `dq_export`, `dq_volume`, `dq_freshness`, `dq_mix`, `dq_schema`).

Each view groups further by **Quality dimension** (column filter), so view A reads as: uniqueness (DUP-1 to DUP-5), consistency (A2), validity (D6, T1, S1), accuracy (D1, D2, D5, A3), freshness (X1).

### Metadata on every test

```yaml
- name: a1_repeated_activity_id__raw          # issue id first, layer last: the list sorts by issue
  description: "A1 / DUP-3. 11 ids repeated at 2026-10-23 (22 rows). A higher count means new repeats; see cleansing_proposals DUP-3."
  config:
    severity: warn
    tags: [dq_known_issue, dq_duplicates]   # dq_raw comes from the folder
    meta:
      issue: A1
      owner: crm_admin
      quality_dimension: uniqueness
```

- **Name** starts with the issue id (`a1_`, `d6_`, `x1_`), so one issue's raw test, staging test and monitor sit together when sorted.
- **Description** holds the baseline count and its date: the reader compares "Failed rows" with it without opening the analysis file.
- **Tags**: layer from the folder, kind and family per test (see above).
- **meta.owner**: the role that acts (`crm_admin`, `sales_ops`, `kpi_owner`, `data_team`; names still open); in production `edr monitor` routes alerts by it.
- Singular tests take the description in `meta.description` (Elementary reads it from there); generic tests use `description:`. Descriptions show in the report for source tests too (confirmed by the owner).
- **meta.quality_dimension**: set on every singular test and `column_anomalies`, which have no default.

### Folder tree (left navigation)

```
models/
  staging/pipedrive/
    sources/_pipedrive__sources.yml  raw tests and source monitors (views A, B, C); own folder so dbt_project.yml can set warn + dq_raw for it
    _pipedrive__models.yml         staging tests (view B)
  intermediate/
    _int_pipedrive__models.yml     flag monitors D1, D2, D3 (view C)
  marts/
    _marts__models.yml             report grain, reconciliation (view B)
    _exposures.yml                 Lightdash funnel dashboard
tests/data_quality/                singular tests on raw data, one file per issue (d5, a3, t1, s1, x1)
```

Declaring the Lightdash dashboard as an exposure makes Lineage end at the dashboard, so a red source test shows which report it touches, and `exposure_schema_validity` protects the columns the dashboard uses.

## 4. Each detected issue in the report

| Issue | Test (Elementary type) | Layer, view | Dimension | What a change looks like |
|---|---|---|---|---|
| DUP-1 full-row duplicates | `dbt_utils.unique_combination_of_columns` on source; `unique` on `deal_change_key` | raw A; staging B | uniqueness | raw failed rows > 0 = a double load |
| DUP-2 / D3 two lifecycles per `deal_id` | singular `unique_add_time_per_deal`; `column_anomalies: count_true` on `has_two_lifecycles`, weekly by `created_at` | raw A; monitor C | uniqueness | count above 5 |
| DUP-3 / A1 repeated `activity_id` | `unique` on source (warn); `unique` + `not_null` on staging | raw A; staging B | uniqueness | raw above 11; staging must stay 0 |
| DUP-5 / U1 shared emails | `unique` on `email` (warn) | raw A | uniqueness | above 4 |
| D1 skipped stages | `column_anomalies: count_true` on `skips_a_stage`, weekly | monitor C | accuracy | a week far above or below 84% |
| D2 after-sale without Closing | `column_anomalies: count_true` on `is_after_sale_without_closing` | monitor C | accuracy | same |
| D4 lost reason on every deal | `dimension_anomalies` on `lost_reason_id` | monitor C | consistency | a reason that appears or vanishes |
| D5 generated timing | singular, share of changes at the creation clock time | raw A | accuracy | share drops below 50% = real timestamps arrive |
| D6 mixed types | `accepted_values` per key on source; `not_null` per typed column on staging | raw A; staging B | validity | any staging failure |
| A2 activities without a known deal | `relationships` on `deal_id` (warn) | raw A | consistency | match rate moves from 8 of 4,579 |
| A3 after-close calls before Closing | singular | raw A | accuracy | above 157 |
| A4 done flag ~50% | `dimension_anomalies` on `type` with `where_expression: done`, weekly by `due_to` | monitor C | consistency | one type's done rate leaves the band |
| T1 inactive type in use | `accepted_values ['Yes','No']`; singular on activities of inactive types | raw A | validity | new inactive types in use |
| S1 stage spelling | singular, stage name vs field label | raw A | validity | more than 1 mismatch |
| X1 export ends | `volume_anomalies` on `activity`, weekly by `due_to`, `fail_on_zero: true`; `freshness_anomalies` | monitor C | completeness, freshness | empty weeks: calls stop after 2024-09-13 |
| Schema | `schema_changes_from_baseline` on all six sources | monitor C | validity | any column change |
| Volume | `volume_anomalies` on `deal_changes` and `activity`, weekly | monitor C | completeness | a week far from the trend |
| Field keys, stages | `dimension_anomalies` on `changed_field_key`; on `funnel_step` of the report | monitor C | completeness | a key or step drops to 0 |
| Report | grain `unique_combination_of_columns`, reconciliation, `exposure_schema_validity` | report B | uniqueness, validity | any failure |

Why `fail_on_zero` for X1: the weeks after 2024-09 are inside the training period too, so their zeros lower the mean and widen the band; the z-score alone would not flag them. First run (2026-10-23, run date 2025-03-12): `x1_volume_weekly__activity` warns with 4 empty weeks; `x1_freshness_weekly__activity` **passes**, for the same reason (the long gaps are in the training too). Freshness anomalies only catch the week a table stops, so X1 stays covered by the volume monitor and the singular test.

## 5. Reading routine

1. **Dashboard**: any red? Red is only possible in view B or a monitor at error.
2. **View B**: must be empty. A failure stops the release; open the row, read the failed-row query.
3. **View A**: compare each warning's Failed rows with the baseline in its description. Higher: open **Test runs** for the trend, then send it to the owner in `meta.owner`.
4. **View C**: open each anomaly chart; a point outside the band is either a real change (new issue: add it to [[cleansing_proposals]]) or an expected one (raise `anomaly_sensitivity` or exclude it with `anomaly_exclude_metrics`).
5. **Lineage** on any red node: which models and which dashboard are affected.

## 6. As built

See "As built" in [[elementary_rollout]]: the tags, names and descriptions above are in the sources YAML and `tests/data_quality/`; the report runs on http://localhost:8081/elementary_report.html. Elementary's own tests show their type as name in the report, so their issue id is read from the description.

## 7. Open

- Owner role names (`crm_admin`, `sales_ops`, `kpi_owner`, `data_team`): left open (owner, 2026-10-23).
