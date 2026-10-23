---
tags:
  - project/enpal
  - domain/eda
  - domain/dbt
  - domain/data-quality
  - type/reference
---

# EDA and data-quality skills

Created 2026-10-22 from: the AI-overview text on EDA (Tukey), the GeeksforGeeks article "What is Exploratory Data Analysis", and a list of Kimball-style data-quality check classes.

Location: local clone `career/code/data-engineering-agent-skills`, branch `skills/eda`, pushed as PR #6. Installed in the Enpal project at `.claude/skills/` (untracked).

| Skill | Use when |
|---|---|
| `eda-source-profiling` | New raw source: structure, nulls, distributions, key overlap, outliers, documenting findings with consequences |
| `eda-event-log-and-funnel-checks` | Event/change-history log feeding a funnel: skipped steps, duplicates, orphan keys, date coverage, metric decisions |
| `eda-dbt-test-probes` | Probe a source with dbt tests during EDA (4 classes), triage failures, then promote confirmed ones to staging |

## EDA in one page

**Goals:** understand structure, spot anomalies, assess distributions, uncover relationships, guide downstream work.

**Types:** univariate (histogram, box plot, bar chart, summary stats) → bivariate (scatter, correlation, cross-tab, line over time, covariance) → multivariate (pair plots, PCA, spatial).

**Workflow (GfG, 8 steps):** understand problem/data → import and inspect → handle missing data → explore characteristics (central tendency, spread, skew, kurtosis, outliers) → transform → visualise relationships → handle outliers → communicate findings.

**Missing data:** find the cause first; removing rows can bias, imputing adds uncertainty (mean, median, regression, KNN).
**Outliers:** detect with IQR (`q1 - 1.5·IQR`, `q3 + 1.5·IQR`) or z-score (|z| > 3); judge with domain knowledge; cap/transform; remove only if clearly wrong.

**In SQL/dbt:** profile each table alone first (grain, nulls, categories, dates); queries in `analyses/` with Question / Finding / Consequence headers; summary table in `docs/exploratory_analysis.md`; never impute or delete silently in staging — report and ask.

## Data-quality check classes

1. **Field-level:** type/format, nulls in required fields, range/domain.
2. **Record-level:** uniqueness / key integrity, mandatory attributes present.
3. **Referential:** orphan foreign keys (drop / reject / map to `Unknown`), conformed dimension consistency.
4. **Business logic:** arithmetic across columns, temporal sequence (order ≤ ship).

Mapping to dbt tests: `not_null`, `accepted_values`, `accepted_range`, `unique`, `unique_combination_of_columns`, `relationships`, `expression_is_true`, singular tests. Severity: own-pipeline defect = error; known upstream defect = warn.

Related: [[dbt_source_tests_and_loader_gotcha]], [[02_data_findings]].

## Update 2026-10-22: generic skills + dbt test probes

- Skills were rewritten with neutral placeholders (`entity_id`, `event_key`, `event_time`, `step`, `raw.tasks`) so they work for any event-log source, not only Pipedrive. PR #6 in `data-engineering-agent-skills` updated.
- `eda-findings-to-dbt-tests` became **`eda-dbt-test-probes`**: Phase 1 *probe* (many tests on sources, `dbt test --select "source:*" "test_type:singular" --store-failures`, every failure is a finding), Phase 2 *promote* (keep tests that guard a real claim, move to staging with severity).
- `eda-source-profiling` got a new step 6, "Probe with dbt tests".

### First probe run on the Pipedrive sources (44 tests, 37 pass, 7 fail)

| Failing test | Rows | Class | Finding |
|---|---|---|---|
| `activity.deal_id` relationships -> `deal_changes.deal_id` | 4,571 | referential | activity deal ids do not match deals |
| `explore_stage_moves_not_forward_by_one` (informational) | 2,512 | business logic | 2,502 skips + 8 backward + 2 repeats |
| `activity.activity_id` unique | 11 | record | repeated activity ids |
| `users.email` unique | 4 | record | shared emails |
| `unique_add_time_per_deal` | 5 | record | deals with two creation events |
| `unique_lost_reason_per_deal` | 5 | record | the same 5 deals have two lost reasons (new) |
| `explore_lost_before_last_stage` | 4 | business logic | lost reason dated before last stage |

37 passes include: no duplicate events (full-grain test), no nulls, owners and stage ids all exist, stage and activity-type domains valid, all deals start at stage 1, no stage event before creation, no same-timestamp ties, done is boolean, due dates in range.
Failing rows are stored in schema `public_dbt_test__audit`. Files: `models/staging/pipedrive/_pipedrive__sources.yml`, `tests/exploration/explore_*.sql`.

Gotchas met: two tests with the same generated name need `name:`; `source('a','b')` inside a YAML flow mapping breaks the parse (use block style); `relationships` cannot cast text to int (singular test instead).

## Update 2026-10-22: distributions

`eda-source-profiling` got a **Distributions** section (tested on Postgres, Snowflake equivalents noted): numeric summary with skewness and excess kurtosis, quantiles, equal-width histogram with text bars (`width_bucket`), deciles (`ntile`), categorical frequency with cumulative share, cardinality and distinct ratio, monthly volume, distribution of a count per entity, and a distribution compared across groups. Includes a "Reading the shape" table (uniform = skew ~0 and excess kurtosis ~ -1.2, long tail, two humps, one dominant value, hard cut, empty bins). `eda-event-log-and-funnel-checks` got rows for gaps between events, events per entity and events per period. Queries on the real data: `analyses/02_distributions.sql`.

## Update 2026-10-22: nulls and keys first

`eda-source-profiling` now has steps 3 (**Nulls**, first analysis file) and 4 (**Primary and foreign keys**, second analysis file), a "Nulls and keys" section (null profile of every column, declared constraints, primary key candidates, alternate keys, foreign key inclusion test, conditional foreign keys in key-value logs, key register) and says the first two analysis files are always nulls and keys. `eda-dbt-test-probes` derives probes from the key register. Project files: `analyses/01_nulls_and_keys.sql` (older files merged into `04_descriptive_analysis.sql`, `02_distributions.sql`, `03_outliers.sql`, `05_quality_checks.sql`).

## Update 2026-10-22: one file per raw table

`eda-source-profiling` now prescribes the layout used in the project: **one analysis file per raw table**, each with the same six sections (1 all columns, 2 primary key given or identified with unique and not-null check, 3 foreign keys with nulls, matches, orphans and parent uniqueness, 4 nulls and not nulls, 5 outliers, 6 descriptive analytics, including distributions), plus **one overall data-quality findings file** with one result row per check (class, violations, proposed test severity, result). Files: `analyses/01_deal_changes.sql` to `06_fields.sql`, `07_data_quality_findings.sql`. The findings are charted in the dashboard.
