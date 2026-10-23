---
tags:
  - project/enpal
  - type/index
---

# Enpal take-home: project vault

The single place for the project documentation, the data quality findings and the learning notes. Source of truth: this vault in Google Drive (`Learning/enpal_assessment_vault`). The repo carries a copy of the text files in `vault/` (documentation PR), refreshed with `scripts/sync_vault.sh`.

## Project documentation (`project/`)

| Note | What it holds |
|---|---|
| [[task]] | The assignment as received |
| [[business_context]] | The company, table relations, expectations vs data, what the export cannot answer |
| [[sales_funnel_assumptions]] | My assumption of how a deal goes through Enpal's sale: process, funnel diagram, KPI-to-data map |
| [[crm_field_definitions]] | Every CRM field in business terms |
| [[data_dictionary]] | Fields with links to the Pipedrive documentation |
| [[findings]] | Exploratory findings per table and the data quality findings list |
| [[deal_history_and_questions_for_enpal]] | Deal 399956, stage skipping, backfill, questions for Enpal with SQL |
| [[logical_model]] | Business entities, keys and relationships (1 to 1, 1 to many) with measured cardinalities, Mermaid diagram |
| [[model_plan]] | Intended layers, grains, metric definitions, tests |
| [[elementary_rollout]] | Data quality tests and monitoring with Elementary: issue-to-test map, phases, who does what |
| [[approach]] | Why compare with the UI and talk to stakeholders; how the Pipedrive trial account was set up |
| [[NOTES]] | Status, decisions, open questions register, reminders, commands |

This vault holds text and diagrams only. The SQL is in the repo:
- in the solution PR: the main data quality issues per table `analyses/00_data_quality_issues.sql`, the per-table profiling `analyses/01` to `06`, and the dbt solution;
- local only (gitignored): the full data quality checks `07`, the business questions `08`, the checks to revisit `09`.

## Learning notes

- `wiki/`: topic notes and the Q&A log, start at [[00_index]] and [[03_qa_log]]. Kept in the Drive vault only, not copied to the repo.

Flashcards are not part of this vault.
