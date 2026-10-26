# NOTES: Enpal take-home (handover between Claude sessions)

Last updated 2026-10-22. Written by the Claude session that did the exploration. First commit and PR (on the fork) include these notes.

## What we are building

Enpal Senior Analytics Engineer take-home. Build dbt models from six Pipedrive CSVs, ending in `rep_sales_funnel_monthly` with columns `month, kpi_name, funnel_step, deals_count` for steps 1, 2, 2.1, 3, 3.1, 4, 5, 6, 7, 8, 9. Original task text: [[task]]. The PR goes to the owner's own fork only.

## Platform: Snowflake instead of Postgres (agreed with Enpal)

The assignment ships a local Postgres in Docker (`docker compose up`, admin/admin). **Enpal agreed in writing that the task may be solved on my own Snowflake test account**, and that AI tools may be used as support rather than to do the whole task. So the repository sent to Enpal is Snowflake-only: no `docker-compose.yml`, no `init.sql`, no `dbt-postgres` target.

What this does and does not change:

- **Unchanged:** the six Pipedrive source tables, the layer structure, the funnel definitions and the required reporting model with its four columns.
- **Changed:** where the raw data is loaded (`ENPAL_RAW.PIPEDRIVE` instead of `postgres.public`), the setup steps in the repo README, and the SQL dialect of the analyses.
- **Why:** the role asks for Snowflake semantic views, which the funnel report can feed, and one platform keeps the repository simple to read.

The Postgres phase up to 2026-10-24 is kept as history in the decision table below and under "Before 2026-10-24: Postgres (history)".

## Status

- Environment works: own Snowflake trial account, raw loaded once into `ENPAL_RAW.PIPEDRIVE`, dbt venv `~/.venvs/enpal_sf`, `dbt build` green on the `test` target.
- Exploration is done: the main data quality issues per table (`analyses/00_data_quality_issues.sql`), one analysis file per raw table (`analyses/01_deal_changes.sql` to `06_fields.sql`), all in the solution PR; local only (gitignored): `analyses/07_data_quality_findings.sql`, `analyses/08_business_questions.sql` (the KPIs read against the business, see `vault/project/business_context.md`) and `09_review_later.sql`; dbt test probes (44 tests, 7 fail, each a finding). See `vault/project/findings.md`. The same findings are charted in the dashboard.
- All layers are written: staging, intermediate and marts, ending in `rep_sales_funnel_monthly`. Claude writes the models, the owner reviews every layer (decision of 2026-10-24).
- `vault/project/model_plan.md` has the intended layers, grains and metric definitions.

## Reminder: review later (owner)

Go through `analyses/09_review_later.sql` (local only) and write an answer under each question: the IQR rule on the stage gaps, the flat gap shape (generated data?), the month window of the report spine, and the open questions from the time distribution (157 After Close Calls before the first Closing; activities flat from the first month; owner assigned after creation).

## Decisions

| Decision | State | Why |
|---|---|---|
| Skipped stages: backfill with an `is_inferred` flag, keep recorded-only available as a variable | **Decided by the owner** | 84% of deals skip a stage; recorded-only would roughly halve the middle steps |
| PR goes to `liudmilaz/dbt_enpal_assessment`; never push to `aro-91/dbt_enpal_assessment` | **Decided by the owner** | The task says fork; the original repo holds other candidates' PRs |
| Step 1 date: first entry into stage 1 (not `add_time`) | Open. Claude recommends stage 1 entry | Same definition as every other step; `add_time` is a median 35 days earlier |
| Calls (steps 2.1, 3.1): count `done = true` only, as a variable | Open. Claude recommends done-only | About half of calls are done; planned vs held |
| Surrogate key over all columns on `deal_changes` only (`deal_change_key`); deduplication = keep the first row per key | **Decided by the owner** (2026-10-23) | No natural key; full rows are unique (0 removed today). See `vault/project/cleansing_proposals.md` (DUP-1) |
| `activity`: no surrogate key; `activity_id` is the primary key; deduplicate to one row per id, keeping the latest `due_to` | **Decided by the owner** (2026-10-23) | 4,579 rows to 4,568 (11 removed); steps 2.1 and 3.1 (done only) each lose 1 in 2024-01 and 2024-04. See `cleansing_proposals.md` (DUP-3) |
| Repeated `activity_id` (11 ids, 22 rows, 0.48%): treat as duplicates, mark as a data quality issue; cleansing per the process within the domain | **Decided by the owner** (2026-10-23) | Proven not a composite key (02_activity, section 2). Needs a review by the business stakeholder responsible for the KPIs (Sales Call 1 / 2) and the CRM data entry |
| Platform, first decision: the task's Postgres in Docker is the deliverable; Snowflake only as an optional extension branch | **Superseded** on 2026-10-24 (kept for the history) | The task ships a Postgres setup (docker compose, admin/admin); Snowflake was a bonus |
| Platform (2026-10-24): **the project runs on Snowflake** (own trial account); the repo sent to Enpal contains no Postgres | **Decided by the owner**; **agreed by Enpal** in writing: own Snowflake test account allowed; AI tools allowed as support, not to do the whole task | The job description also asks for semantic views (Snowflake), which the funnel report can show; one platform keeps the repo simple. Layout in [[snowflake_test_env_plan]] |
| Who writes the models (2026-10-24): Claude writes, the owner reviews every layer; notification at raw load and at staging with tests | **Decided by the owner** | Earlier: the owner wrote the models for training |
| A deal with two creation events counts once per step and month, by its first entry | Proposed by Claude, not confirmed | 5 deals carry two lifecycles |
| Report window 2024-01 to 2025-02 | Proposed by Claude, not confirmed | Months that have stage events; calls are 0 from 2024-10, and so are new deals (last `add_time` 2024-09-13, found by Elementary) |
| `kpi_name` = step name, `funnel_step` = step number as text (`'2.1'`) | Proposed by Claude, not confirmed | The task does not spell out the values |

