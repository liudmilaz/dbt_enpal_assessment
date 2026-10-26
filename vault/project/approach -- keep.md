# Approach

## The findings are assumptions

Almost every cleansing proposal in this project is an assumption, not a decision: how to deduplicate repeated activity ids (A1), which lifecycle of a merged deal counts (D3), whether Duplicate Entry deals leave the funnel (DUP-6), that a skipped stage counts as reached (D1, D2), which date starts step 1, and that only done calls count. The exploratory analysis shows *what* the data looks like; it cannot show *why*, and the why decides the right deduplication, adjustment or calculation.

In a real project I would settle these before building, in this order:

1. **Read the code and the documentation first**: the export or ingestion code, the CRM configuration (pipeline, mandatory fields, merge and lost-reason settings) and the source system's documentation, so I come to the meeting with the mechanism, not only the symptom.
2. **Ask for a call or meeting with the stakeholders**: the KPI owner, sales ops (data entry) and the CRM admin. I bring each finding with its evidence and a proposed default, and we agree on the rule.
3. **Only then implement the rule** and document it as a decision.

Here the stakeholders were not available, so each finding is handled with a documented default (Found / Handled in the test metadata, [[cleansing_proposals]]), and every assumption is listed as a question, for the data team and for the stakeholders, in [[questions_for_enpal]]. The findings of the exploratory analysis should be read as assumptions to confirm.

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

### Data catalog (dbt docs)

A data catalog is the shared reference of what the data means: every source, model and column with its description, the keys and tests, and the lineage from the raw tables to the report. It lets an analyst or a stakeholder find the right table and read its definition without asking the data team, shows the impact of a change before it is made (which models and reports depend on a column), and is the context an AI analytics tool reads. Here it is dbt's own catalog, built from the descriptions and `meta` in the YAML and the column types in Snowflake:

```bash
source ~/.snowflake/enpal.env              # Snowflake account, user and key path
source ~/.venvs/enpal_sf/bin/activate      # dbt venv
export DBT_PROFILES_DIR=.                  # profiles.yml in the repo root
dbt docs generate                          # target/index.html, manifest.json, catalog.json
dbt docs serve --port 8082                 # http://localhost:8082 (8081 is the Elementary report)
```

Locally it is served on localhost only; in production the generated site would be published (dbt Cloud, a static bucket, or a catalog tool that reads the dbt artifacts).

**Lineage on localhost**, from the raw tables to the report:

```bash
dbt docs serve --port 8082                                    # after dbt docs generate: open the lineage graph (button at the bottom right)
dbt ls --select +rep_sales_funnel_monthly --resource-type model --resource-type source   # the same lineage as a list in the terminal
```

The Elementary report (`bash scripts/dq_report.sh`, http://localhost:8081) also has a Lineage page, with the test results on each node.

**Suggestion for production: Snowflake Horizon.** dbt's lineage ends at the dbt models. Snowflake Horizon (the governance and catalog features of Snowflake) records lineage inside the account, from the raw tables through the dbt views and tables to the objects built on them, and shows it in Snowsight (Lineage tab of a table). With the report fed into a Snowflake semantic view for the BI layer, one lineage would cover the raw data, the models and the metrics. To confirm with the data team: the Snowflake edition (lineage needs Enterprise or higher) and how far the lineage reaches into semantic views and the BI tool.

### Data quality monitoring (Elementary)

The quality of this data product depends on the quality of the CRM data, and the fixes depend on the people who enter it. The data quality tests therefore run in Elementary (`bash scripts/dq_report.sh`): every issue found in the exploratory analysis fails with its affected raw rows, which is the basis for the discussion with the stakeholders (sales ops, CRM admin, KPI owner).

For ad hoc tracking between the scheduled runs, Claude can chart the quality directly from the same tests: it runs the query of an issue (see [[data_quality_issues]]) and draws, for example, the affected rows per month or per stage, which is quick to share in a stakeholder conversation.

The tools are only part of it: a proper rollout of the data quality monitoring needs team effort and collaboration. The data team owns the tests and the pipeline, the CRM admin and sales ops own the fixes at the source, the KPI owner decides the rules (deduplication, adjustment, calculation), and together they agree who is alerted, how often the issues are reviewed and when an issue counts as solved.

**Question for Enpal's data team** (T14 in [[questions_for_enpal]]): do you already use Elementary (or another tool) for data quality checks, and do you run a deployed data catalog? In my experience a deployed catalog is often missing; Elementary, or an equivalent, is needed here in any case, because the report is only as good as the CRM data and the issues have to be worked through with the stakeholders.

### Reporting for stakeholders (BI tool)

The report is a table for self-service reporting; stable and scalable reporting for the stakeholders needs the BI tool that already exists at Enpal (Tableau, Lightdash or any other) on top of `rep_sales_funnel_monthly`, ideally through a semantic layer (T17 in [[questions_for_enpal]]). No BI tool is part of this solution. Instead, the analysis is shown as one dashboard built with Claude charts, [Pipedrive funnel and data quality](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e): the first tab is the exploratory analysis of the funnel (on the same Snowflake models as the report), the other tabs the data quality issues per raw table.

### Working method

The project follows the method in this vault: exploratory analysis per raw table → findings and data quality list ([[findings]]) → assumptions and questions for the stakeholders ([[deal_history_and_questions_for_enpal]], [[cleansing_proposals]]) → logical model ([[logical_model]]) → models and tests. The general version of the method is the skill `data-project-with-claude-code` (skills repo, PR #7).
