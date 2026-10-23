---
tags:
  - project/enpal
  - type/index
---

# Enpal take-home: project vault

The single place for the project documentation, the data quality findings and the learning notes. Source of truth: this vault in Google Drive (`Learning/enpal_assessment_vault`). The repo carries a copy in `vault/`, refreshed with `scripts/sync_vault.sh` before each push of the documentation PR.

## Project documentation (`project/`)

| Note | What it holds |
|---|---|
| [[task]] | The assignment as received |
| [[business_context]] | The company, the sale behind the data, KPI-to-data map, table relations, expectations vs data |
| [[crm_field_definitions]] | Every CRM field in business terms |
| [[data_dictionary]] | Fields with links to the Pipedrive documentation |
| [[findings]] | Exploratory findings per table and the data quality findings list |
| [[deal_history_and_questions_for_enpal]] | Deal 399956, stage skipping, backfill, questions for Enpal with SQL |
| [[model_plan]] | Intended layers, grains, metric definitions, tests |
| [[approach]] | How the work is done in a real setting, open questions register, change log |
| [[NOTES]] | Status, decisions, reminders, commands |

SQL kept with the documentation (`project/sql/`; in Obsidian enable Settings, Files and links, "Detect all file extensions" to see them):

- `07_data_quality_findings.sql`: one row per data quality check
- `08_business_questions.sql`: the funnel KPIs checked against business expectations
- `09_review_later.sql`: statistical checks and open questions to go through later

The per-table profiling queries (`analyses/01` to `06`) stay in the dbt repo, in the analysis PR.

## Learning notes

- `wiki/`: topic notes and the Q&A log, start at [[00_index]] and [[03_qa_log]]

Flashcards are not part of this vault.
