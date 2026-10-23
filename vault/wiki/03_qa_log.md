---
tags:
  - project/enpal
  - type/qa-log
---

# Q&A log — questions asked during the implementation

Rule: every question asked while implementing is added here (grouped by topic), and linked to its note. Flashcards are kept outside this vault (Drive: `Learning/claude_based_learning/flashcards/project/enpal_*.md`).

## Docker and environments → [[docker_and_environments]]
| Date | Question | Short answer |
|---|---|---|
| 2026-10-21 | What is Docker for, and how does a Docker env compare with a Python env? | Docker isolates the whole runtime (runs Postgres); venv isolates Python packages only (runs dbt) |
| 2026-10-21 | Why not run Postgres without containerization? | Reproducibility, automated setup, cheap reset, no host pollution, pinned version; cost: VM layer |
| 2026-10-21 | How do I run `docker compose up` manually? | `cd` into the project folder, check `docker ps`, `docker compose up -d` |
| 2026-10-22 | `no configuration file provided: not found` | Wrong folder; Compose looks for `docker-compose.yml` in the current directory |

## Databases → [[oltp_vs_olap_databases]], [[postgres_at_scale]]
| Date | Question | Short answer |
|---|---|---|
| 2026-10-21 | How does this scale? Cloud (BQ/Snowflake) vs Postgres; compare MySQL, Oracle, SQL Server | OLTP vs OLAP, row vs columnar, coupled vs separated compute |
| 2026-10-21 | How else is Postgres used in a bigger company? | App backend + replicas + pooling + partitioning + CDC to warehouse; analytics on it is what crashes |

## Architecture → [[startup_spreadsheet_data_stack]]
| Date | Question | Short answer |
|---|---|---|
| 2026-10-21 | Is local Postgres scalable for raw Excel/CSV in a startup? Cheaper options? | Not for a team; bucket + loader + dbt on BigQuery free tier or managed Postgres |

## dbt and data quality → [[dbt_source_tests_and_loader_gotcha]]
| Date | Question | Short answer |
|---|---|---|
| 2026-10-22 | Why is `count(*)` on `activity` 9,158? | Loader ran twice; no PK on activity/deal_changes; `down -v` and reload |
| 2026-10-22 | Where do you add the source-level test? | `_pipedrive__sources.yml`, `unique_combination_of_columns` on the true grain |

## EDA and data quality → [[eda_skills]]
| Date | Question / request | Short answer |
|---|---|---|
| 2026-10-22 | Add to the plan: tests in dbt, in staging | Data-quality tests live in `_stg_pipedrive__models.yml`; sources YAML only declares tables ([[dbt_source_tests_and_loader_gotcha]]) |
| 2026-10-22 | Create Claude Code skills for EDA before starting, from the EDA text, the GfG article and the data-quality check list | Three skills in `data-engineering-agent-skills` branch `skills/eda`, installed in the project's `.claude/skills/` ([[eda_skills]]) |

## Exploration tooling → [[vscode_postgres_manual_exploration]]
| Date | Question / request | Short answer |
|---|---|---|
| 2026-10-22 | Do the exploratory analysis first and show results with charts and summaries | 11 `analyses/*.sql` files + a dashboard "Pipedrive funnel EDA"; findings 14-22 in [[02_data_findings]] |
| 2026-10-22 | Set up VS Code and learn the data manually with Postgres | `code` on PATH, SQLTools + pg driver, connection to localhost:5432, run `analyses/` queries, psql via `docker exec` ([[vscode_postgres_manual_exploration]]) |

## Pipedrive source understanding → [[pipedrive_crm_terms]]
| Date | Question / request | Short answer |
|---|---|---|
| 2026-10-22 | Add a text block about the Pipedrive CRM source to the charts; research the Pipedrive terms | New section "Reading the source: Pipedrive terms" on the dashboard; notes in [[pipedrive_crm_terms]] |

| 2026-10-22 | Review the skills, make them generic, and apply dbt tests during the exploration to find data-quality issues | Skills rewritten with neutral placeholders; new `eda-dbt-test-probes`; first probe run: 44 tests, 7 failures ([[eda_skills]]) |

| 2026-10-22 | Include the distribution and its SQL query in the EDA skills | Distributions section added to `eda-source-profiling` and distribution rows to the event-log skill; real-data run in `analyses/02_distributions.sql` |

