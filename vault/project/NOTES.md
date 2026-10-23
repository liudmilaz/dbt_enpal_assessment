# NOTES: Enpal take-home (handover between Claude sessions)

Last updated 2026-10-22. Written by the Claude session that did the exploration. First commit and PR (on the fork) include these notes.

## What we are building

Enpal Senior Analytics Engineer take-home. Build dbt models on Postgres (Docker) from six Pipedrive CSVs, ending in `rep_sales_funnel_monthly` with columns `month, kpi_name, funnel_step, deals_count` for steps 1, 2, 2.1, 3, 3.1, 4, 5, 6, 7, 8, 9. Original task text: `README.md`. The PR goes to the owner's own fork only.

## Status

- Environment works: Docker Postgres loaded once, dbt venv, `dbt run` passed on the test model.
- Exploration is done: one analysis file per raw table (`analyses/01_deal_changes.sql` to `06_fields.sql`) plus `vault/project/sql/07_data_quality_findings.sql` and `vault/project/sql/08_business_questions.sql` (the KPIs read against the business, see `vault/project/business_context.md`); dbt test probes (44 tests, 7 fail, each a finding). See `vault/project/findings.md`. The same findings are charted in the dashboard.
- No models are written yet. **The owner is writing the dbt models herself, for training. Do not write models; explain, review and answer questions.**
- `vault/project/model_plan.md` has the intended layers, grains and metric definitions.

## Reminder: review later (owner)

Go through `vault/project/sql/09_review_later.sql` and write an answer under each question: the IQR rule on the stage gaps, the flat gap shape (generated data?), the month window of the report spine, and the open questions from the time distribution (157 After Close Calls before the first Closing; activities flat from the first month; owner assigned after creation).

## Decisions

| Decision | State | Why |
|---|---|---|
| Skipped stages: backfill with an `is_inferred` flag, keep recorded-only available as a variable | **Decided by the owner** | 84% of deals skip a stage; recorded-only would roughly halve the middle steps |
| PR goes to `liudmilaz/dbt_enpal_assessment`; never push to `aro-91/dbt_enpal_assessment` | **Decided by the owner** | The task says fork; the original repo holds other candidates' PRs |
| Step 1 date: first entry into stage 1 (not `add_time`) | Open. Claude recommends stage 1 entry | Same definition as every other step; `add_time` is a median 35 days earlier |
| Calls (steps 2.1, 3.1): count `done = true` only, as a variable | Open. Claude recommends done-only | About half of calls are done; planned vs held |
| Repeated `activity_id` (11 ids, 22 rows, 0.48%): treat as duplicates, mark as a data quality issue; cleansing per the process within the domain | **Decided by the owner** (2026-10-23) | Proven not a composite key (02_activity, section 2). Needs a review by the business stakeholder responsible for the KPIs (Sales Call 1 / 2) and the CRM data entry |
| Snowflake extension branch | Open. Not started | Optional bonus; Postgres is the deliverable |
| A deal with two creation events counts once per step and month, by its first entry | Proposed by Claude, not confirmed | 5 deals carry two lifecycles |
| Report window 2024-01 to 2025-02 | Proposed by Claude, not confirmed | Months that have stage events; calls are 0 from 2024-10 |
| `kpi_name` = step name, `funnel_step` = step number as text (`'2.1'`) | Proposed by Claude, not confirmed | The task does not spell out the values |

## Lightdash dashboard (local)

Project **Enpal Pipedrive EDA** on the local Lightdash (`http://localhost:8080`), dashboard "Enpal Pipedrive: exploratory analysis per table": one tab per raw table plus an Overview tab, 47 SQL charts. Built by `lightdash/build_dashboard.py` (see `lightdash/README.md`). Sign in with your own Lightdash account.

## Pipedrive trial (datacanonic.pipedrive.com)

Pipeline set to the 9 stages and the 4 activity types created; sample data removed. Import files are in `pipedrive_trial/` (`build_import_files.py`, `deals_import.csv`, `activities_import.csv`). The import itself is not done yet. Pipedrive imports current state, not change history, so the monthly numbers cannot be checked in the UI. See `vault/project/approach.md`.

## Done

Fork cloned, Docker and venv set up, VS Code SQLTools connection, per-table analysis files and the overall data-quality findings file, source declarations with probe tests (`models/staging/pipedrive/_pipedrive__sources.yml`), singular probe tests (`tests/exploration/`), findings and plan docs.

## Next

1. Housekeeping: `.gitignore` (`target/`, `logs/`, `dbt_packages/`, `.venv/`), remove tracked `target/`, delete `models/test_model.sql`, add `requirements.txt`, pin the Postgres image tag in `docker-compose.yml`.
2. Owner writes staging, intermediate and marts models per `vault/project/model_plan.md`.
3. Promote confirmed probe tests to the staging YAML with severities; delete the rest of `tests/exploration/`.
4. Reconcile the report with the numbers in `vault/project/model_plan.md`.
5. README (setup, assumptions, open questions for Enpal), commit, PR on the fork, zip for the email.

## Rules for this project

- Update `vault/project/approach.md` (change log and open-question register) with every change pushed to the PR.
- Never push, open a PR or comment on `aro-91/dbt_enpal_assessment`. Push only to `origin` (`liudmilaz/...`); pass `-R liudmilaz/dbt_enpal_assessment` to `gh`.
- Do not commit or push unless asked. Commit identity: `zolotukmila@datacanonic.com`.
- Never run `docker compose up` a second time on a loaded database (the loader appends; `activity` and `deal_changes` have no primary key and double).

## Commands

```bash
cd "~/GoogleDrive/career/code/dbt_enpal_assessment"

# Docker (Colima is the running runtime)
docker ps                          # is it up? if not: colima start
docker compose up -d               # only when the container does not exist yet
docker compose down -v && docker compose up -d   # reset and reload the CSVs once
docker exec -it dbt_enpal_assessment-db-1 psql -U admin -d postgres

# dbt: venv is outside Google Drive; profile is profiles.yml in the repo root
source ~/.venvs/enpal/bin/activate
export DBT_PROFILES_DIR=.
dbt deps
dbt debug
dbt test --select "source:*" "test_type:singular" --store-failures   # probes; failing rows go to schema public_dbt_test__audit
dbt build
```

- Postgres: host `localhost`, port `5432`, database `postgres`, user `admin`, password `admin`. Raw tables in schema `public`. dbt output schema: `public_pipedrive_analytics` (from `+schema: pipedrive_analytics`).
- dbt-core 1.10.23, dbt-postgres 1.9.1, dbt_utils 1.4.1 (`packages.yml`).
- VS Code: SQLTools connection is in `.vscode/settings.json`. Run a statement with Cmd+E, Cmd+E.
- Project skills (EDA, from the owner's skills repo PR #6) are in `.claude/skills/`, excluded from git via `.git/info/exclude`.

## Other places

- Learning vault (notes and flashcards): `~/GoogleDrive/Learning/enpal_assessment_vault/` (`wiki/`, `flashcards/`).
- Skills repo: `~/GoogleDrive/career/code/data-engineering-agent-skills`, branch `skills/eda`, PR #6 on `liudmilaz/data-engineering-agent-skills`.
- Exploration dashboard: https://claude.ai/artifact/TFJEc4EbMPTMELGNdeFpvJ
