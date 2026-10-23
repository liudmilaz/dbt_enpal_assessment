---
tags:
  - project/enpal
  - domain/eda
  - domain/pipedrive
  - type/flashcard
---

# Flashcards — business context and field documentation

---

Why read about the company before the descriptive analysis? #card
Coded values and stages only mean something in the business process they record: Enpal sells household energy solutions in a long sales process, so the funnel is a core KPI, and a lost reason such as Duplicate Entry can be checked against the stages the deal reached.

---

What should a field description contain in the analysis files? #card
Only the fields the analysis needs, each with a one-line meaning, a link to the source system's own documentation and the status: defined, mentioned but not defined, not documented, or named differently by the system.

---

What did decoding the lost reasons show? #card
Five labels (Customer Not Ready, Pricing Issues, Unreachable Customer, Product Mismatch, Duplicate Entry) with the same average highest stage (6.4 to 6.7). 377 deals are lost as Duplicate Entry although 274 reached Closing; 411 of 422 Unreachable Customer deals reached Needs Assessment or later. The reason does not describe where a deal stopped.

---

Which Pipedrive documentation covers lost reasons? #card
The support article "Lost reasons": reasons are freeform or predefined by an admin (Company settings, Lost reasons), shown in the deal details, limit 100. The API field is `lost_reason` ("The reason for losing the deal", settable when the deal is lost).

---

Why is the export not representative of Enpal's scale? #card
It has 1,995 deals and 4,579 activities, while Enpal serves over 115,000 customers: read the data structure and quality issues from it, not business size or conversion rates.

---

How was the Lightdash dashboard built without clicking through the UI? #card
Through Lightdash's REST API: create a project (Postgres connection, dbt connection none, dbtVersion required), create saved SQL charts (table and bar configs) in a space, then a dashboard with tabs and tiles (markdown and sql_chart). The container reaches the Postgres through host.docker.internal.