## Open questions for Enpal (register)

| # | Question | Evidence | Proposed default | Owner (to confirm) | Status |
|---|---|---|---|---|---|
| 1 | Do skipped stages count as reached? | 84% of deals skip a stage | Yes, with an `is_inferred` flag (decided) | KPI owner | Decided by the analyst, to confirm |
| 2 | Is lead generation the creation date or the first stage-1 entry? | median 35 days apart | First stage-1 entry | KPI owner | Open |
| 3 | Do calls count when scheduled or when done? | about 50% done | Done only | Sales team lead, KPI owner | Open |
| 4 | Why do activities not match the deals? | 8 of 4,572 ids | Count calls by activity date | CRM admin | Open |
| 5 | What does the lost reason on every deal mean? | all 1,995 deals | Not used for the funnel | CRM admin, sales operations | Open |
| 6 | Are the 5 deals with two creations merged records? | two lifecycles each | Count once, by first entry | CRM admin | Open |
| 7 | Where is the deal status (open, won, lost)? | not in the export | Not used | CRM admin / IT | Open |

Update the status as answers arrive. Decided items are also in the Decisions table above.

## Lightdash dashboard (local)

2026-10-24, owner's rule: **Lightdash shows business dashboards only; every data quality issue lives in Elementary.** The exploration dashboard (47 SQL charts on Postgres) and its charts were deleted. All 28 findings of `analyses/07_data_quality_findings.sql` are Elementary tests (the last six added the same day: D3 backward or repeated moves, DUP-6, D4 Unreachable Customer, U2 users never referenced, options on single-option fields). A snapshot of the 145 test results is the Claude dashboard "Pipedrive data quality" (https://claude.ai/artifact/QdybrKkyQsRV6Eyn1cUTbU).

