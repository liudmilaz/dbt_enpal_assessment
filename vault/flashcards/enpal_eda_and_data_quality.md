---
tags:
  - project/enpal
  - domain/eda
  - domain/dbt
  - domain/data-quality
  - type/flashcard
---

# Flashcards — EDA and data-quality checks

---

What question does exploratory data analysis answer before modelling? #card
"What can I safely assume about this data?" (Tukey-style: summaries and visuals rather than pre-set hypothesis tests). Every finding must end with a consequence for a model, a test, a definition or an open question.

---

List the 8 EDA workflow steps. #card
Understand problem and data → import and inspect → handle missing data → explore characteristics (centre, spread, skew, outliers) → transform → visualise relationships → handle outliers → communicate findings.

---

Univariate vs bivariate vs multivariate EDA? #card
Univariate: one variable (histogram, box plot, bar chart, summary stats). Bivariate: two variables (scatter, correlation, cross-tab, line over time). Multivariate: three or more (pair plots, PCA, spatial).

---

How do you detect outliers with the IQR rule? #card
Outlier if `x < Q1 − 1.5·IQR` or `x > Q3 + 1.5·IQR`, with IQR = Q3 − Q1. In SQL use `percentile_cont(0.25/0.75) within group (order by x)`. The z-score alternative: `abs((x − avg)/stddev) > 3`.

---

Missing values: what do you do first, and what may you not do silently? #card
First find out why the value is missing (not applicable / not yet happened / broken). Do not impute, cap or delete silently in raw/staging: each choice changes the numbers. Report and ask.

---

Why profile each table alone before joining? #card
A join can fan out and pass as a finding. Know each table's grain, nulls and key uniqueness first, then measure key overlap between tables.

---

How do you tell whether two id columns are really related? #card
Compare the observed overlap (e.g. 8 of 4,572 activity deal_ids exist in deal_changes) with the overlap random ids from the same range would give. If they match, the keys are unrelated and the tables cannot be joined.

---

What must each `analyses/*.sql` file start with? #card
A comment block with Question, Finding and Consequence. The summary table in `docs/exploratory_analysis.md` repeats Finding, Evidence (link) and Consequence, plus date coverage per source and open questions for the data owner.

---

Name the four classes of data-quality checks. #card
Field-level (type/format, nulls, range/domain); record-level (uniqueness, mandatory attributes); referential (orphan foreign keys, conformed dimensions); business logic (arithmetic across columns, temporal sequence).

---

What can an ETL do with an orphan foreign key? #card
Drop the row (only if the loss is counted and tested), reject and report it, or map it to an explicit `Unknown` surrogate key. State the choice in the model description.

---

Map the four check classes to dbt tests. #card
Field: `not_null`, `accepted_values`, `accepted_range`, contract `data_type`. Record: `unique`, `unique_combination_of_columns`. Referential: `relationships`. Business logic: `expression_is_true` (arithmetic, created ≤ first stage) and singular tests (reconciliations).

---

Where do the Enpal data-quality tests live and why? #card
In the staging YAML next to the `stg_*` model (decision 2026-10-22): the property first becomes true in staging, and the staging model is 1:1 with the raw table, so a grain test there also catches the double load.

---

Severity rule for data-quality tests? #card
Defect created by our own pipeline (double load, bad join) = error. Known upstream defect (repeated ids, shared emails) = warn with a comment and the fix in staging. Expected incomplete data (activity ends before events) = warn; do not delete the test.

---

Event-log checks before defining a funnel KPI? #card
Grain of the log, per-key row counts, creation event per entity, first stage, distinct entities per stage, skipped steps (`stage − lag(stage) > 1`), backward moves, repeats, same-timestamp ties, duplicate events, terminal fields, lag between creation and first stage, activity key overlap, date coverage per source.