| 2026-10-22 | Find the deal for `activity_id` 521731 and where in the UI to verify whether the duplicate is a process mistake or by design | Two unrelated activities share the id (deals 762400 and 968858); verify in the source Pipedrive via Activities list columns (ID activity, ID deal) and the two deal pages; evidence points to an id collision, not a duplicate ([[02_data_findings]]) |
| 2026-10-22 | Tour guide through the data added to the trial account | Import of 1,995 deals run in the UI (stages mapped, custom source fields, creation date mapped); activities not yet imported; see `docs/pipedrive_tour.md` when written |

| 2026-10-22 | In the exploratory analysis identify the nulls and the primary and foreign keys; if the skills do not say it, change them and make it one of the first files | Skills updated (steps 3 and 4, key register); new `analyses/01_nulls_and_keys.sql`, older files merged and renumbered 02-05; key register in `docs/findings.md` |

| 2026-10-22 | Put nulls and keys in the same file, then distributions, then outliers; combine the descriptive queries in one file | Analysis files now: 00 select all, 01 nulls and keys, 02 distributions, 03 outliers, 04 descriptive analysis (sections A to I), 05 quality checks; skills describe this layout ([[eda_skills]]) |

| 2026-10-22 | What is `changed_field_key` within the Pipedrive system? | The technical key of the deal field that changed (flow / changelog entry); `fields.csv` maps key to display name; see Settings, Data fields ([[pipedrive_crm_terms]]) |

