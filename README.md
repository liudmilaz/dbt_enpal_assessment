# Enpal take-home: Pipedrive sales funnel in dbt on Snowflake

The assignment ships a local Postgres in Docker. Enpal agreed that this solution may run on my own **Snowflake trial account** instead, so the setup section below describes Snowflake and the repository contains no Postgres. Everything the task asks for is unchanged: the same six Pipedrive tables, the same layers, the same reporting model. The role also asks for Snowflake semantic views, and keeping one platform makes the project simpler to read. AI tools (Claude Code) were used as support, as agreed.

## Result

`MARTS.rep_sales_funnel_monthly(month, kpi_name, funnel_step, deals_count)`: one row per month and funnel step, 2024-01 to 2025-02, zero-filled (154 rows). Contract enforced. Built for self-service reporting by month; quarters, weeks or years belong to a semantic layer or BI tool on the event grain, because the call steps 2.1 and 3.1 count distinct deal ids per month and do not add up across months.

| Step | Counted as | Total deals in the window |
|---|---|---|
| 1 to 9 (stages) | distinct deals whose **first entry** into the stage falls in the month; a skipped stage counts as reached (`is_inferred`) and is dated at the earliest entry of a higher stage | 1,618 / 1,614 / 1,582 / 1,512 / 1,367 / 1,150 / 877 / 586 / 274 |
| 2.1 Sales Call 1, 3.1 Sales Call 2 | distinct deal ids with a **done** call of that type due in the month | 566 / 558 |

## Data flow

```
ENPAL_RAW.PIPEDRIVE        6 CSVs, loaded once (scripts/snowflake_load.sql); dbt can only read it
  -> ENPAL_TEST.SRC        zero-copy clones (dbt run-operation refresh_src) - default target `test`
  -> STAGING               stg_pipedrive__*  one view per raw table: rename, cast, deduplicate
  -> INTERMEDIATE          int_pipedrive__deal_stage_entries(_backfilled), __funnel_steps, __sales_calls
  -> MARTS                 dim_funnel_step, rep_sales_funnel_monthly
ENPAL_ANALYTICS_PROD       same layers, target `prod`, built from main only, reads ENPAL_RAW directly
```

## Setup (Snowflake)

1. **Account objects** (once, as ACCOUNTADMIN): `scripts/snowflake_admin.sql` creates the warehouse `ENPAL_WH` (X-Small, suspends after 60 s), the databases `ENPAL_RAW`, `ENPAL_TEST`, `ENPAL_ANALYTICS_PROD`, the role `ENPAL_DBT_ROLE` (read-only on raw) and the service user `ENPAL_DBT_USER` (key pair, no secondary roles). The header of the script shows the `snow sql` call.
2. **Raw data** (as SYSADMIN): `snow sql -c <admin connection> -f scripts/snowflake_load.sql` loads `raw_data/*.csv` into `ENPAL_RAW.PIPEDRIVE`. It replaces the tables, so a rerun never appends twice.
3. **Credentials**: copy `scripts/snowflake_env.example` to `~/.snowflake/enpal.env`, fill in account and key path, `source` it. `profiles.yml` reads them from the environment; nothing secret is in the repo.
4. **dbt** (venv outside the repo): `pip install -r requirements.txt`, then
   ```bash
   export DBT_PROFILES_DIR=.
   dbt deps
   dbt run-operation refresh_src   # fresh zero-copy clones in ENPAL_TEST.SRC
   dbt build                       # target test: models and all tests
   ```
   Production: `dbt build --target prod` (from `main` only).
5. **Data quality report and dashboard** (optional): `pip install -r requirements-elementary.txt` in a separate venv, and a Snowflake CLI connection to the account (`snow connection add`, key pair as in `profiles.yml`; name `enpal`, or set `SNOW_CONNECTION`). Then `bash scripts/dq_report.sh` runs every test and serves on http://localhost:8081:
   - the Elementary report: `elementary_report_test.html`;
   - the data quality dashboard: `dq_dashboard_test.html`, one tab per raw table with a chart of the affected raw rows per issue; clicking a bar shows the rows of that issue with what was found, how the pipeline cleanses or transforms it and the query behind it.
   After a test run alone, `python3 scripts/dq_dashboard.py --target test` rebuilds the dashboard from the latest Elementary results.

## Decisions and assumptions

