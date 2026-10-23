---
tags:
  - project/enpal
  - type/plan
---

# Elementary rollout: data quality tests and monitoring

Plan for monitoring the data quality issues in [[findings]] (main list: `analyses/00_data_quality_issues.sql`) with **Elementary**, the open-source dbt package plus CLI. Status: plan, nothing installed yet.

## Split of tools

| Tool | Used for | Not used for |
|---|---|---|
| dbt tests (generic, `dbt_utils`, singular) | the checks themselves: keys, domains, relationships, business rules, report grain | |
| Elementary dbt package | stores every test result and run in tables in schema `public_elementary`; adds anomaly and schema-change tests | |
| Elementary CLI `edr` | the data quality report (HTML: test results over time, failed rows, lineage) and, in production, alerts | |
| Lightdash | **final dashboards only**: `rep_sales_funnel_monthly` | quality checks; the data quality charts built during exploration are retired from Lightdash |

Why Elementary, not Lightdash, for quality: it reads dbt's own test results (no second set of SQL to maintain), keeps the history of each test, shows failed rows and lineage, and knows owners and tags from the YAML. A BI tool would only chart counts that someone recomputes by hand.

## Versions

- Package `elementary-data/elementary` 0.26.1 (dbt `>=1.0, <3.0`; project runs dbt-core 1.12.5 on Postgres, supported).
- CLI `elementary-data[postgres]` 0.26.1 (Python 3.10 to 3.13), installed in the project venv.

## How the issues become tests

Two kinds of check, because the issues are of two kinds:

1. **Known defects, pinned to today's count.** On the one-time load the count is fixed, so the test warns at today's count and fails above it: `warn_if: ">0"`, `error_if: ">N"` with N the measured count. A known issue stays visible (warn) without breaking the build; a new instance fails it.
2. **Rates that move with new data, as anomaly monitors.** In production the counts grow with the deals, so a pinned number would fail every week. A rate is put on a model as a boolean flag (for example `skips_a_stage` on `int_pipedrive__deals`) and Elementary's `column_anomalies` (`count_true`) watches it per month of `created_at`: it fails when a month leaves the range learnt from the earlier months.

Severity follows [[findings]]: **error** when our own pipeline would be wrong, **warn** for a known upstream defect handled in staging, **info** (documented, no test) when nothing can be checked.

Every test gets `meta` with the issue id, the category (process or data) and the owner, and `tags: [data_quality]`, so the Elementary report can be filtered by issue and owner.

| Issue | Category | Test | Where | Severity |
|---|---|---|---|---|
| D1 stages skipped (84%) | process | flag `skips_a_stage`, `column_anomalies: count_true` per month | `int_pipedrive__deals` | warn |
| D2 after-sale without Closing (683) | process | flag `is_after_sale_without_closing`, `column_anomalies: count_true` | `int_pipedrive__deals` | warn |
| D3 two lifecycles (5 deals) | process | existing `unique_add_time_per_deal`, `error_if: ">5"`; flag `has_two_lifecycles` | source `deal_changes`; `int_pipedrive__deals` | warn |
| D4 lost reason on every deal | process | `dimension_anomalies` on `lost_reason_id`, time `created_at` | `int_pipedrive__deals` | warn |
| D5 changes at the creation clock time (99.8%) | data | singular test: share above 50% signals generated or backfilled history | `stg_pipedrive__deal_changes` | warn |
| D6 mixed types in `new_value` | data | existing `accepted_values` per key; `not_null` on the typed columns after the cast | source; staging | error |
| A1 repeated `activity_id` (11) | data | existing `unique`, `error_if: ">11"`; `unique` + `not_null` on surrogate `activity_key` | source; `stg_pipedrive__activity` | warn; error |
| A2 activities not linked to deals (8 of 4,579 match) | process | existing `relationships` on `deal_id`, pinned to today's failures | source `activity` | warn |
| A3 after-close calls before the first Closing (157) | process | singular test, `error_if: ">157"` | `int_pipedrive__sales_calls` | warn |
| A4 done flag ~50% for every type | process | `dimension_anomalies` on `activity_type` with `is_done`, time `due_at` | `stg_pipedrive__activity` | warn |
| T1 inactive type in use; `active` as text | data | `accepted_values ['Yes', 'No']` on source; singular test: activities of inactive types, `error_if: ">1133"` | source; staging | error; warn |
| U1 shared emails (4) | data | `unique` on `email`, `error_if: ">4"` | `stg_pipedrive__users` | warn |
| U2 1,347 owners for 1,995 deals | data | none, documented | | info |
| S1 "Qualified lead" vs "Qualified Lead" | data | singular test: stage name differs from field label, `error_if: ">1"` | staging | warn |
| X1 tables end on different dates | export | singular test: last dates of `deal_changes`, `activity`, `users` more than 31 days apart | staging | warn |

