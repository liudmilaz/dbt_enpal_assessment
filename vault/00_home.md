---
tags:
  - project/enpal
  - type/index
---

# Enpal take-home: project vault

The project documentation for the handover, as text and Mermaid diagrams. Source of truth: this vault in Google Drive; the documentation PR carries the same files in `vault/`, kept in sync.

## Project documentation (`project/`)

| Note | What it holds |
|---|---|
| [[01_task]] | The assignment as received from Enpal |
| [[02_approach]] | The findings as assumptions to confirm with the stakeholders, the Pipedrive trial, the technical implementation |
| [[03_data_dictionary]] | Every raw field in business terms; the main metadata lives in dbt |
| [[04_business_context]] | The company, the assumed sale, the funnel KPIs and how each is counted, expectations against the data |
| [[05_data_quality_issues_and_assumptions]] | Every data quality issue per raw table: question, explanation and assumed origin, impact, proposed handling, dbt test |
| [[06_logical_model]] | Entities, keys and relationships in crow's foot notation, and the assumptions the model carries |

The SQL is in the repository: the dbt project and the data quality tests in `tests/data_quality/`.

Not part of the deliverable and not copied to the repository: `archive/` (working notes, earlier versions) and `wiki/` (learning notes).
