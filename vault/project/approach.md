# How I approach this work (and how I did it here)

This file explains the method behind the changes in this PR, as I would work on a real project. It is updated with every change pushed to the PR (see the log at the end).

## Principle

Data is a record of a business process. When the source system has a UI, **look at it before trusting the data**, and cross-check what the tables say against what the system shows. Skipping that check is the most common way to build a precise model of the wrong thing. Many data-quality problems are not pipeline bugs: they come from how people enter data and how the process is defined. Those cannot be fixed in SQL; they need an answer from the business.

## Steps

1. **Understand the process before the data.** Read the tool's vocabulary (deal, stage, activity, status) and walk through the UI as a user: create a record, move it, close it, and see what the history shows.
2. **Get the data into a place where I can compare it with the UI.** Load the same records into the system (or a sandbox) so the screen and the tables describe the same thing.
3. **Explore the data** (`analyses/`): grain, keys, nulls, distributions, key overlap, and probe the assumptions with dbt tests. Write each finding with its consequence.
4. **Cross-check against the UI.** Pick a few records and totals and compare: counts per stage, a deal's history, activity totals and done flags. Note every mismatch.
5. **Classify each issue:** pipeline defect (fix in code), modelling choice (decide and document), or business-process / data-entry issue (ask the business).
6. **Raise business questions early and to a named owner**, with evidence and a proposed default, and keep working on the default so the project is not blocked.
7. **Model, test, document.** Tests promoted from the probes, a plan that states grain and keys, the assumption written next to the model.
8. **Record decisions** with date, owner and consequence, so a later change of the answer shows what to re-run.

## Who owns the answer

Find the owner before the project phase that needs the answer. Typical owners, to be confirmed against the real organisation:

| Kind of question | Typical owner | When to settle it |
|---|---|---|
| KPI definition (what counts as a lead, a qualified lead, a call held) | KPI owner: head of sales or revenue operations | OKR planning, before the KPI is built; changes only at the next OKR review |
| Data entry rules (when a stage is set, when a deal is marked lost, merging duplicates) | Sales operations / CRM admin, with the sales team lead for enforcement | Project kickoff; re-check at each release that changes the process |
| Pipeline and stage configuration, activity types, required fields | CRM admin | Project phase of the build, before historical comparisons |
| Which activities count (done vs scheduled, which types) | Sales team lead and the KPI owner | Definition workshop, written down |
| Access, exports, history retention, what the export omits | CRM admin / IT | Project kickoff |
| Reporting use of the numbers | Business sponsor of the report | Sign-off of the first version |

Ask in writing, give the evidence (a query result and a screenshot), propose a default, and ask for a date. Record the answer in the register below.

## What this looks like in this project

Source: Pipedrive export, six CSV tables (`raw_data/`). Goal: monthly sales funnel report.

- **UI access:** a Pipedrive trial account is available. The plan is to load the task data into it and compare. Limit to know up front: Pipedrive imports the *current state* of records, not their change history. The imported deals will show a stage and the source values, but the stage-change timeline and the monthly numbers can only be checked in the data, not in the UI. What can be cross-checked in the UI: deals per stage, activity totals by type, done share, a deal's fields.
- **Data-quality findings that are really process questions** (see `vault/project/findings.md` and the register):
  - activities do not link to deals (8 of 4,572 ids match): data entry or export problem;
  - every deal has a lost reason, even deals at the last stage: process definition (Pipedrive only allows a lost reason on lost deals);
  - 84% of deals skip stages: users move deals freely, so the funnel definition must say how skipped stages count;
  - 5 deals with two creation events: probably merged or duplicated deals;
  - half of the activities are not marked done: does the KPI mean planned or held;
  - no deal status in the export: won and lost cannot be read.

## Open question register

| # | Question | Evidence | Proposed default | Owner (to confirm) | Status |
|---|---|---|---|---|---|
| 1 | Do skipped stages count as reached? | 84% of deals skip a stage | Yes, with an `is_inferred` flag (decided) | KPI owner | Decided by the analyst, to confirm |
| 2 | Is lead generation the creation date or the first stage-1 entry? | median 35 days apart | First stage-1 entry | KPI owner | Open |
| 3 | Do calls count when scheduled or when done? | about 50% done | Done only | Sales team lead, KPI owner | Open |
| 4 | Why do activities not match the deals? | 8 of 4,572 ids | Count calls by activity date | CRM admin | Open |
| 5 | What does the lost reason on every deal mean? | all 1,995 deals | Not used for the funnel | CRM admin, sales operations | Open |
| 6 | Are the 5 deals with two creations merged records? | two lifecycles each | Count once, by first entry | CRM admin | Open |
| 7 | Where is the deal status (open, won, lost)? | not in the export | Not used | CRM admin / IT | Open |

## Where the data is

