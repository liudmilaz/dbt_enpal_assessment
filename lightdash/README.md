# Lightdash dashboard: exploratory analysis per table

Builds a local Lightdash dashboard with one tab per raw table (plus an overview tab with the data-quality findings). Every chart is a saved SQL chart that runs against the Docker Postgres.

- Lightdash: self-hosted, `http://localhost:8080` (Colima). Project **Enpal Pipedrive EDA** (Postgres connection, no dbt connection). The Lightdash container reaches the Postgres container (Docker Desktop) through the Mac host: host `host.docker.internal`, port 5432.
- Tabs: Overview, deal_changes, activity, activity_types, users, stages, fields. Each table tab has a context box (class, grain, findings, fields used with Pipedrive documentation links) and charts for: all columns, primary key, foreign keys, nulls, outliers, descriptive analytics.
- Rebuild: `python3 -I lightdash/build_dashboard.py` (the Lightdash project must exist; put its uuid in a `project.json` next to the scripts as `{"project": {"projectUuid": "<uuid>"}}`). The scripts read the CLI login from `~/.config/lightdash/config.yaml` at runtime; no token is stored here.
- `ldapi.py` (API helper), `ldbuild.py` (chart payloads, expects `project.json` with the project uuid next to it), `build_dashboard.py` (tabs, charts, dashboard).
- The queries mirror `analyses/01_deal_changes.sql` to `analyses/07_data_quality_findings.sql`.
