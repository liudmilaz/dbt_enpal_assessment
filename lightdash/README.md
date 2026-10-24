# Lightdash dashboard: exploratory analysis per table

Builds a Lightdash dashboard with one tab per raw table (plus an overview tab with the data-quality findings). Every chart is a saved SQL chart that runs on Snowflake against `ENPAL_RAW.PIPEDRIVE`.

- Lightdash: self-hosted, `http://localhost:8080`. The project needs a **Snowflake connection** (account from `~/.snowflake/enpal.env`, user `ENPAL_DBT_USER` with its key pair, role `ENPAL_DBT_ROLE`, warehouse `ENPAL_WH`, database `ENPAL_RAW`). Add it in the Lightdash UI (Project settings, Connection); the key is never written into this repo.
- Tabs: Overview, deal_changes, activity, activity_types, users, stages, fields. Each table tab has a context box (class, grain, findings, fields used with Pipedrive documentation links) and charts for: all columns, primary key, foreign keys, nulls, outliers, descriptive analytics.
- Rebuild: `python3 -I lightdash/build_dashboard.py` from `lightdash/` (put the project uuid in a `project.json` next to the scripts as `{"project": {"projectUuid": "<uuid>"}}`). The scripts read the Lightdash CLI login from `~/.config/lightdash/config.yaml` at runtime and the column names through the `snow` CLI connection `enpal` (override with `SNOW_CONNECTION`); no token is stored here.
- `ldapi.py` (API helper), `ldbuild.py` (chart payloads; column names as Snowflake returns them, upper case for unquoted aliases), `build_dashboard.py` (tabs, charts, dashboard).
- The queries mirror `analyses/01_deal_changes.sql` to `analyses/07_data_quality_findings.sql`; all 47 were run on Snowflake and compared with the earlier Postgres results (same numbers; only formatting differs).
- Scope: Lightdash is meant for the final funnel dashboard on `rep_sales_funnel_monthly`; data quality is tracked in the Elementary report (`scripts/dq_report.sh`). This exploration dashboard stays until the owner retires it.
