---
tags:
  - project/enpal
  - domain/dbt
  - tools/docker
  - type/reference
---

# dbt source tests and the double-load gotcha

## The bug
`docker compose up` runs the `data_loader` service every time. Running it again on an already-loaded DB appends the CSVs again. Tables with primary keys (`users`, `stages`, `fields`, `activity_types`) reject the duplicates; `activity` and `deal_changes` have no PK, so they double (9,158 and 30,812 instead of 4,579 and 15,406).

Fix: `docker compose down -v && docker compose up -d`. Avoid: `docker ps` first; do not `up` twice.

Impact: a doubled load silently doubles funnel counts. The earlier test model showed 4,579 only because it ran before the second load.

## Where the test goes
**Decision (2026-10-22): in the staging YAML**, `models/staging/pipedrive/_stg_pipedrive__models.yml`, on the `stg_*` model that is 1:1 with the raw table (so it still catches the double load). The sources YAML (`_pipedrive__sources.yml`) only declares the tables. Needs `dbt_utils` in `packages.yml` + `dbt deps`.

```yaml
models:
  - name: stg_pipedrive__deal_changes
    description: "Grain: one row per field change (deal_id, changed_field_key, change_time)."
    data_tests:
      # fails if the loader ran twice
      - dbt_utils.unique_combination_of_columns:
          arguments: { combination_of_columns: [deal_id, changed_field_key, change_time] }
  - name: stg_pipedrive__activity
    description: "Grain: one row per activity (surrogate key); source activity_id repeats for 11 ids."
    columns:
      - name: activity_id
        data_tests:
          - unique:
              config: { severity: warn }   # known upstream defect, fixed by the surrogate key
```

If the staging model already de-duplicates `activity`, test the double load on the raw copy instead (a source-level test on the full row) or compare staging row counts with the source in a singular test. Run: `dbt test --select "stg_pipedrive__*"`, or `dbt build`.

Rule (dbt-testing-data-quality skill): known upstream defect → `warn` on the source + fix in staging; true grain violation caused by our own pipeline → hard fail.
