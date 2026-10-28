# Approach

## The findings are assumptions

Almost every cleansing step in this project rests on an assumption, not on a confirmed rule: how to deduplicate repeated activity ids (A1), how a deal with two lifecycles counts (D3), whether Duplicate Entry deals leave the funnel (DUP-6), that a skipped stage counts as reached (D1, D2), and that only done calls count (A4). The exploratory analysis shows *what* the data looks like; it cannot show *why*, and the why would decide the right deduplication, adjustment or calculation.

In a real project I would suggest settling these before building, in this order:

1. **Read the code and the documentation first**: the export or ingestion code, the CRM configuration (pipeline, mandatory fields, merge and lost-reason settings) and the source system's documentation, so that the meeting can start from the mechanism, not only the symptom.
2. **Meet the stakeholders**: the KPI owner, sales ops (data entry) and the CRM admin, with each finding, its evidence and a proposed default, to agree on the rule.
3. **Then implement the rule** and document it as a decision.

Here the stakeholders were not available, so each finding is handled with a documented default. The issues, the assumptions behind them, the questions for the stakeholders and the dbt tests are in [[05_data_quality_issues_and_assumptions]].

## Why compare with the UI

The tables show what was stored; the source system's UI shows how it was entered: which stage moves are allowed, what a lost reason or a merge does, which fields are mandatory. Many findings (skipped stages, duplicates, contradicting values) could be a defect, a rule of the data entry process or a feature of the tool, and only the people who own the process and the KPIs can say which. Comparing the data with the UI could narrow that down before the stakeholder meeting.

## How I set up the Pipedrive trial account

A free Pipedrive trial was set up like the source: the nine pipeline stages, the four activity types, Pipedrive's sample data removed, and the deals imported with the import wizard. It was used to see the data the way a sales rep sees it. Some of the assumptions in this project were made from the Pipedrive documentation and the trial rather than from the data alone. An import creates the current state of a deal, not its history, so the monthly numbers could only be checked in the data.

## Technical implementation

### Zero-copy cloning and the naming convention

- **Three databases**: `ENPAL_RAW` (the CSVs, loaded once, read-only for dbt), `ENPAL_TEST` (default target) and `ENPAL_ANALYTICS_PROD` (built from `main` only).
- **Zero-copy clones** for testing: `dbt run-operation refresh_src` clones every raw table into `ENPAL_TEST.SRC`. A clone costs no storage until it diverges, and rerunning resets the test data. Tables are cloned one by one, because a schema clone keeps the original owner and the dbt role could not replace the tables. Prod reads `ENPAL_RAW` directly; the source switches by target (var `raw_location`).
- **`generate_schema_name`**: every layer gets the same schema name in every environment (`STAGING`, `INTERMEDIATE`, `MARTS`, `ELEMENTARY`) instead of dbt's default `<target_schema>_<custom>`. The environment is told apart by the database, so a query reads the same in test and prod.

### Layers: Kimball and common sense

- **Sources**: the six raw tables with descriptions, keys in `meta`, key tests.
- **Staging** (views, one per raw table): rename and cast once, deduplicate; the names stay stable through the DAG.
- **Intermediate** (views, one business rule or one grain change per model): the deal cohorts (creation month), stage entries, the backfill of skipped stages, the funnel steps, the sales calls.
- **Marts** (tables): `dim_funnel_step` (dimension) and the task's report `rep_sales_funnel_monthly` with an enforced contract. The report counts every stage step in the month the deal was created (cohort), as Pipedrive's deal conversion report does; the call steps, which cannot be linked to the deals, count by the month the call was due. A full star schema seemed unnecessary here: the export has no amounts, no products and too few user attributes for more dimensions.
- **Tests**: generic tests on every layer (unique + not_null on primary and alternate keys, not_null + relationships on foreign keys, accepted values of the funnel steps) and one singular test per data quality issue, which returns the affected raw rows.

### Skills: dbt and Snowflake

- **dbt**: the dbt Labs agent skills for Claude Code (analytics engineering, running dbt commands, documentation, Mermaid DAG) and a dimensional-modeling skill: they set the layer conventions, the test policy and the habit of checking every model with `dbt show` before and after a change.
- **Snowflake**: the Snowflake CLI (`snow`) with key-pair authentication for every ad-hoc query and the admin and load scripts; a service user with its own role, read-only on raw; an X-Small warehouse that suspends after 60 seconds.

### Data catalog (dbt docs)

A data catalog is the shared reference of what the data means: every source, model and column with its description, the keys and tests, and the lineage from the raw tables to the report. Here it is dbt's own catalog, built from the descriptions and `meta` in the YAML and the column types in Snowflake:

```bash
source ~/.snowflake/enpal.env              # Snowflake account, user and key path
source ~/.venvs/enpal_sf/bin/activate      # dbt venv
export DBT_PROFILES_DIR=.                  # profiles.yml in the repo root
dbt docs generate                          # target/index.html, manifest.json, catalog.json
dbt docs serve --port 8082                 # http://localhost:8082, lineage graph at the bottom right
```

**Suggestion for production: Snowflake Horizon.** dbt's lineage ends at the dbt models. Snowflake Horizon records lineage inside the account, from the raw tables through the dbt models to the objects built on them, and shows it in Snowsight. To confirm with the data team: the Snowflake edition (lineage needs Enterprise or higher) and how far the lineage reaches into semantic views and the BI tool.

### Data quality monitoring (Elementary)

A monitoring with Elementary is prepared in the repository (`bash scripts/dq_report.sh`): each issue found in the exploratory analysis runs as a dbt test and fails with its affected raw rows. A full rollout would need some more implementation time (scheduling, alerting, ownership of the issues). For the current data quality check, the decision was to proceed with Claude charts: the dashboard [Pipedrive exploratory analysis](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e) shows each issue with its affected raw rows and its query, which is quick to share in a stakeholder conversation.

The tools are only part of it: a rollout of data quality monitoring would need the team. The data team owns the tests and the pipeline, the CRM admin and sales ops own the fixes at the source, the KPI owner decides the rules, and together they could agree who is alerted, how often the issues are reviewed and when an issue counts as solved.

**Question for Enpal's data team**: is Elementary (or another tool) already used for data quality checks, and is a data catalog deployed? Elementary, or an equivalent, could find a good use, because the report is only as good as the CRM data and the issues have to be worked through with the stakeholders.

### Reporting for stakeholders (BI tool)

The report is a table for self-service reporting; stable reporting for the stakeholders would need the BI tool that already exists at Enpal on top of `rep_sales_funnel_monthly`, ideally through a semantic layer. No BI tool is part of this solution. The analysis is shown in two dashboards built with Claude charts: [Pipedrive funnel EDA](https://claude.ai/artifact/TFJEc4EbMPTMELGNdeFpvJ) (the Pipedrive terms, the data quality assumptions, how the KPI is calculated, the monthly report and the funnel) and [Pipedrive exploratory analysis](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e) (one tab per raw table with its data quality issues, and the tables, keys and nulls).

A funnel per user (owner history, `dim_user`, event-grain facts, slicing in the semantic layer) is suggested in the README section "Further development: the funnel per user"; not implemented.

### Working method

Exploratory analysis per raw table → data quality issues and assumptions ([[05_data_quality_issues_and_assumptions]]) → logical model ([[06_logical_model]]) → models and tests. The general version of the method is the skill `data-project-with-claude-code`.