General monitors, independent of the known issues:

| Check | Test | Where | Severity |
|---|---|---|---|
| A column added, dropped or retyped upstream | `elementary.schema_changes_from_baseline` (columns and types declared in the sources YAML) | all six sources | error |
| A double or partial load | existing full-row `unique_combination_of_columns`; `elementary.volume_anomalies`, time `change_time` / `due_to`, weekly buckets | `deal_changes`, `activity` | error; warn |
| A stage or event key that stops arriving | `elementary.dimension_anomalies` on `changed_field_key` | `deal_changes` | warn |
| Report grain and reconciliation | `unique_combination_of_columns [month, funnel_step]`, `deals_count >= 0`, totals per step equal the targets in [[model_plan]] | `rep_sales_funnel_monthly` | error |
| A funnel step that drops out in a month | `elementary.dimension_anomalies` on `funnel_step`, time `month` | `rep_sales_funnel_monthly` | warn |
| Freshness | `elementary.event_freshness_anomalies` in production only; the static export would always be stale | sources | off locally |

The exploration probes in `tests/exploration/` that confirmed a finding move into these model tests; the others are deleted.

## How I will do it

### Phase 1: install and configure (now, sources only)

1. New branch `feature/elementary` from the solution branch, PR to the fork only.
2. `packages.yml`: add `elementary-data/elementary` 0.26.1; `dbt deps`.
3. `dbt_project.yml`: give the package its own schema, so its tables stay out of the analytics schema:
   ```yaml
   models:
     elementary:
       +schema: elementary
   ```
4. `dbt run --select elementary`: creates the Elementary tables (`elementary_test_results`, `dbt_run_results`, `dbt_models`, ...) in `public_elementary`. From then on the package's `on-run-end` hook writes every run and test result there.
5. CLI in the venv: `pip install 'elementary-data[postgres]==0.26.1'`; add an `elementary` profile to the repo's `profiles.yml` (same local Postgres, schema `public_elementary`, the task's admin/admin), generated with `dbt run-operation elementary.generate_elementary_cli_profile`.
6. `.gitignore`: `edr_target/`.
7. Check: `dbt test --select source:postgres_public`, then `select test_name, status, failures from public_elementary.elementary_test_results` returns one row per probe, with the counts in the analysis files.

### Phase 2: sources (now)

1. Add `meta`, `tags`, the pinned thresholds and the source-level rows of the tables above to `_pipedrive__sources.yml`.
2. Declare column types for `schema_changes_from_baseline`; add volume and dimension monitors on `deal_changes` and `activity`.
3. Anomaly tests on a one-time load: the history is 2024-01 to 2025-03 and today is 2026, so the run date is set inside the data range with the Elementary var `custom_run_started_at` (to verify in phase 1) and `training_period` covers the earlier months. Without this, every bucket is "old" and nothing is tested.
4. `edr report --profiles-dir .` writes `edr_target/elementary_report.html`; open it and compare each failure count with `analyses/00_data_quality_issues.sql`. A difference means the test or the analysis is wrong.

### Phase 3: models (after the models exist)

The test YAML of each model and the singular tests are added as the models are written; the flag columns (D1, D2, D3) are a proposal for `int_pipedrive__deals`. Then `dbt build` runs models and tests together, and the report shows each issue on the model it affects, with lineage to the source.

### Phase 4: dashboards and production

- Lightdash: only the funnel dashboard on `rep_sales_funnel_monthly`; the exploration charts on data quality are removed from the Lightdash project (with the owner's go).
- Production, for the README (not built here): `dbt build` then `edr monitor` sends Slack alerts for failed tests to the owner in `meta`; `edr report` (or `edr send-report` to a bucket) publishes the report after each run; freshness monitors switched on; pinned thresholds replaced by the anomaly monitors as new data arrives.

## Who does what

| Step | Who |
|---|---|
| Package, schema, CLI, profile, `.gitignore` (phase 1) | Claude, reviewed by the owner |
| Source tests and monitors (phase 2) | Claude drafts, owner reviews |
| Model tests, flag columns, singular tests (phase 3) | owner writes, Claude reviews |
| Retire the Lightdash data quality charts | owner decides |

## Open decisions

- Separate PR for Elementary, or inside the solution PR (proposed: separate branch, merged into the solution branch).
- Flag columns D1 to D3 on `int_pipedrive__deals`: yes or no.
- Pinned thresholds as above, or warn only.