| Topic | Choice | Why / effect |
|---|---|---|
| Skipped stages (84% of deals) | counted as reached, flagged `is_inferred`; for recorded entries only use `int_pipedrive__deal_stage_entries` | a deal in Negotiation has passed Qualified Lead; recorded-only would roughly halve the middle steps |
| Step 1 date | first entry into stage 1, not the creation time | same rule as every other step; creation is a median 35 days earlier |
| Calls 2.1 / 3.1 | done calls only; `is_due_before_export_end` in `int_pipedrive__sales_calls` flags the calls due before the export ended (the last change of the deal history) | a held call is the KPI; only about 50% of every type is marked done, although every call was due before the export ended. Counting those calls too would about double steps 2.1 and 3.1 (to confirm with Enpal) |
| Calls vs deals | calls counted per month by their own `deal_id` | only 8 of 4,579 activities link to a deal in the history, so they cannot be attached to the funnel deals |
| Two lifecycles in one deal (5 deals) | counted once per step, by the first entry | |
| Repeated `activity_id` (11 ids) | `activity_id` is the key; the latest `due_to` per id is kept (4,579 to 4,568) | |
| Report window | from the first to the last month with any funnel step in the data (2024-01 to 2025-02 in this export) | no hardcoded dates; calls and new deals stop on 2024-09-13 (the exports end on different dates), so steps 2.1 and 3.1 are 0 after |
| Names | `kpi_name` = the task's step name, `funnel_step` = step number as text (`'2.1'`) | the CRM spells one stage differently |

