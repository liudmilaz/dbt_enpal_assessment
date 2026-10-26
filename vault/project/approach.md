# Approach

## The findings are assumptions

Almost every cleansing proposal in this project is an assumption, not a decision: how to deduplicate repeated activity ids (A1), which lifecycle of a merged deal counts (D3), whether Duplicate Entry deals leave the funnel (DUP-6), that a skipped stage counts as reached (D1, D2), which date starts step 1, and that only done calls count. The exploratory analysis shows *what* the data looks like; it cannot show *why*, and the why decides the right deduplication, adjustment or calculation.

In a real project I would settle these before building, in this order:

1. **Read the code and the documentation first**: the export or ingestion code, the CRM configuration (pipeline, mandatory fields, merge and lost-reason settings) and the source system's documentation, so I come to the meeting with the mechanism, not only the symptom.
2. **Ask for a call or meeting with the stakeholders**: the KPI owner, sales ops (data entry) and the CRM admin. I bring each finding with its evidence and a proposed default, and we agree on the rule.
3. **Only then implement the rule** and document it as a decision.

Here the stakeholders were not available, so each finding is handled with a documented default (Found / Improve / Handled in the test metadata, [[cleansing_proposals]]), and the open questions for Enpal are in [[deal_history_and_questions_for_enpal]] and [[cleansing_proposals]]. The findings of the exploratory analysis should be read as assumptions to confirm.

## Why compare with the UI

The tables show what was stored; the source system's UI shows how it was entered: which stage moves are allowed, what a lost reason or a merge does, which fields are mandatory. Many findings (skipped stages, duplicates, contradicting values) can be a defect or a rule of the data-entry process, and only the people who own the process and the KPIs can say which. Comparing the data with the UI narrows that down before the stakeholder meeting.

## How I set up the Pipedrive trial account

Goal: see the deals and activities of the export the way a sales rep sees them, and learn the process from the UI.

1. **Opened a Pipedrive trial account** (free 14-day trial).
2. **Configured it like the source:**
   - pipeline renamed and extended to the 9 stages of the export (Lead Generation to Renewal/Expansion);
   - activity types created to match `activity_types`: Sales Call 1 (the default type Meeting renamed, so its key stays `meeting`), Sales Call 2, Follow Up Call, After Close Call;
   - Pipedrive's sample data removed.
3. **Prepared the import files** with a small script (a working tool, not part of the deliverable):
   - `deals_import.csv`: one row per deal, with its current stage, owner, creation date and lost reason; the source ids and the stage path kept in custom text fields (Source deal id, Source owner id, Source lost reason id, Stage path); a placeholder organisation "Source export (test data)";
   - `activities_import.csv`: one row per activity.
4. **Imported the deals** with the import wizard: creation date mapped to "Deal created", stages mapped value by value, duplicates merged. An import can be reverted within 48 hours.
5. **Still to do:** confirm the deal count, import the activities, set Follow Up Call inactive (as in the export), then walk through the deals and activities in the UI.

Limits to know:
- Pipedrive imports the **current state** of a record, not its change history, so the stage timeline and the monthly funnel numbers can only be checked in the data.
- Times shift by 1 to 2 hours with the account's time zone.
- What the UI can confirm: deals per stage, activity totals by type and done flag, one deal's fields, how a lost reason and a merge behave.

## Technical implementation

### Zero-copy cloning and the naming convention

- **Three databases**: `ENPAL_RAW` (the CSVs, loaded once, read-only for dbt), `ENPAL_TEST` (default target) and `ENPAL_ANALYTICS_PROD`) (built from `main` only).
- **Zero-copy clones** for testing: `dbt run-operation refresh_src` clones every raw table into `ENPAL_TEST.SRC`. A clone costs no storage until it diverges, and rerunning resets the test data. Tables are cloned one by one, because a schema clone keeps the original owner and the dbt role could not replace the tables. Prod reads `ENPAL_RAW` directly; the source switches by target (var `raw_location`).
- **`generate_schema_name`**: every layer gets the same schema name in every environment (`STAGING`, `INTERMEDIATE`, `MARTS`, `ELEMENTARY`) instead of dbt's default `<target_schema>_<custom>`. The environment is told apart by the database, so a query reads the same in test and prod.

### Layers: Kimball and common sense

- **Sources**: the six raw tables with descriptions, keys in `meta`, key tests.
- **Staging** (views, one per raw table): rename and cast once, deduplicate; the names stay stable through the DAG.
- **Intermediate** (views, one business rule or one grain change per model): deals derived from the change history, stage entries, the backfill of skipped stages, the funnel steps, the sales calls.
- **Marts** (tables): `dim_funnel_step` (dimension) and the task's report `rep_sales_funnel_monthly` with an enforced contract, for self-service reporting by month. Quarters, weeks or years belong to a semantic layer or BI tool on the event grain: the call steps 2.1 and 3.1 count distinct deal ids per month and do not add up across months. No full star schema for its own sake: the export has no amounts, no products and too few user attributes for more dimensions.
- **Tests**: generic tests on every layer (unique + not_null on primary and alternate keys, not_null + relationships on foreign keys, accepted values of the funnel steps) and one singular test per data quality issue found in the exploratory analysis, which returns the affected raw rows and fails in the Elementary report. Still to add with the business process: source freshness, anomaly detection, custom tests.

### Skills: dbt and Snowflake

- **dbt**: the dbt Labs agent skills for Claude Code (analytics engineering, running dbt commands, documentation, Mermaid DAG) and a dimensional-modeling skill: they set the layer conventions, the test policy and the habit of checking every model with `dbt show` before and after a change.
- **Snowflake**: the Snowflake CLI (`snow`) with key-pair authentication for every ad-hoc query and the admin and load scripts; a service user with its own role, read-only on raw; an X-Small warehouse that suspends after 60 seconds.

### Working method

The project follows the method in this vault: exploratory analysis per raw table → findings and data quality list ([[findings]]) → assumptions and questions for the stakeholders ([[deal_history_and_questions_for_enpal]], [[cleansing_proposals]]) → logical model ([[logical_model]]) → models and tests. The general version of the method is the skill `data-project-with-claude-code` (skills repo, PR #7).
