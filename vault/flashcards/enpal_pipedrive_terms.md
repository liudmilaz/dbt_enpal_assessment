---
tags:
  - project/enpal
  - domain/pipedrive
  - domain/crm
  - type/flashcard
---

# Flashcards — Pipedrive CRM terms

---

Lead vs deal in Pipedrive? #card
A lead is an unqualified prospect in the Leads Inbox; it becomes a deal once qualified. A deal is an ongoing sales conversation that moves through pipeline stages until won or lost. In this export "Lead Generation" is stage 1 of a deal.

---

What are the deal status values in the Pipedrive API? #card
`open`, `won`, `lost`, `deleted`. The export has no status column, so won/lost cannot be read directly.

---

What does a Pipedrive stage carry besides its name? #card
A deal probability and a days-until-rotten setting (and its pipeline). The export keeps only stage id and name, so the id order is the only funnel order.

---

What is an activity and what can it link to? #card
A scheduled action toward closing a sale (call, meeting, task, deadline, email, lunch). It can link to a lead, deal, person, organization, project, or nothing at all.

---

What is `key_string` of an activity type? #card
A key generated from the type's name at creation; it cannot be changed. Activities reference it, so `activity.type` matches `activity_types.type` (`meeting` = Sales Call 1, `sc_2` = Sales Call 2).

---

Which Pipedrive endpoints record deal field changes? #card
`GET /deals/{id}/flow` (updates; custom-field changes only with `all_changes=1`) and `GET /deals/{id}/changelog` (field value updates). `deal_changes` looks like such a log flattened to one row per change, with the new value only.

---

When can a lost reason be set? #card
Only when the deal status is lost. A lost reason on every deal (as in this export) therefore needs an explanation from the data owner; treat it as end-of-lifecycle metadata.

---

Why are skipped stages and backward moves not errors in Pipedrive data? #card
Users can move a deal to any stage, so non-sequential paths are normal behaviour (general product knowledge, not confirmed in the pages read).

---

What is missing from the export for a funnel analysis? #card
Deal status and close date, value/currency/products, pipeline, probability/rotten settings, persons/organizations/leads, who made a change and the previous value, and when an activity was completed.

---

What does `activity.due_to` mean versus `done`? #card
`due_to` is the planned time of the activity; `done` says it was marked done. Neither says when it actually happened.

---

What is an activity in business terms (Pipedrive, Enpal)? #card
A planned task of a sales rep: a call or meeting with a type, an owner, a linked deal, a due date and a done flag. A deal is the sales opportunity; activities are the work done to move it through the stages. Planned (due date) is not the same as held (done).
