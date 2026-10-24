# Lightdash: Deals Overview dashboard

The funnel dashboard on the dbt marts `fct_deals` and `rep_sales_funnel_monthly`, laid out like a CRM "Deals Overview": conversion gauge, big numbers (closed deals, new leads, average sales cycle), a monthly trend and two funnels. Data quality is not shown here: it lives in the Elementary report (`scripts/dq_report.sh`).

- The export has no won/lost status and no amounts: "closed" means the deal reached Closing (stage 6); the amount tiles of a usual CRM dashboard are replaced by new leads and by the funnel of all eleven task steps.
- Metrics and joins are defined in `models/marts/_marts__models.yml` (`meta`): `leads`, `closed_deals`, `conversion_rate`, `avg_sales_cycle_days`, `total_deals`.

Setup (self-hosted Lightdash on http://localhost:8080):

1. Deploy the dbt project (the CLI reads the Snowflake target from `profiles.yml` and creates the project with that connection):
   ```bash
   source ~/.snowflake/enpal.env && export DBT_PROFILES_DIR=.
   lightdash deploy --create "Enpal Sales Funnel" --project-dir . --profiles-dir . --target test
   ```
2. Build the charts and the dashboard: `cd lightdash && python3 -I build_funnel_dashboard.py <project-uuid>`. `ldapi.py` reads the Lightdash CLI login from `~/.config/lightdash/config.yaml` at runtime; no token is stored here.
