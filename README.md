# Enpal take-home: Pipedrive sales funnel in dbt on Snowflake

The assignment ships a local Postgres in Docker. Enpal agreed that this solution may run on my own **Snowflake trial account** instead, so the setup section below describes Snowflake and the repository contains no Postgres. Everything the task asks for is unchanged: the same six Pipedrive tables, the same layers, the same reporting model. The role also asks for Snowflake semantic views, and keeping one platform makes the project simpler to read. AI tools (Claude Code) were used as support, as agreed.

## Result

`MARTS.rep_sales_funnel_monthly(month, kpi_name, funnel_step, sort_order, deals_count)`: one row per month and funnel step, 2024-01 to 2024-09, zero-filled (99 rows). Contract enforced. `sort_order` orders the steps for charts (1, 2, 2.1, 3, 3.1, 4 to 9).

**The month is the deal's creation month (cohort).** The task asks to research the Pipedrive CRM terms (step 2), so the report follows Pipedrive's [deal conversion report](https://support.pipedrive.com/en/article/insights-reports-deal-conversion), whose default filter is the deal creation date: every step a deal reaches counts in the month the deal was created, whenever the step happened. Each row is therefore the conversion of one month's deals, and no stage step exceeds the one before. The deals of recent months are still in progress, so their later steps are lower and would grow with a newer export. Counting each step in the month it happened (event month) would instead show the activity of the month, where a later step can exceed Lead Generation because it includes deals created earlier.

| Step | Counted as | Total deals in the window |
|---|---|---|
| 1 to 9 (stages) | distinct deals **created in the month** that reached the stage at any time; a skipped stage counts as reached (`is_inferred`) | 1,618 / 1,614 / 1,582 / 1,512 / 1,367 / 1,150 / 877 / 586 / 274 |
| 2.1 Sales Call 1, 3.1 Sales Call 2 | distinct deal ids with a **done** call of that type **due in the month**: these deal ids are not in the deal history (A2) and have no creation date, so they cannot be counted by cohort | 566 / 558 |

## Data flow

```
ENPAL_RAW.PIPEDRIVE        6 CSVs, loaded once (scripts/snowflake_load.sql); dbt can only read it
  -> ENPAL_TEST.SRC        zero-copy clones (dbt run-operation refresh_src) - default target `test`
  -> STAGING               stg_pipedrive__*  one view per raw table: rename, cast, deduplicate
  -> INTERMEDIATE          int_pipedrive__deal_cohorts, __deal_stage_entries(_backfilled), __funnel_steps, __sales_calls
  -> MARTS                 dim_funnel_step, rep_sales_funnel_monthly
ENPAL_ANALYTICS_PROD       same layers, target `prod`, built from main only, reads ENPAL_RAW directly
```

## Setup (Snowflake)

1. **Account objects** (once, as ACCOUNTADMIN): `scripts/snowflake_admin.sql` creates the warehouse `ENPAL_WH` (X-Small, suspends after 60 s), the databases `ENPAL_RAW`, `ENPAL_TEST`, `ENPAL_ANALYTICS_PROD`, the role `ENPAL_DBT_ROLE` (read-only on raw) and the service user `ENPAL_DBT_USER` (key pair, no secondary roles). The header of the script shows the `snow sql` call.
2. **Raw data** (as SYSADMIN): `snow sql -c <admin connection> -f scripts/snowflake_load.sql` loads `raw_data/*.csv` into `ENPAL_RAW.PIPEDRIVE`. It replaces the tables, so a rerun never appends twice.
3. **Credentials**: copy `scripts/snowflake_env.example` to a file outside the repository, fill in account and key path, `source` it. `profiles.yml` reads them from the environment; nothing secret is in the repo.
4. **dbt** (venv outside the repo): `pip install -r requirements.txt`, then
   ```bash
   export DBT_PROFILES_DIR=.
   dbt deps
   dbt run-operation refresh_src   # fresh zero-copy clones in ENPAL_TEST.SRC
   dbt build                       # target test: models and all tests
   ```
   Production: `dbt build --target prod` (from `main` only).
5. **Data quality report and dashboard** (optional): `pip install -r requirements-elementary.txt` in a separate venv, and a Snowflake CLI connection to the account (`snow connection add`, key pair as in `profiles.yml`; name `enpal`, or set `SNOW_CONNECTION`). With the credentials exported (or `ENPAL_ENV_FILE` set to their file), the project's venv active and the Elementary CLI on the `PATH` (or `EDR_BIN` set to it), `bash scripts/dq_report.sh` runs every test and serves on http://localhost:8081:
   - the Elementary report: `elementary_report_test.html`;
   - the data quality dashboard: `dq_dashboard_test.html`, one tab per raw table with a chart of the affected raw rows per issue; clicking a bar shows the rows of that issue with what was found, how the pipeline cleanses or transforms it and the query behind it.
   After a test run alone, `python3 scripts/dq_dashboard.py --target test` rebuilds the dashboard from the latest Elementary results.

## Decisions and assumptions

| Topic | Choice | Why / effect |
|---|---|---|
| Skipped stages (84% of deals) | counted as reached, flagged `is_inferred`; for recorded entries only use `int_pipedrive__deal_stage_entries` | a deal in Negotiation has passed Qualified Lead; recorded-only would roughly halve the middle steps |
| Month of the report | the deal's creation month (cohort) for every stage step; the due month for the call steps | follows the Pipedrive documentation, as the task suggests: the deal conversion report filters on the deal creation date. The call steps have no creation date (A2). To confirm with the KPI owner |
| Win / loss conversion | not built | Pipedrive's second conversion mode needs the deal status (won, lost); the export has no status, won time or lost time, and every deal carries a lost reason (D4), also the deals that reached Renewal/Expansion |
| Calls 2.1 / 3.1 | done calls only; `is_due_before_export_end` in `int_pipedrive__sales_calls` flags the calls due before the export ended (the last change of the deal history) | a held call is the KPI; only about 50% of every type is marked done, although every call was due before the export ended. Counting those calls too would about double steps 2.1 and 3.1 (to confirm with Enpal) |
| Calls vs deals | calls counted per month by their own `deal_id` | only 8 of 4,579 activities link to a deal in the history, so they cannot be attached to the funnel deals |
| Two lifecycles in one deal (5 deals) | counted once per step, in the month of the first creation | |
| Repeated `activity_id` (11 ids) | `activity_id` is the key; the latest `due_to` per id is kept (4,579 to 4,568) | |
| Report window | from the first to the last month with any funnel step in the data (2024-01 to 2024-09 in this export) | no hardcoded dates; new deals and calls stop on 2024-09-13 (X1), so 2024-09 is a part month |
| Names | `kpi_name` = the task's step name, `funnel_step` = step number as text (`'2.1'`) | the CRM spells one stage differently |

The open questions for the business (KPI owner, CRM admin) and the evidence behind every finding are in `vault/` (documentation PR) and in `analyses/` (one exploratory file per raw table, with results under each query; added after the owner's review).

## Tests

Generic tests, and custom tests that show the data quality issues found in the exploratory analysis.

- **Generic, every layer**: unique + not_null on primary and alternate keys, not_null + relationships on foreign keys (on the raw layer also the keys inside `deal_changes.new_value`), accepted values of the funnel steps.
- **Known data quality issues** (`tests/data_quality/`, tag `dq_known_issue`): one singular test per issue, named by its id (`a1_repeated_activity_id`, `d1_deals_with_skipped_stages`, ...), with Found / Handled in its meta. Each returns the affected raw rows at the table's own grain, and fails (severity error).

Every issue found in the exploratory analysis, with its rows affected, business case, cleansing and test, is in [Data quality issues](#data-quality-issues) below.

`dbt build` uses the default selector `pipeline` (`selectors.yml`), which leaves the known issues out, so the pipeline is not blocked by defects of the export it already handles. `bash scripts/dq_report.sh` runs every test and serves the Elementary report: the dashboard gives the overview, with the known issues as failures; each issue's test result page lists its affected raw rows (duplicates, unmatched keys, skipped stages, ...).

**Still to implement**, once the export is loaded on a schedule and agreed with the business:
- source freshness (`loaded_at_field`, `warn_after` / `error_after`) per raw table;
- anomaly detection (Elementary volume, freshness, dimension and schema monitors), once there is load history to train on;
- custom tests per business process, agreed with sales ops and the CRM admin (for example call outcomes, lead routing, stage rules).

## Data quality issues

Every data quality issue found in the exploratory analysis, one section per raw table as in the dashboard [Pipedrive exploratory analysis](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e), which also shows the affected raw rows and the query of each issue. Each issue follows the same structure: the question for the stakeholders, an explanation with the assumed origin (data entry, a feature of Pipedrive, or the export), the impact on `rep_sales_funnel_monthly`, the proposed handling (implemented as the default until it is confirmed), and the dbt test that lists the affected raw rows.

**Note:** the provided data set is most probably synthetic, but it is treated as a real case. Some of its behaviour may be inconsistent and not fully reflect reality: inconsistencies without a big impact on the final report are not followed up, only recorded. The origins below are assumptions, checked against the Pipedrive documentation where it covers the point; where it does not, the text says so.

The issues that change the report come first in each table. Found counts are rows of this export at the issue's grain and would change with a new load.

| Issue | Table | Affects the report | Found | dbt test |
|---|---|---|---|---|
| [D1](#d1) Skipped stages | `deal_changes` | yes | 2,502 stage moves (1,684 deals) | [`d1_deals_with_skipped_stages`](tests/data_quality/d1_deals_with_skipped_stages.sql) |
| [D2](#d2) After-sale without a recorded Closing | `deal_changes` | yes | 3,207 stage moves (683 deals) | [`d2_after_sale_without_closing`](tests/data_quality/d2_after_sale_without_closing.sql) |
| [D3](#d3) One deal_id, two lifecycles | `deal_changes` | yes | 10 lifecycles (5 deals) | [`d3_two_creations_per_deal`](tests/data_quality/d3_two_creations_per_deal.sql) |
| [DUP-6](#dup-6) Duplicate Entry deals that reached Closing | `deal_changes` | yes | 274 deals (377 deals carry a Duplicate Entry lost reason in total) | [`dup6_duplicate_entry_deals_past_closing`](tests/data_quality/dup6_duplicate_entry_deals_past_closing.sql) |
| [D4](#d4) Lost reason on deals that reached Closing or later | `deal_changes` | no | 1,429 lost reasons (1,424 deals); every deal carries one | none (documented only) |
| [D5](#d5) Changes at the creation's clock time | `deal_changes` | no | 13,373 of 13,406 changes after creation (1,995 deals) | none (documented only) |
| [A1](#a1) One activity_id, two activities | `activity` | yes | 22 activities (11 activity ids) | [`a1_repeated_activity_id`](tests/data_quality/a1_repeated_activity_id.sql) |
| [A2](#a2) Activities not linked to the deal history | `activity` | yes | 4,571 activities (4,564 deal ids); 8 of 4,579 activities match a funnel deal | [`a2_activity_deal_not_in_deal_changes`](tests/data_quality/a2_activity_deal_not_in_deal_changes.sql) |
| [A3](#a3) After Close Calls before any Closing | `activity` | no | 157 activities (157 deal ids) | none (documented only) |
| [A4](#a4) Past activities never marked done | `activity` | yes | 2,289 activities (2,285 activity ids), about half of every type | [`a4_past_activities_not_done`](tests/data_quality/a4_past_activities_not_done.sql) |
| [X1](#x1) Exports end on different dates | `activity` | yes | 5 table and event types (2 tables) | [`x1_export_end_dates_apart`](tests/data_quality/x1_export_end_dates_apart.sql) |
| [T1](#t1) Inactive activity type in use | `activity_types` | no | 1,133 activities of 1 activity type (Follow Up Call) | generic `accepted_values` on `active` (format only) |
| [U1](#u1) Users sharing an email | `users` | no | 8 users (4 emails) | [`u1_shared_email__users`](tests/data_quality/u1_shared_email__users.sql) |
| [U2](#u2) Several owners per deal | `users` | no | 501 deals with more than one owner; about 1,350 owners with a few deals each | none (documented only) |
| [S1](#s1) Stage spelled two ways | `stages` | yes | 1 stage: 'Qualified lead' in stages, 'Qualified Lead' in the Stage field | [`s1_stage_name_differs_from_field_label`](tests/data_quality/s1_stage_name_differs_from_field_label.sql) |

### deal_changes

#### D1
**Skipped stages** · affects the report: yes · found: 2,502 stage moves (1,684 deals)

- **Question** (sales ops, KPI owner): Reps often move a deal several stages at once, for example from Lead Generation straight to Needs Assessment. Did the customer pass the skipped stages, so that the deal could count under each of them?
- **Explanation (assumption)**: Most deals skip at least one stage. The likely origin is data entry: Pipedrive lets a user drag a deal to any stage in the pipeline view, so a rep who updates the pipeline after the fact can move a deal several stages at once. A spreadsheet import seems an unlikely origin: an import places a deal straight into one stage without earlier entries, while here every deal starts at stage 1 and the skips happen later in its history.
- **Impact**: The middle steps of the funnel, Closing included, are much higher when skipped stages count as reached: the backfill adds 4,152 stage entries.
- **Proposed handling**: Proposed and implemented as the default: a skipped stage counts as reached (`is_inferred`), dated by the deal's earliest entry into a higher stage. Pipedrive's pipeline conversion report treats a won deal as having completed every stage, which points the same way. The recorded-only counts stay available in `int_pipedrive__deal_stage_entries`.
- **dbt test**: [`d1_deals_with_skipped_stages`](tests/data_quality/d1_deals_with_skipped_stages.sql)

#### D2
**After-sale without a recorded Closing** · affects the report: yes · found: 3,207 stage moves (683 deals)

- **Question** (KPI owner, sales ops, after-sales lead): Many deals reach Implementation or later without ever being moved to Closing. Was the contract signed for all of them? Does after-sales run in a separate pipeline that the export does not include?
- **Explanation (assumption)**: Possibly the same data entry behaviour as D1, for Closing: an installation suggests a signed contract. Possibly a tool feature: Pipedrive supports several pipelines and the export has no pipeline column, so a move into an after-sales pipeline could look like a jump over Closing.
- **Impact**: A large share of the deals counted under Closing would be inferred, not recorded.
- **Proposed handling**: Proposed and implemented as the default: Closing counts as reached (inferred) when a deal reached an after-sale stage; `is_inferred` keeps recorded and inferred closings apart.
- **dbt test**: [`d2_after_sale_without_closing`](tests/data_quality/d2_after_sale_without_closing.sql)

#### D3
**One deal_id, two lifecycles** · affects the report: yes · found: 10 lifecycles (5 deals)

- **Question** (CRM admin, data team): Five deal ids carry two full lifecycles, each with its own creation, owners, stages and lost reason. Were two deals merged, or did the export give two deals the same id?
- **Explanation (assumption)**: Two origins seem possible. A tool feature: an admin can merge two deals in Pipedrive and choose which values to keep; the support article does not say whether the history of the removed deal stays, so a merge test in the trial account could tell. The export: Pipedrive ids are assigned by the system and are not reused, while the ids here look random and collide about as often as chance predicts (A1 shows the same for activities), which points to the export rather than to a merge.
- **Impact**: Small: 5 deals. Counted twice, they would inflate the steps they reached in both lifecycles.
- **Proposed handling**: Cleansed: each of the 5 deals counts once per stage, by its first entry (`int_pipedrive__deal_stage_entries`), in the month of its first creation (`int_pipedrive__deal_cohorts`). Splitting them into two deals each was considered and not chosen.
- **dbt test**: [`d3_two_creations_per_deal`](tests/data_quality/d3_two_creations_per_deal.sql)

#### DUP-6
**Duplicate Entry deals that reached Closing** · affects the report: yes · found: 274 deals (377 deals carry a Duplicate Entry lost reason in total)

- **Question** (sales ops, KPI owner): Deals with the lost reason Duplicate Entry still reached Closing or later. Are they duplicates that should leave the funnel, or is the reason used for something else, for example a re-signed contract?
- **Explanation (assumption)**: Duplicate Entry is likely one of the company's predefined lost reasons (Pipedrive lets an admin replace free-form reasons with a predefined list). A real duplicate would be expected to be closed or merged early; that 274 of them reached Closing suggests the reason was chosen late, or for other cases.
- **Impact**: Leaving them out lowers every step of the funnel.
- **Proposed handling**: Proposed and implemented as the default: every deal with a Duplicate Entry lost reason is left out in staging (`stg_pipedrive__deal_changes`), also when it is the first of two lifecycles (D3). If they turn out to be real deals, it would be a one-line change in staging.
- **dbt test**: [`dup6_duplicate_entry_deals_past_closing`](tests/data_quality/dup6_duplicate_entry_deals_past_closing.sql)

#### D4
**Lost reason on deals that reached Closing or later** · affects the report: no · found: 1,429 lost reasons (1,424 deals); every deal carries one

- **Question** (KPI owner, CRM admin): Every deal carries a lost reason, also the deals that reached Renewal/Expansion. What does a lost reason mean on a closed deal, and how could won and lost deals be told apart?
- **Explanation (assumption)**: According to Pipedrive's documentation, a lost reason is entered when a deal is marked as lost, and the deal's status then changes to lost. A lost reason on every deal does not fit this behaviour, so it more likely comes from how the export was prepared than from data entry. The export has no status, won time or lost time, so a win/loss analysis (Pipedrive's second conversion mode) does not seem possible with this data.
- **Impact**: No count of the report changes. Win rates cannot be derived.
- **Proposed handling**: Proposed: keep the lost reason as a closure label, not as an outcome, and count Closing by the stage only; split Closing by outcome once a status is available.
- **dbt test**: none (documented only)

#### D5
**Changes at the creation's clock time** · affects the report: no · found: 13,373 of 13,406 changes after creation (1,995 deals)

- **Question** (data team): Almost every change of a deal is stored at the time of day of the deal's creation. How were the timestamps of the export produced?
- **Explanation (assumption)**: Pipedrive logs each change of a deal with its own timestamp (the deal flow), so the pattern does not seem to come from data entry. A spreadsheet import also seems an unlikely origin, because an import creates the current state of a deal, not its history. It more likely comes from how the export was prepared. A check in the trial account could help: which time Pipedrive stores for a deal imported with a creation date only.
- **Impact**: None at the monthly grain. Durations between stages and anything below a month, for example by week, could be distorted.
- **Proposed handling**: Proposed: use dates only, never the time of day or durations between stages.
- **dbt test**: none (documented only)

### activity

#### A1
**One activity_id, two activities** · affects the report: yes · found: 22 activities (11 activity ids)

- **Question** (data team, CRM admin): Eleven activity ids appear twice, with a different user, deal and due date in every pair. Are they two versions of one activity or two different activities?
- **Explanation (assumption)**: In Pipedrive an activity id is assigned by the system and is unique, and a repeated import would create new ids rather than repeat one, so data entry or an import seem unlikely origins. The number of repeats matches what chance predicts for random ids, which points to the export.
- **Impact**: Steps 2.1 and 3.1 change by at most 1 in a month.
- **Proposed handling**: Proposed and implemented as the default (agreed 2026-10-23): `activity_id` is the primary key; one row per id is kept, the one with the latest due date (`stg_pipedrive__activity`).
- **dbt test**: [`a1_repeated_activity_id`](tests/data_quality/a1_repeated_activity_id.sql)

#### A2
**Activities not linked to the deal history** · affects the report: yes · found: 4,571 activities (4,564 deal ids); 8 of 4,579 activities match a funnel deal

- **Question** (data team): Only 8 of 4,579 activities carry a deal id that exists in the deal history. Do the activities and the deals come from the same set of deals?
- **Explanation (assumption)**: In Pipedrive an activity linked to a deal carries that deal's id, and an imported activity that cannot be matched to a deal stays without a deal rather than getting another id. The deal ids here match about as often as chance predicts, which suggests that the two tables were exported, or their ids remapped, separately.
- **Impact**: The call steps cannot be attributed to the funnel deals, nor to a deal's creation month (cohort).
- **Proposed handling**: Proposed and implemented as the default: steps 2.1 and 3.1 count the calls' own deal ids by the month the call was due, not joined to the funnel deals (`int_pipedrive__sales_calls`).
- **dbt test**: [`a2_activity_deal_not_in_deal_changes`](tests/data_quality/a2_activity_deal_not_in_deal_changes.sql)

#### A4
**Past activities never marked done** · affects the report: yes · found: 2,289 activities (2,285 activity ids), about half of every type

- **Question** (KPI owner, sales ops): About half of every activity type is not marked done, although all of them were due before the export ended. Is a call that was not marked done a held call for the KPI?
- **Explanation (assumption)**: Two origins seem possible. Data entry: reps hold the call and do not mark it done. Import or export: the done status is a field the Pipedrive import can map, and a flag that is almost exactly 50% for every type suggests a value set in bulk rather than rep behaviour.
- **Impact**: Counting the calls due before the export ended too would roughly double the call steps: Sales Call 1 from 566 to 1,142 deal ids, Sales Call 2 from 558 to 1,120.
- **Proposed handling**: Proposed and implemented as the default: done calls only; the calls due before the export ended are flagged (`is_due_before_export_end` in `int_pipedrive__sales_calls`), so counting them would be a one-line change.
- **dbt test**: [`a4_past_activities_not_done`](tests/data_quality/a4_past_activities_not_done.sql)

#### X1
**Exports end on different dates** · affects the report: yes · found: 5 table and event types (2 tables)

- **Question** (data team): Deal creations and activities end on 2024-09-13, owner changes on 2024-11-02, stage moves on 2025-02-24 and lost reasons on 2025-03-11. Were the tables exported at different times?
- **Explanation (assumption)**: Pipedrive exports deals, activities and users as separate files, so tables taken at different times seem a likely origin.
- **Impact**: With the report by creation month, the window ends in 2024-09, the last month with new deals. Stage moves after it count in the earlier cohorts, and 2024-09 is a part month whose deals have had the least time to progress.
- **Proposed handling**: Proposed and implemented as the default: the report runs from the first to the last month with data, with no hardcoded dates.
- **dbt test**: [`x1_export_end_dates_apart`](tests/data_quality/x1_export_end_dates_apart.sql)

#### A3
**After Close Calls before any Closing** · affects the report: no · found: 157 activities (157 deal ids)

- **Question**: No separate question: it follows from A2.
- **Explanation (assumption)**: An After Close Call is expected after a signed contract. These calls are due before the first Closing of any deal, which suggests that they belong to deals that are not in this export (A2).
- **Impact**: None: After Close Call is not a funnel step.
- **Proposed handling**: Proposed: no change.
- **dbt test**: none (documented only)

### activity_types

#### T1
**Inactive activity type in use** · affects the report: no · found: 1,133 activities of 1 activity type (Follow Up Call)

- **Question** (CRM admin): Follow Up Call is inactive but used from the first to the last day of the export. When was it deactivated?
- **Explanation (assumption)**: This looks like a tool feature: a deactivated activity type is hidden for new activities and keeps its past ones, and its key string cannot change.
- **Impact**: None: Follow Up Call is not a funnel step.
- **Proposed handling**: Proposed: store `active` as true or false and keep the activities.
- **dbt test**: generic `accepted_values` on `active` (format only)

### users

#### U1
**Users sharing an email** · affects the report: no · found: 8 users (4 emails)

- **Question** (CRM admin): Four emails are each used by two users with different names. Are these different people?
- **Explanation (assumption)**: A Pipedrive login email is unique within a company account, so shared emails more likely come from the export (edited or anonymised user data) than from data entry.
- **Impact**: None: the report does not use users.
- **Proposed handling**: Proposed: join users on id, never on email.
- **dbt test**: [`u1_shared_email__users`](tests/data_quality/u1_shared_email__users.sql)

#### U2
**Several owners per deal** · affects the report: no · found: 501 deals with more than one owner; about 1,350 owners with a few deals each

- **Question** (sales ops): Deals change owner during the sale, and the owners are spread thin over many users. Who should get the credit for a step, if a funnel per rep is needed?
- **Explanation (assumption)**: Pipedrive lets the owner of a deal change, by hand or by an automation, so several owners per deal can come from the process. That so many users own only a few deals each is not typical of a sales team and may come from the export.
- **Impact**: None on the report; a funnel per rep would need an attribution rule.
- **Proposed handling**: Proposed: no per-rep KPIs from this export; a funnel per user is outlined in the README.
- **dbt test**: none (documented only)

### stages

#### S1
**Stage spelled two ways** · affects the report: yes · found: 1 stage: 'Qualified lead' in stages, 'Qualified Lead' in the Stage field

- **Question** (CRM admin): Stage 2 is spelled 'Qualified lead' in the stages table and 'Qualified Lead' in the Stage field. Which spelling is current?
- **Explanation (assumption)**: A stage renamed in Pipedrive's pipeline settings shows the new name everywhere, so two spellings in one account seem unlikely from data entry. The two tables were possibly exported at different times (X1).
- **Impact**: The step names of the report would differ from the task's.
- **Proposed handling**: Proposed and implemented as the default: the step names come from the Stage field labels, which use the task's spelling (`int_pipedrive__funnel_steps`).
- **dbt test**: [`s1_stage_name_differs_from_field_label`](tests/data_quality/s1_stage_name_differs_from_field_label.sql)

### Checked, nothing found

Full-row duplicates in `deal_changes`, `activity` and `users`; one activity entered twice under two ids; stage moves of one deal at the same time; NULLs in required columns; owners, stages, users and activity types missing from their dictionaries; deals not starting at stage 1; stage moves dated before the deal's creation. The key and relationship checks run as generic dbt tests on the sources.

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

## Further development: the logical model in a Snowflake semantic view

The logical model (`vault/project/06_logical_model.md`) is maintained by hand and follows the dbt models: every model names its entity in `meta.logical_entity`, the keys are tested, and the marts carry primary and foreign key constraints (informational in Snowflake, visible to tools that read constraints).

A suggested next step is to expose the same model to the business through a **Snowflake semantic view**, built with dbt (`semantic_view` materialization):

- `TABLES` with primary keys for the entities a consumer queries: deals (with their creation month), stage entries, funnel steps, sales calls;
- `RELATIONSHIPS` as in the logical model: stage entry to deal and to funnel step, sales call to funnel step;
- `METRICS` for the KPIs: deals reaching a step, by creation month (cohort) or by the month of the step, and conversion between steps as derived metrics, recomputed for any grain a query picks.

BI tools and Cortex Analyst would then read the logical model and one definition of each KPI from the semantic view. It would need atomic facts in the marts (one row per deal and stage, one row per call) next to the monthly report, and the KPI owner's choice between the cohort and the event view. Not implemented.

## Repository

| Path | Content |
|---|---|
| `models/sources/pipedrive/` | sources with descriptions, keys in `meta`, raw-layer key tests |
| `models/staging`, `models/intermediate`, `models/marts` | the models |
| `macros/` | `refresh_src` (test clones), `generate_schema_name` (one schema per layer) |
| `tests/data_quality/` | custom tests: the known data quality issues, and the lost-reason key of the raw layer |
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

The setup steps of the original task (Docker, a local Postgres database, `dbt-postgres`) are replaced by the Snowflake setup above, with Enpal's agreement. The project steps are unchanged.
