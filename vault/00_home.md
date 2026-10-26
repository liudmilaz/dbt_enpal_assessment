---
tags:
  - project/enpal
  - type/index
---

# Enpal take-home: project vault

The project documentation, as text and Mermaid diagrams. Source of truth: this vault in Google Drive; the documentation PR carries the same files in `vault/`, kept in sync.

## Project documentation (`project/`)

| Note | What it holds |
|---|---|
| [[task]] | The assignment as received from Enpal |
| [[approach]] | The findings as assumptions to confirm with the stakeholders; the UI check in a Pipedrive trial; the technical implementation |
| [[business_context]] | The company, my assumption of the sale, the funnel KPIs and how each is counted, expectations against the data |
| [[data_dictionary]] | Every field: business meaning, Pipedrive documentation, caveats in this export |
| [[logical_model]] | Entities, keys and relationships in crow's foot notation (cardinality and ordinality), with measured counts |
| [[findings]] | Exploratory findings per raw table and the data quality checks |
| [[data_quality_issues]] | Per data quality issue: the query that lists the affected raw rows, the result, the business case (assumption) and the proposed fix |
| [[cleansing_proposals]] | Per data quality issue: logic, exploration, assumption, proposed handling, decisions |
| [[questions_for_enpal]] | Every assumption of the implementation as a question: data team (onboarding) and stakeholders (regular meetings), and how to organise the meetings |
| [[deal_history_and_questions_for_enpal]] | One deal's history, stage skipping, the backfill, and the questions for Enpal with SQL |

The SQL is in the repo: the main data quality issues `analyses/00_data_quality_issues.sql`, the per-table profiling `analyses/01` to `06`, and the dbt project.

Not part of the deliverable and not copied to the repo: `archive/` (working notes and plans) and `wiki/` (learning notes, start at [[00_index]] and [[03_qa_log]]).