The open questions for the business (KPI owner, CRM admin) and the evidence behind every finding are in `vault/` (documentation PR) and in `analyses/` (one exploratory file per raw table, with results under each query; added after the owner's review).

## Tests

Generic tests, and custom tests that show the data quality issues found in the exploratory analysis.

- **Generic, every layer**: unique + not_null on primary and alternate keys, not_null + relationships on foreign keys (on the raw layer also the keys inside `deal_changes.new_value`), accepted values of the funnel steps.
- **Known data quality issues** (`tests/data_quality/`, tag `dq_known_issue`): one singular test per issue, named by its id (`a1_repeated_activity_id`, `d1_deals_with_skipped_stages`, ...), with Found / Handled in its meta. Each returns the affected raw rows at the table's own grain, and fails (severity error).

### Data quality issues affecting the report

The issues found in the exploratory analysis that change a count or a name of `rep_sales_funnel_monthly`, with how the pipeline cleanses or transforms them. All issues, also those that change nothing in the report, with the rows and distinct deals or activities affected, the business case and the cleansing, are in [data_quality_issues.md](data_quality_issues.md).

| Issue | Effect on the report | Cleansing / transformation | Test |
|---|---|---|---|
| D1 Skipped stages | Deals jump over stages, so a stage the customer passed is missing. | A skipped stage counts as reached (`is_inferred`), dated by the deal's earliest entry into a higher stage (`int_pipedrive__deal_stage_entries_backfilled`). | `d1_deals_with_skipped_stages` |
| D2 After-sale without a recorded Closing | Deals reach Implementation or later without Closing. | Closing counts as reached (inferred) through the same backfill. | `d2_after_sale_without_closing` |
| D3 One deal id, two lifecycles | A merged deal carries two histories. | Each deal counts once per stage, by its first entry (`int_pipedrive__deal_stage_entries`). | `d3_two_creations_per_deal` |
| DUP-6 Duplicate Entry deals | Duplicates would be counted as real deals. | Dedup deals in staging: every deal with a Duplicate Entry lost reason is left out (`stg_pipedrive__deal_changes`). | `dup6_duplicate_entry_deals_past_closing` |
| A1 One activity id, two activities | A call could be counted twice. | One row per activity id, the latest due date (`stg_pipedrive__activity`). | `a1_repeated_activity_id` |
| A2 Activities not linked to the deal history | Calls cannot be tied to the funnel deals. | Steps 2.1 and 3.1 count the calls' own deal ids per month, not joined to the funnel deals (`int_pipedrive__sales_calls`). | `a2_activity_deal_not_in_deal_changes` |
| A4 Past activities never marked done | Steps 2.1 and 3.1 depend on the done flag. | Done calls only; the calls due before the export ended are flagged (`is_due_before_export_end`) to count them if the business confirms. | `a4_past_activities_not_done` |
| X1 Exports end on different dates | Calls end months before the deal history. | The report runs to the last month with data; steps 2.1 and 3.1 are 0 after the activity export ends. | `x1_export_end_dates_apart` |
| S1 Stage spelled two ways | The step names would differ from the task. | Step names from the Stage field labels (`int_pipedrive__funnel_steps`). | `s1_stage_name_differs_from_field_label` |

`dbt build` uses the default selector `pipeline` (`selectors.yml`), which leaves the known issues out, so the pipeline is not blocked by defects of the export it already handles. `bash scripts/dq_report.sh` runs every test and serves the Elementary report: the dashboard gives the overview, with the known issues as failures; each issue's test result page lists its affected raw rows (duplicates, unmatched keys, skipped stages, ...).

**Still to implement**, once the export is loaded on a schedule and agreed with the business:
- source freshness (`loaded_at_field`, `warn_after` / `error_after`) per raw table;
- anomaly detection (Elementary volume, freshness, dimension and schema monitors), once there is load history to train on;
- custom tests per business process, agreed with sales ops and the CRM admin (for example call outcomes, lead routing, stage rules).

## Further development: the funnel per user

The report has no user dimension. The `users` table is not used, but not because users are missing: every deal owner and activity assignee exists in it.

**Why it is not used yet**
1. The task's report has no user dimension.
2. Owners are spread thin (U2): a month × step × owner table would be almost all zeros and ones.
3. The table is current state only, with no team, role or history. Shared emails (U1) are not a problem, because the joins use the id.

**What the data supports**
- Ownership history works for attribution: owners are set before stage 1 in almost every case, so every stage entry has an owner at the moment of entry (as-of join on the `user_id` changes).
- Calls cannot use the deal owner: on the 8 activities whose deal is in the history, the assignee is never one of that deal's owners (A2). Calls per user use the activity's assignee.

**Proposed refactor** (not implemented). `rep_sales_funnel_monthly` and its contract stay as they are; added:
1. `int_pipedrive__deal_owner_history`: one row per deal and owner period (`valid_from` = the change time, `valid_to` = the next change), built from the `user_id` changes; tested for overlapping periods per deal.
2. `dim_user`: from `stg_pipedrive__users`, with flags for owner, assignee and shared email; team and role once Enpal supplies a mapping (S15).
3. Event-grain facts, with relationship tests to `dim_user`:
   - `fct_deal_stage_entries`: deal × stage, with `entered_at`, `is_inferred` and `owner_user_id` as of `entered_at`;
   - `fct_sales_calls`: with `assigned_user_id` and `is_done`.
4. Slicing per user in a semantic layer or BI tool on these facts, not as another monthly table, because distinct deal counts do not add up across owners or months.

To confirm with Enpal: the attribution rule, i.e. the owner at the time of stage entry (proposed), the current owner, or the first owner.

## Repository

| Path | Content |
|---|---|
| `models/sources/pipedrive/` | sources with descriptions, keys in `meta`, raw-layer key tests |
| `models/staging`, `models/intermediate`, `models/marts` | the models |
| `macros/` | `refresh_src` (test clones), `generate_schema_name` (one schema per layer) |
| `tests/data_quality/` | custom tests: the known data quality issues, and the lost-reason key of the raw layer |
| `data_quality_issues.md` | every data quality issue found in the analysis: rows affected, business case, cleansing, test, link to the dashboards |
| `selectors.yml` | `pipeline` (default, without the known issues), `dq_report` (every test) |
| `analyses/` | exploratory analysis per raw table, SQL with results (kept local until reviewed; added before the final submission) |
| `scripts/` | Snowflake admin and load scripts, data quality report (`dq_report.sh`) and dashboard (`dq_dashboard.py` with its page template) |

---

## The task (as given)

1. Remove the test model once you make sure it works
2. Dive deep into the Pipedrive CRM source data to gain a thorough understanding of all its details. (You may also research the Pipedrive CRM tool terms).
3. Define DBT sources and build the necessary layers organizing the data flow for optimal relevance and maintainability.
4. Build a reporting model (rep_sales_funnel_monthly) with monthly intervals, incorporating the following funnel steps (KPIs):  
  &nbsp;&nbsp;&nbsp;Step 1: Lead Generation  
  &nbsp;&nbsp;&nbsp;Step 2: Qualified Lead  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 2.1: Sales Call 1  
  &nbsp;&nbsp;&nbsp;Step 3: Needs Assessment  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 3.1: Sales Call 2  
  &nbsp;&nbsp;&nbsp;Step 4: Proposal/Quote Preparation  
  &nbsp;&nbsp;&nbsp;Step 5: Negotiation  
  &nbsp;&nbsp;&nbsp;Step 6: Closing  
  &nbsp;&nbsp;&nbsp;Step 7: Implementation/Onboarding  
  &nbsp;&nbsp;&nbsp;Step 8: Follow-up/Customer Success  
  &nbsp;&nbsp;&nbsp;Step 9: Renewal/Expansion
5. Column names of the reporting model: `month`, `kpi_name`, `funnel_step`, `deals_count`
6. “Git commit” all the changes and create a PR to your forked repo (not the original one). Send your repo link to us.

The setup steps of the original task (Docker, local Postgres with admin/admin, `dbt-postgres`) are replaced by the Snowflake setup above, with Enpal's agreement. The project steps are unchanged.