The Lightdash dashboard "Sales Funnel" (monthly trend, two funnels) runs on `rep_sales_funnel_monthly` through the dbt metric in `models/marts/_marts__models.yml`; built by `lightdash/build_funnel_dashboard.py` after `lightdash deploy --create`. The month dimension offers MONTH only: quarters and years belong to a semantic layer on the event grain, because the call steps count distinct deal ids per month. `fct_deals` and the Deals Overview tiles were removed on 2026-10-25 (outside the task's monthly report).

## Pipedrive trial (datacanonic.pipedrive.com)

Pipeline set to the 9 stages and the 4 activity types created; sample data removed. Import files are in `pipedrive_trial/` (`build_import_files.py`, `deals_import.csv`, `activities_import.csv`). Deals import started; activities import still to do. Pipedrive imports current state, not change history, so the monthly numbers cannot be checked in the UI. Setup steps: `vault/project/approach.md`.

## Done

2026-10-24: Snowflake layout built (ENPAL_RAW, ENPAL_TEST as default target with zero-copy clones, ENPAL_ANALYTICS_PROD), raw loaded, Postgres removed from the repo, staging layer (6 views, 37 tests, all pass) built in ENPAL_TEST.


Fork cloned, venv set up, per-table analysis files and the overall data-quality findings file, source declarations with probe tests (`models/sources/pipedrive/_pipedrive__sources.yml`), singular data-quality tests (`tests/data_quality/`), findings and plan docs.

## Next

1. ~~Housekeeping~~ done 2026-10-24 on `feature/elementary`: `models/test_model.sql` removed, `requirements*.txt` added (Snowflake, Elementary), the Postgres setup files removed from the repo; `target/` is untracked.
2. ~~Staging, intermediate and marts models~~ done 2026-10-24 per [[model_plan]]; the owner reviews each layer.
3. ~~Promote probe tests~~ done 2026-10-24 for the raw layer: all 7 probes moved to `tests/data_quality/` (renamed, house style), `tests/exploration/` deleted.
4. ~~Reconcile the report~~ done: the per-step totals equal the targets in [[model_plan]] and the reconciliation test passes.
5. README (setup, assumptions, open questions for Enpal), commit, PR on the fork, zip for the email.

## Rules for this project

- Keep the open-question register above up to date when a question is raised or answered. `vault/project/approach.md` holds only why the UI is compared and how the Pipedrive trial was set up (no change log).
- Never push, open a PR or comment on `aro-91/dbt_enpal_assessment`. Push only to `origin` (`liudmilaz/...`); pass `-R liudmilaz/dbt_enpal_assessment` to `gh`.
- Do not commit or push unless asked. Commit identity: `zolotukmila@datacanonic.com`.
- Never load the raw tables twice without `create or replace`: `activity` and `deal_changes` have no primary key and would double.

## Initial setup (Snowflake, since 2026-10-24)

Snowflake, built through the admin connection (`scripts/snowflake_admin.sql`, `scripts/snowflake_load.sql`):
- **ENPAL_RAW.PIPEDRIVE**: loaded by SYSADMIN; the dbt role can only read it.
- **ENPAL_TEST**: the default target. `dbt run-operation refresh_src` clones the six raw tables into `ENPAL_TEST.SRC`; the clones use 0 bytes of their own storage, and the command refuses to run on prod.
- **ENPAL_ANALYTICS_PROD**: the prod target, built from `main` only.
- **Service user ENPAL_DBT_USER**: key pair only (`~/.ssh/snowflake_enpal_dbt_rsa_key.p8`), no secondary roles. Its details are in `~/.snowflake/enpal.env`; `snow` connection `enpal`.
- `ENPAL_DB` (the first copy) was dropped on 2026-10-24.

What every database, role and warehouse in the account is for, and how the costs arise: [[snowflake_account_and_costs]]. Plan and as-built notes: [[snowflake_test_env_plan]].

## Commands

```bash
cd "~/GoogleDrive/career/code/dbt_enpal_assessment"

# dbt on Snowflake: venv outside Google Drive; profile is profiles.yml in the repo root (default target test)
source ~/.snowflake/enpal.env
source ~/.venvs/enpal_sf/bin/activate
export DBT_PROFILES_DIR=.
dbt deps
dbt run-operation refresh_src     # fresh zero-copy clones in ENPAL_TEST.SRC
dbt build                         # target test
dbt build --target prod           # only from main, after confirmation

# ad-hoc queries as the dbt service user
snow sql -c enpal -q "select count(*) from enpal_raw.pipedrive.deal_changes"

# data quality report (Elementary), served on http://localhost:8081
bash scripts/dq_report.sh
```

- dbt-core 1.10.23, dbt-snowflake 1.10.8, dbt_utils, Elementary 0.26.1 (`packages.yml`); Elementary CLI in its own venv `~/.venvs/edr`.
- Project skills (EDA, workflow, Snowflake + dbt from scratch) are in `.claude/skills/`, excluded from git.

### Before 2026-10-24: Postgres (history)

The task's setup: Docker (`docker compose up`, Colima runtime), Postgres `localhost:5432`, database `postgres`, user/password `admin`, raw tables in `public`, dbt output in `public_pipedrive_analytics`, venv `~/.venvs/enpal` with dbt-postgres 1.9.1. Replaced by Snowflake (decision in the table above); the Docker files were removed from the repo.

## Other places

- Project vault (Obsidian, source of the documentation): `Learning/enpal_assessment_vault/` in Google Drive (`project/`, `wiki/`); copied to the repo's `vault/` by `scripts/sync_vault.sh`.
- Skills repo: `~/GoogleDrive/career/code/data-engineering-agent-skills`, branch `skills/eda`, PR #6 on `liudmilaz/data-engineering-agent-skills`.
- Exploration dashboard: https://claude.ai/artifact/TFJEc4EbMPTMELGNdeFpvJ
