---
tags:
  - project/enpal
  - type/definitions
---

# CRM field definitions in business terms

What every field of the Pipedrive export means for Enpal's sales process, in plain words. For the technical side (Pipedrive documentation links, whether a field is documented) see [[data_dictionary]]; for the company and the funnel see [[business_context]]. The reading of fields in Enpal's sale is an **interpretation, to confirm with Enpal** where marked.

## The objects

| Object | In business terms |
|---|---|
| **Deal** | One sales opportunity: one household (or business) that might buy or rent a solar system, battery, wallbox, heat pump or an electricity contract. A deal moves through the stages of the sales pipeline until it is won or lost. There is no deals table in the export; a deal exists only through its history in `deal_changes`. |
| **Stage** | One step of the sales pipeline, from first interest to after-sales. The nine stages are the funnel steps of the report. |
| **Activity** | A task a sales rep plans to move a deal forward: a call, a consultation, a follow-up. Planned is not held: only `done` says it took place. |
| **Activity type** | The kind of task (Sales Call 1, Sales Call 2, Follow Up Call, After Close Call), set up by the CRM administrator. |
| **User** | A person working in the CRM: a sales rep, a lead qualifier, an after-sales agent. Users own deals and activities. |
| **Field** | The metadata of a deal field: its technical key, its display name and, for list fields, the allowed values. |

## deal_changes: the history of each deal

One row = one change of one field of one deal, the way the CRM records it in the deal's history (the "changelog").

| Field | Business meaning | Caveats in this export |
|---|---|---|
| `deal_id` | The sales opportunity the change belongs to. | 5 deals hold two lifecycles (two creations, two lost reasons), consistent with a duplicate lead merged into one deal. |
| `change_time` | When the change was made in the CRM. | Every change has the deal's creation time of day (99.8%): the dates are creation + whole days, so the timing looks generated. |
| `changed_field_key` | Which property of the deal changed: see the four keys below. | Only four of the many deal fields are in the export. |
| `new_value` | The value after the change. Its meaning depends on the key. | No old value, no author of the change. |

The four kinds of change (`changed_field_key`):

| Key | Display name in the CRM | Business event | `new_value` holds |
|---|---|---|---|
| `add_time` | Deal created | A lead became a deal: the household showed interest (web form, call, partner). | The creation timestamp |
| `user_id` | Owner | The deal was assigned or re-assigned to a person (lead routing, hand-over). Owner comes a median 15 days after creation, always before stage 1. | The user id of the new owner |
| `stage_id` | Stage | The deal moved to a pipeline stage. The first entry into a stage is what the funnel report counts. | The stage id (1 to 9) |
| `lost_reason` | Lost reason | The deal was closed as lost, with the reason the rep chose. | The reason id (1 to 5) |

## stages: the sales pipeline

| Field | Business meaning |
|---|---|
| `stage_id` | The position of the step in the pipeline (1 = first). The order of the ids is the order of the funnel. |
| `stage_name` | The step's name as the sales team sees it. |

The nine stages in Enpal's sale (interpretation, to confirm with Enpal):

| Id | Stage | What happens with the customer |
|---|---|---|
| 1 | Lead Generation | A household shows interest and enters the pipeline. |
| 2 | Qualified Lead | The lead fits a product (own roof, region, budget) and is worth a consultation. |
| 3 | Needs Assessment | Roof, consumption and budget are assessed (remote or on site). |
| 4 | Proposal/Quote Preparation | A system is designed and an offer prepared (rental or purchase). |
| 5 | Negotiation | The offer is discussed and adjusted. |
| 6 | Closing | The contract is signed. |
| 7 | Implementation/Onboarding | Installation and grid connection; the customer is onboarded. |
| 8 | Follow-up/Customer Success | After-sales care and service. |
| 9 | Renewal/Expansion | Add-ons: battery, wallbox, heat pump, electricity contract. |

Caveat: 84% of deals skip at least one stage in the CRM, and 683 of 1,081 deals in stages 7 to 9 never recorded Closing, so the stages describe where reps moved the deal, not every step the customer went through.

## fields: the deal field metadata

| Field | Business meaning |
|---|---|
| `id` | Technical id of the field definition. |
| `field_key` | The technical name of the deal property, used in the change log (`stage_id`, `lost_reason`, ...). |
| `name` | The label users see in the CRM (Stage, Owner, Deal created, Lost reason). |
| `field_value_options` | For list fields, the allowed values and their labels: the stage names and the lost reasons. Empty for fields without a list (owner, creation date). |

The lost reasons (`field_value_options` of `lost_reason`):

| Id | Reason | Business meaning | Caveat |
|---|---|---|---|
| 1 | Customer Not Ready | The household is interested but not now (timing, decision pending). | Each reason covers ~400 deals and is spread evenly over all stages. |
| 2 | Pricing Issues | The price or the financing did not work for the customer. | |
| 3 | Unreachable Customer | The customer stopped answering. | 411 of 422 reached Needs Assessment or later, so they were reachable for a while. |
| 4 | Product Mismatch | The product does not fit (roof, house, consumption, region). | |
| 5 | Duplicate Entry | The deal is a duplicate of another deal for the same customer and was closed. | 274 of 377 reached Closing: duplicates are not caught early. |

## activity: planned work on deals

One row = one planned activity.

| Field | Business meaning | Caveats in this export |
|---|---|---|
| `activity_id` | The activity's id in the CRM; meant to be unique. | 11 ids repeat for unrelated activities: duplicates, a data quality issue (decided; review by the business stakeholder). |
| `type` | The kind of activity, by its technical key (see activity types). | |
| `assigned_to_user` | The person responsible for doing it. | |
| `deal_id` | The sales opportunity it is for. | Only 8 of 4,579 match a deal in `deal_changes`: activities cannot be tied to the funnel deals. |
| `done` | Whether the rep marked it as done, i.e. it took place. | Every type is ~50% done, although all are due before the export ends. |
| `due_to` | When it is planned (date and time). | Planned, not held; ends 2024-09-13. |

## activity_types: the kinds of activity

| Field | Business meaning |
|---|---|
| `id` | Technical id of the type. |
| `name` | The name users see (Sales Call 1, ...). |
| `type` | The technical key activities refer to; fixed when the type is created. |
| `active` | Whether reps can still choose the type for new activities (text `Yes` / `No`); old activities keep an inactive type. |

The four types in Enpal's sale (interpretation, to confirm with Enpal):

| Key | Name | Business meaning | Funnel step |
|---|---|---|---|
| `meeting` | Sales Call 1 | First consultation with the household. | 2.1 |
| `sc_2` | Sales Call 2 | Second consultation, around the offer. | 3.1 |
| `follow_up` | Follow Up Call | A chase or reminder call between steps (inactive type). | none |
| `after_close_call` | After Close Call | A call after the contract: installation, onboarding, satisfaction. | none |

Caveat: 157 After Close Calls are due before the first deal reached Closing (2024-02-02).

## users: the people in the CRM

Current state only: no history of names or emails.

| Field | Business meaning | Caveats in this export |
|---|---|---|
| `id` | The person's id; referenced as deal owner and activity assignee. | 1,347 owners for 1,995 deals (median 2 deals each): not the shape of a real sales team. |
| `name` | The person's name. | |
| `email` | The person's login email. | 4 emails are shared by 2 users each: never join on email. |
| `modified` | The last change of the user record. | Runs to 2024-10-28, after the last activity: the tables were exported at different times. |
