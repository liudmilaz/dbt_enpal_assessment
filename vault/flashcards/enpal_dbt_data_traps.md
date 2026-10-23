---
tags:
  - project/enpal
  - domain/dbt
  - domain/sql
  - type/flashcard
---

# Flashcards — dbt tests and Pipedrive data traps

---

Why did `count(*)` on `activity` return 9,158 instead of 4,579? #card
`docker compose up` runs the `data_loader` every time. A second run on a loaded DB appends the CSVs again. Tables with primary keys reject duplicates; `activity` and `deal_changes` have none, so they double. Fix: `docker compose down -v` then `up -d`.

---

Where do tests on raw tables go in dbt? #card
In the sources YAML (`_pipedrive__sources.yml`), under `data_tests` on the source table. They check the data before any model touches it.

---

Which dbt test checks uniqueness on a combination of columns? #card
`dbt_utils.unique_combination_of_columns` with `arguments: { combination_of_columns: [...] }`. Requires `dbt_utils` in `packages.yml` and `dbt deps`.

---

When should a source test be `severity: warn` vs fail? #card
Known upstream defect you cannot fix (e.g. 11 repeated `activity_id`s): `warn`, and fix it in staging. Grain violation caused by your own pipeline (e.g. double load): hard fail.

---

How do you run only the source tests? #card
`dbt test --select "source:*"`

---

What is the grain of `deal_changes` and what does it contain? #card
An event log: one row per field change. `deal_id, changed_field_key, change_time, new_value`. Keys: `stage_id` (8,906), `user_id` (2,500), `add_time` (2,000), `lost_reason` (2,000). 1,995 deals.

---

Why can't Sales Call 1/2 be joined to deals in the Pipedrive data? #card
Only 8 of 4,579 `activity.deal_id` values exist in `deal_changes` (about the overlap random 6-digit ids would give). So steps 2.1/3.1 are counted from activities by `due_to` month, and it is an open question for Enpal.

---

Which activity types are funnel steps? #card
`meeting` = Sales Call 1 (step 2.1), `sc_2` = Sales Call 2 (step 3.1). `follow_up` and `after_close_call` are not funnel steps.

---

What is the issue with stage jumps in `deal_changes`? #card
Every deal starts at stage 1, but 2,502 jumps skip a step (84% of deals skip at least one), plus 8 backward moves and 2 repeats. Counting recorded entries under-counts the middle of the funnel; options: count recorded only or backfill skipped stages with `is_inferred`.

---

What does `lost_reason` mean in this dataset? #card
Every deal has one, even deals that reached stage 9, and it is set after the last stage change. It marks the end of a lifecycle, not a lost deal. Labels are only inside `fields.field_value_options` (JSONB).

---

What is the definition of `deals_count` in `rep_sales_funnel_monthly`? #card
Distinct deals first entering the stage in that month (event cohort, not cumulative). Month spine bounded to the observed range; empty months are 0, not missing.