| 2026-10-22 | Simplify 01_nulls_and_keys: only the identified primary keys (given by the task or identified), foreign keys that exist with null counts, check unique and not null | File and findings simplified; skills updated (PR #6) |

| 2026-10-22 | Verify which tables are dictionaries (from `00_select_all_raw.sql`) and add comments, also for the fact tables | Facts: `deal_changes`, `activity`; dictionaries: `activity_types`, `stages`, `fields`, `users` (master data); comments added to the file and `docs/findings.md` |

| 2026-10-22 | Restructure `analyses/`: a separate file per raw table (all columns, pk, fk, nulls, outliers, descriptive analytics) and an overall file with all data quality findings; include the approach in the skills; run the findings on the charts | Seven files in `analyses/`; skills updated (PR #6); dashboard has new sections for keys, nulls and the 25 findings ([[eda_skills]]) |

| 2026-10-22 | Read the company information and role description for the descriptive analysis; describe the fields used with links to the Pipedrive documentation | Business context and field documentation links in each table file and in `docs/data_dictionary.md`; coded lost reasons decoded and checked (findings 26 to 28 of 28) |
| 2026-10-22 | Create the Lightdash dashboard: one table = one tab | Project "Enpal Pipedrive EDA", dashboard with Overview + 6 table tabs, 47 SQL charts, built via the API (`lightdash/` in the repo) |

| 2026-10-23 | Simplify the exploratory analysis (primary key via `count(*) over (partition by ...)`), keep the general business context in one md file, and use it to explore what the data relates to | Per-table files rewritten (one check per query, result as a comment); `docs/business_context.md` (company, sale, KPI-to-data map, table relations, expectations vs data); new `analyses/08_business_questions.sql` (B1 to B6) ([[eda_business_questions]]) |

| 2026-10-23 | Keep only the final queries; avoid nested subqueries and use CTEs; add this to the SQL skills | Non-final queries removed; all subqueries in 01 to 08 rewritten as CTEs (outputs diffed, identical); `eda-source-profiling` skill has a new SQL style section ([[eda_business_questions]]) |

| 2026-10-23 | Apply my SQL layout (one column per line, join condition on its own line) to all queries and the skills; check snake_case; verify whether Postgres is case sensitive | All 8 files reformatted, outputs identical; skill has layout, naming and case rules. Postgres: unquoted identifiers fold to lowercase (not case sensitive), quoted ones are exact; string values and JSON keys are case sensitive ([[eda_business_questions]]) |

| 2026-10-23 | Filter with where as early as possible; review the stage foreign key query and suggest rewrites with a CTE or a join `on ... and` condition | Filters moved into CTEs in 01, 07, 08 (outputs identical). Left-table filter in a left join's `on` is wrong: cast error, and 6,500 false orphans with a safe cast. Rule added to the skill ([[eda_business_questions]]) |

| 2026-10-23 | Equivalent of Postgres `jsonb_array_elements` in Snowflake and BigQuery | Snowflake: `lateral flatten(input => col)`, fields as `f.value:id::string`; BigQuery: `unnest(json_query_array(col))`, fields as `json_value(o, '$.id')` ([[eda_business_questions]]) |

| 2026-10-23 | Run explain on the queries with `cross join jsonb_array_elements`, review performance, suggest better rewrites; how would it work in BigQuery and Snowflake | All under 1 ms (07: 40 ms); the JSON unnest touches 1 row of `fields`; cost sits in the seq scans of `deal_changes` (7 in 07). Estimates off (function rows=100, never-analyzed dictionaries 110/140 rows). Rewrites: `jsonb_to_recordset`, aggregate before the join, unnest once in staging. BigQuery: re-parsing JSON strings costs slot time, use ARRAY<STRUCT>; Snowflake: VARIANT is stored columnar, FLATTEN once ([[postgres_at_scale]]) |

| 2026-10-23 | Rewrite the JSON queries, comment each CTE / filter with why, add separate array blocks to the skills, remember the style | 01, 05, 06, 07, 08 rewritten with `jsonb_to_recordset`, aggregate-first and one read of `deal_changes` in 07 (7 scans to 1); outputs identical; skill section "Arrays and JSON"; style saved to memory ([[postgres_at_scale]]) |

| 2026-10-23 | `extract(epoch ...)` in Postgres: equivalent in Snowflake and BigQuery | Snowflake: `date_part(epoch_second, ts)`, differences `datediff('second', a, b)`; BigQuery: `unix_seconds(ts)`, differences `timestamp_diff(b, a, second)`. `datediff('day', ...)` in Snowflake counts midnights crossed, so use seconds / 86400 for fractional days ([[postgres_at_scale]]) |

| 2026-10-23 | Move statistical cases (IQR on gaps) to a separate file and remind me; outliers for fact tables as rows per month / quarter / year, per dimension, and per dimension and month | `analyses/09_review_later.sql` (R1 IQR, R2 gap shape, R3 month spine, R4 open questions); section 5 of 01 and 02 rewritten; new finding: 157 After Close Calls due before the first Closing (2024-02-02); reminder in NOTES.md and memory; skill updated ([[eda_business_questions]]) |

| 2026-10-23 | Average number of changes per deal per month; why monthly granularity | 1.74 to 1.84 changes per active deal per month to 2024-10, falling to 1.0 by 2025-03; 4.4 active months per deal. Monthly because of the 15-month range and the monthly report; seasonality or performance questions are separate domain deep dives (01 section 5d) |

| 2026-10-23 | Interpret the full history of deal 399956 against Enpal's business and Pipedrive's change process | Two interleaved lifecycles told apart by clock time (06:45:44 and 18:27:27), overlapping in time: a duplicate lead merged into one deal; stage path skips Closing and Implementation; lost reason Customer Not Ready after Follow-up. Across the table 99.8% of changes share the creation's clock time (1,990 deals one clock time, the 5 two-lifecycle deals two): event times are creation + whole days, i.e. generated ([[02_data_findings]]) |

| 2026-10-23 | SQL for the deal 399956 history, for the 84% skipping, what 'backfilled' means, and supporting SQL for each question to Enpal; verify the merge assumption in the docs and the trial | All queries run. Docs: the merge tutorial keeps the `merge_with_id` deal, deletes the other, transfers activities/emails/notes, says nothing about history. All 5 two-lifecycle deals overlap (second created before the first was lost). 683 of 1,081 deals in stages 7-9 have no recorded Closing. Trial merge test needs her approval ([[pipedrive_crm_terms]]) |

| 2026-10-23 | Review 02_activity.sql primary key with the window-count SQL; duplicates need cleansing; process for `<table>_id` duplicates (assume DQ when few, prove it, ask for categorization) into the skills | 11 ids / 22 rows (0.48%); user, deal, due date differ in every pair; (activity_id, type) not unique; 11.6 chance collisions expected vs 11: data quality issue, not composite key. Process in the skill and memory; cleansing decision asked ([[nulls_and_keys]]) |

| 2026-10-23 | Decision on the repeated activity_ids | Treated as duplicates, marked as a data quality issue; cleansing can follow the process within the domain and needs a review by the business stakeholder responsible for the KPIs and the data entry. Recorded in NOTES.md, 02, 07, 09, findings.md ([[nulls_and_keys]]) |

| 2026-10-23 | Add the done x type distribution (count distinct activity_id) to the descriptive part; use such examples for distributions in the skills | 02 section 6a with distinct ids and rows side by side: every type ~50/50 done; sc_2 not done 563 ids vs 564 rows (id 283914 collision). Skill: new 'distribution across two dimensions' block ([[eda_skills]]) |

| 2026-10-23 | What is an activity in business terms? | A planned task of a sales rep in the CRM (a call, a meeting), with a type, an owner, a linked deal, a due date and a done flag; in Enpal's sale: consultation calls (Sales Call 1 / 2), follow-ups, after-close calls. Planned (due date) is not held (done) ([[pipedrive_crm_terms]]) |

## Add new questions below
