# NOTES: Enpal take-home (handover between Claude sessions)

Last updated 2026-10-22. Written by the Claude session that did the exploration. First commit and PR (on the fork) include these notes.

## What we are building

Enpal Senior Analytics Engineer take-home. Build dbt models on Postgres (Docker) from six Pipedrive CSVs, ending in `rep_sales_funnel_monthly` with columns `month, kpi_name, funnel_step, deals_count` for steps 1, 2, 2.1, 3, 3.1, 4, 5, 6, 7, 8, 9. Original task text: `README.md`. The PR goes to the owner's own fork only.

## Status

- Environment works: Docker Postgres loaded once, dbt venv, `dbt run` passed on the test model.
- Exploration is done: the main data quality issues per table (`analyses/00_data_quality_issues.sql`), one analysis file per raw table (`analyses/01_deal_changes.sql` to `06_fields.sql`), all in the solution PR; local only (gitignored): `analyses/07_data_quality_findings.sql`, `analyses/08_business_questions.sql` (the KPIs read against the business, see `vault/project/business_context.md`) and `09_review_later.sql`; dbt test probes (44 tests, 7 fail, each a finding). See `vault/project/findings.md`. The same findings are charted in the dashboard.
- No models are written yet. **The owner is writing the dbt models herself, for training. Do not write models; explain, review and answer questions.**
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
| Platform (2026-10-24): **the project runs on Snowflake** (own trial account UE17459); the repo sent to Enpal contains no Postgres | **Decided by the owner**; **agreed by Enpal** in writing: own Snowflake test account allowed; AI tools allowed as support, not to do the whole task | The job description also asks for semantic views (Snowflake), which the funnel report can show; one platform keeps the repo simple. Layout in [[snowflake_test_env_plan]] |
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

Project **Enpal Pipedrive EDA** on the local Lightdash (`http://localhost:8080`), dashboard "Enpal Pipedrive: exploratory analysis per table": one tab per raw table plus an Overview tab, 47 SQL charts. Built by `lightdash/build_dashboard.py` (see `lightdash/README.md`). Sign in with your own Lightdash account.

## Pipedrive trial (datacanonic.pipedrive.com)

Pipeline set to the 9 stages and the 4 activity types created; sample data removed. Import files are in `pipedrive_trial/` (`build_import_files.py`, `deals_import.csv`, `activities_import.csv`). Deals import started; activities import still to do. Pipedrive imports current state, not change history, so the monthly numbers cannot be checked in the UI. Setup steps: `vault/project/approach.md`.

## Done

2026-10-24: Snowflake layout built (ENPAL_RAW, ENPAL_TEST as default target with zero-copy clones, ENPAL_ANALYTICS_PROD), raw loaded, Postgres removed from the repo, staging layer (6 views, 37 tests, all pass) built in ENPAL_TEST.


Fork cloned, Docker and venv set up, VS Code SQLTools connection, per-table analysis files and the overall data-quality findings file, source declarations with probe tests (`models/staging/pipedrive/_pipedrive__sources.yml`), singular probe tests (`tests/exploration/`), findings and plan docs.

## Next

1. ~~Housekeeping~~ done 2026-10-24 on `feature/elementary`: `models/test_model.sql` removed, `requirements*.txt` added (Postgres, Snowflake, Elementary), Postgres image pinned to 18.6; `target/` was never tracked.
2. Owner writes staging, intermediate and marts models per `vault/project/model_plan.md`.
3. ~~Promote probe tests~~ done 2026-10-24 for the raw layer: all 7 probes moved to `tests/data_quality/` (renamed, house style), `tests/exploration/` deleted. Staging tests come with the owner's models (phase 3).
4. Reconcile the report with the numbers in `vault/project/model_plan.md`.
5. README (setup, assumptions, open questions for Enpal), commit, PR on the fork, zip for the email.

## Rules for this project

- Keep the open-question register above up to date when a question is raised or answered. `vault/project/approach.md` holds only why the UI is compared and how the Pipedrive trial was set up (no change log).
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

- Project vault (Obsidian, source of the documentation): `Learning/enpal_assessment_vault/` in Google Drive (`project/`, `wiki/`); copied to the repo's `vault/` by `scripts/sync_vault.sh`.
- Skills repo: `~/GoogleDrive/career/code/data-engineering-agent-skills`, branch `skills/eda`, PR #6 on `liudmilaz/data-engineering-agent-skills`.
- Exploration dashboard: https://claude.ai/artifact/TFJEc4EbMPTMELGNdeFpvJ
