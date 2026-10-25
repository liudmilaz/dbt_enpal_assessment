# Lightdash: Sales Funnel dashboard

The funnel dashboard on the dbt mart `rep_sales_funnel_monthly`: a monthly trend and two funnels (the nine stages, and all eleven task steps). Data quality is not shown here: it lives in the Elementary report (`scripts/dq_report.sh`).

- The mart is monthly, for self-service reporting by month. Quarters, weeks or years need the event grain in a semantic layer: the call steps 2.1 and 3.1 count distinct deal ids per month and must not be summed across months, so the `month` dimension offers MONTH only.
- The metric `total_deals` and the join to `dim_funnel_step` (step order) are defined in `models/marts/_marts__models.yml` (`meta`).

Setup (self-hosted Lightdash on http://localhost:8080):

1. Deploy the dbt project (the CLI reads the Snowflake target from `profiles.yml` and creates the project with that connection):
   ```bash
   source ~/.snowflake/enpal.env && export DBT_PROFILES_DIR=.
   lightdash deploy --create "Enpal Sales Funnel" --project-dir . --profiles-dir . --target test
   ```
2. Build the charts and the dashboard: `cd lightdash && python3 -I build_funnel_dashboard.py <project-uuid>`. `ldapi.py` reads the Lightdash CLI login from `~/.config/lightdash/config.yaml` at runtime; no token is stored here.