- Task CSVs: `raw_data/` (loaded into Postgres schema `public` by `docker compose up`).
- Files prepared for the trial account: `pipedrive_trial/deals_import.csv` (one row per deal, current state) and `pipedrive_trial/activities_import.csv`, built by `pipedrive_trial/build_import_files.py`.
- In Pipedrive after the import: Deals (list and pipeline view, a deal's detail page with its history), Activities (list and calendar), and the import history in the import wizard. Menu names are as seen in the trial UI and should be re-checked after the import.

## Change log

Newest first. One entry per push to the PR.

| Date | Change | Why | Cross-check done | Open questions raised |
|---|---|---|---|---|
| 2026-10-23 | Flashcards removed from the vault (moved back to the separate learning folder in Drive) | The vault holds the project documentation and the learning notes, not study cards | Links to `flashcards/` removed from the home page, the wiki index, the Q&A log and the notes | none |
| 2026-10-23 | Documentation moved to an Obsidian vault (source: Google Drive; copy in the repo's `vault/`, synced by `scripts/sync_vault.sh`) and pushed as a separate PR stacked on the analysis PR: task, business context, new CRM field definitions in business terms, data dictionary, findings, approach, model plan, notes, deal history, analyses 07 to 09, learning notes and flashcards. Repeated `activity_id`: decided as duplicates, a data quality issue | Keep the documentation, decisions and data quality findings in one navigable place, reviewable separately from the SQL | Path references updated in the analyses and the docs; absolute local paths with the personal Drive folder replaced in the repo copy | Cleansing of the duplicate activities: needs the business stakeholder responsible for the KPIs and data entry |
| 2026-10-23 | Business context in one file (`vault/project/business_context.md`); analyses rewritten (final queries only, CTEs, filters first, commented steps, typed JSON unpacking, one read of `deal_changes` in 07); outliers for fact tables as rows per month, per dimension and per dimension and month; `vault/project/sql/08_business_questions.sql` (KPIs against business expectations); `vault/project/sql/09_review_later.sql` (statistical checks to revisit); `vault/project/deal_history_and_questions_for_enpal.md` (deal 399956, backfill, three questions with SQL) | Read the data with the business process in mind, not only its quality; keep the SQL reviewable line by line | Every rewrite rerun and diffed against the previous output (identical); Postgres case sensitivity verified; Pipedrive merge documentation read (survivor and deleted deal described, history not described); 99.8% of changes share the deal's creation clock time (generated timing) | Are merged deals' histories kept in the export? How is Duplicate Entry chosen? Can a deal reach stages 7 to 9 without Closing (683 of 1,081 do)? 157 After Close Calls before the first Closing |
| 2026-10-23 | Assignment text added as `vault/project/task.md`; per-table analyses, `vault/project/sql/07_data_quality_findings.sql`, data dictionary, rewritten findings and `lightdash/` committed | The grading criteria (exploration, modelling, SQL efficiency, organisation) should sit next to the work that answers them | Plan re-read against the assignment: 11 funnel steps, column names, PR on the fork only, zip by email | Step 1 date, calls done-only vs all scheduled, Snowflake branch still open |
| 2026-10-22 | Business context (Enpal) and field documentation links added to each table file; `vault/project/data_dictionary.md`; lost reasons decoded with their labels and checked against the stages (3 new findings); Lightdash dashboard with one tab per table | The role needs governed, documented, machine-readable definitions; coded values only mean something once decoded | Each field checked against Pipedrive's API and support documentation (defined, mentioned only, or not documented); lost reasons compared with how far deals progressed | How is the lost reason entered, and why are 377 deals lost as Duplicate Entry although 274 reached Closing? |
| 2026-10-22 | `analyses/` restructured: one file per raw table (all columns, primary key, foreign keys, nulls, outliers, descriptive analytics) and one overall `vault/project/sql/07_data_quality_findings.sql` with all 25 findings; findings charted in the dashboard; skills updated | Per-table files keep the evidence for each table together; the overall file gives the business one list to react to | Declared keys compared with tested keys (4 given by the task, 2 identified); all foreign keys tested for nulls, orphans and parent uniqueness | Owner of the extraction (collisions in `activity_id`, unrelated `deal_id`) and of the lost reason semantics |
| 2026-10-22 | Analysis files regrouped (nulls and keys first, descriptive queries in one file); key tables added to `vault/project/findings.md`; skills updated (superseded by the per-table restructure above) | Every later query depends on grain and joinability; the keys the database declares were not the keys the data has | Declared constraints compared with tested keys: 4 declared primary keys, none on `activity` or `deal_changes`, no foreign key declared; `activity.deal_id` fails the inclusion test | Who owns the extraction and why `activity.deal_id` does not match (#4) |
| 2026-10-22 | First PR: EDA analyses, exploratory dbt probe tests, findings and model plan docs, handover notes, `.gitignore`, `target/` untracked. Pipedrive trial prepared in the UI: pipeline set to the 9 stages, activity types Sales Call 1 (renamed Meeting, key stays `meeting`), Sales Call 2, Follow Up Call, After Close Call, sample deals removed | The UI is where the process becomes visible; the account must match the data's vocabulary before a comparison means anything | Settings compared with the data: 9 stage names, 4 activity types. Deals and activities **not imported yet**, so no record-level cross-check done | #4 to #7 still need the CRM admin; open: Pipedrive has a separate Lost reasons setting, to compare with the lost reason options in `fields` |
| 2026-10-22 | Added this file; prepared the Pipedrive import files | Make the method explicit and get a UI to compare against | Trial account opened; import wizard inspected; nothing imported yet | #4 to #7 need the CRM admin |
