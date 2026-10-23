---
tags:
  - project/enpal
  - type/index
---

# Enpal take-home — Senior Analytics Engineer

Pipedrive CRM → dbt on Postgres (Docker) → `rep_sales_funnel_monthly`.

- Task repo (original): https://github.com/aro-91/dbt_enpal_assessment
- My fork: https://github.com/liudmilaz/dbt_enpal_assessment
- Local clone: `~/GoogleDrive/career/code/dbt_enpal_assessment`
- dbt venv (outside Drive): `~/.venvs/enpal`

## Notes

| Note | What it holds |
|---|---|
| [[01_implementation_plan]] | The plan, status, open decisions, commands |
| [[02_data_findings]] | Verified facts and traps in the 6 CSVs |
| [[03_qa_log]] | Every question asked during the implementation, by topic, linked to notes |
| [[docker_and_environments]] | What Docker is for, Docker vs venv, why not native Postgres, manual `docker compose` |
| [[oltp_vs_olap_databases]] | Row vs columnar, Postgres / MySQL / Oracle / SQL Server vs BigQuery / Snowflake |
| [[postgres_at_scale]] | How Postgres runs in a bigger company, why it "crashes" under analytics |
| [[startup_spreadsheet_data_stack]] | Low-cost stack for raw Excel/CSV sheets |
| [[dbt_source_tests_and_loader_gotcha]] | Staging-level tests, the double-load bug |
| [[vscode_postgres_manual_exploration]] | VS Code + SQLTools + psql: explore the Postgres data by hand |
| [[pipedrive_crm_terms]] | Pipedrive vocabulary and how each exported table maps to it |
| [[eda_skills]] | The three EDA / data-quality Claude Code skills and the theory behind them |

Flashcards: `flashcards/project/enpal_*.md` (tag `project/enpal`).
