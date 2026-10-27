---
tags:
  - project/enpal
  - type/definitions
---

# Data dictionary

> **Remark:** the most relevant metadata (the description of every source, model and column, keys, grain and tests) is stored in dbt: the YAML files next to the models and the model descriptions, published with `dbt docs`. This note is the business reading of the raw fields, kept for the handover.

Every field of the six raw tables of the Pipedrive CRM export: what it means for Enpal's sales process, the Pipedrive documentation that describes it, and the caveats found in this export. The reading of fields in Enpal's sale is an **interpretation, to confirm with Enpal**. Company and funnel: [[04_business_context]]; entities and relationships: [[06_logical_model]].

Documentation used (Pipedrive): [Deals API](https://developers.pipedrive.com/docs/api/v1/Deals), [Activities API](https://developers.pipedrive.com/docs/api/v1/Activities), [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes), [Stages API](https://developers.pipedrive.com/docs/api/v1/Stages), [Users API](https://developers.pipedrive.com/docs/api/v1/Users), [Deal fields API](https://developers.pipedrive.com/docs/api/v1/DealFields), support articles [Lost reasons](https://support.pipedrive.com/en/article/lost-reasons), [Customize pipeline stages](https://support.pipedrive.com/en/article/how-can-i-customize-my-pipeline-stages) and [How data is organized](https://support.pipedrive.com/en/article/how-is-pipedrive-data-organized). Where the official page does not define a field, the table says so; some response fields can only be confirmed from third-party references (marked unofficial).

## The objects

| Object | In business terms |
|---|---|
| **Deal** | One sales opportunity: one household (or business) that might buy or rent a solar system, battery, wallbox, heat pump or an electricity contract. There is no deals table in the export; a deal exists only through its history in `deal_changes`. |
| **Stage** | One step of the sales pipeline, from first interest to after-sales. The nine stages are funnel steps 1 to 9. |
| **Activity** | A task a sales rep plans to move a deal forward: a call, a consultation, a follow-up. Planned is not held: only `done` says it took place. |
| **Activity type** | The kind of task (Sales Call 1, Sales Call 2, Follow Up Call, After Close Call), set up by the CRM administrator. |
| **User** | A person working in the CRM: a sales rep, a lead qualifier, an after-sales agent. Users own deals and activities. |
| **Field** | The metadata of a deal field: its technical key, its display name and, for list fields, the allowed values. |

## deal_changes (fact): one change of one field of one deal

The deal's history as the CRM records it (the changelog).

| Column | Business meaning | Documentation | Caveats in this export |
|---|---|---|---|
| `deal_id` | The sales opportunity the change belongs to. | [Deals API: changelog](https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog): documented as the path parameter | 5 deals hold two lifecycles (two creations, two lost reasons), consistent with a duplicate lead merged into one deal (D3). |
| `change_time` | When the change was made in the CRM. | changelog `time`: not defined on the official page | Every change has the deal's creation time of day: use the date of a change, not its time (D5). |
| `changed_field_key` | Which property of the deal changed (the four keys below). | changelog `field_key`: response fields not defined; unofficial: [list updates about deal field values](https://developers.qodex.ai/pipedrive-api-collection/pipedrive-api-v1-2/deals-6/list-updates-about-deal-field-values-1) | Only four of the many deal fields are in the export. |
| `new_value` | The value after the change; its meaning depends on the key. | only third-party references list `new_value` | No old value, no author of the change; four types in one text column; typed per key in staging, the format is tested there. |

The four kinds of change (`changed_field_key`):

| Key | Display name | Business event | `new_value` holds | Documentation |
|---|---|---|---|---|
| `add_time` | Deal created | A lead became a deal: the household showed interest (web form, call, partner). | the creation timestamp | [Deals API: get all deals](https://developers.pipedrive.com/docs/api/v1/Deals#getDeals): only a sort field, not defined |
| `user_id` | Owner | The deal was assigned or re-assigned to a person (lead routing, hand-over); a median 15 days after creation, always before stage 1. | the user id of the new owner | [Deals API: add a deal](https://developers.pipedrive.com/docs/api/v1/Deals#addDeal): documented as `owner_id` |
| `stage_id` | Stage | The deal moved to a pipeline stage; the funnel counts each deal once per stage it reached, in the month the deal was created. | the stage id (1 to 9) | [Deals API: add a deal](https://developers.pipedrive.com/docs/api/v1/Deals#addDeal): documented |
| `lost_reason` | Lost reason | The deal was closed as lost, with the reason the rep chose from the admin's list. | the reason id (1 to 5) | [Support: Lost reasons](https://support.pipedrive.com/en/article/lost-reasons): documented |

## activity (fact): one planned activity

| Column | Business meaning | Documentation | Caveats in this export |
|---|---|---|---|
| `activity_id` | The activity's id in the CRM; meant to be unique. | [Activities API: get an activity](https://developers.pipedrive.com/docs/api/v1/Activities#getActivity): documented | 11 ids repeat for unrelated activities (A1). |
| `type` | The kind of activity, by its key string (see activity types). | [Activities API: add an activity](https://developers.pipedrive.com/docs/api/v1/Activities#addActivity): documented | |
| `assigned_to_user` | The person responsible for doing it. | documented as `owner_id`; `assigned_to_user` is the export's name | |
| `deal_id` | The sales opportunity it is for. | documented | Only 8 of 4,579 match a deal in `deal_changes` (A2). |
| `done` | Whether the rep marked it as done, i.e. it took place. | documented: "Whether the activity is marked as done or not" | Every type is about 50% done, although all are due before the export ends (A4). |
| `due_to` | When it is planned (date and time). | documented as two fields, `due_date` and `due_time`; the export merges them | Planned, not held; the export ends earlier than the deal history (X1). |

## activity_types (dictionary)

| Column | Business meaning | Documentation |
|---|---|---|
| `id` | Technical id of the type; nothing references it. | [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes): documented as a path parameter |
| `name` | The name users see (Sales Call 1, ...). | documented as a body parameter |
| `type` | The key string activities refer to; generated from the name at creation and never changed. | documented (`key_string`) |
| `active` | Whether reps can still choose the type for new activities (text `Yes` / `No`); old activities keep an inactive type (T1). | `active_flag` is not described on the official page; seen in Settings of the trial account |

The four types in Enpal's sale (interpretation, to confirm with Enpal):

| Key | Name | Business meaning | Funnel step |
|---|---|---|---|
| `meeting` | Sales Call 1 | First consultation with the household. | 2.1 |
| `sc_2` | Sales Call 2 | Second consultation, around the offer. | 3.1 |
| `follow_up` | Follow Up Call | A chase or reminder call between steps (inactive type). | none |
| `after_close_call` | After Close Call | A call after the contract: installation, onboarding, satisfaction. | none |

## stages (dictionary)

| Column | Business meaning | Documentation |
|---|---|---|
| `stage_id` | The position of the step in the pipeline (1 = first); the order of the ids is the order of the funnel. | [Stages API](https://developers.pipedrive.com/docs/api/v1/Stages): documented |
| `stage_name` | The step's name as the sales team sees it, set by the CRM admin. | [Support: customize pipeline stages](https://support.pipedrive.com/en/article/how-can-i-customize-my-pipeline-stages): documented |

Not in the export: stage order (`order_nr`), win probability (`deal_probability`) and rotting settings. One name is spelled differently from its label in `fields` (S1).

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

## fields (dictionary, metadata)

| Column | Business meaning | Documentation |
|---|---|---|
| `id` | The field's id in the export; nothing references it. | not defined on the official page |
| `field_key` | The technical name of the deal property, used in the change log (`stage_id`, `lost_reason`, ...). | [Deal fields API](https://developers.pipedrive.com/docs/api/v1/DealFields): keys mentioned, not defined |
| `name` | The label users see in the CRM (Stage, Owner, Deal created, Lost reason). | documented (`field_name`) |
| `field_value_options` | For list fields, the allowed values and their labels: the stage labels and the lost reasons; empty for the others. | documented for single-option fields |

The lost reasons (`field_value_options` of `lost_reason`):

| Id | Reason | Business meaning |
|---|---|---|
| 1 | Customer Not Ready | The household is interested but not now (timing, decision pending). |
| 2 | Pricing Issues | The price or the financing did not work for the customer. |
| 3 | Unreachable Customer | The customer stopped answering. |
| 4 | Product Mismatch | The product does not fit (roof, house, consumption, region). |
| 5 | Duplicate Entry | The deal is a duplicate of another deal for the same customer and was closed (DUP-6). |

Every deal carries a lost reason, also deals that reached Renewal/Expansion, and each reason is spread evenly over all stages: in this export the lost reason is a closure label, not an outcome (D4).

## users (dictionary, master data)

Current state only: no history of names or emails.

| Column | Business meaning | Documentation | Caveats in this export |
|---|---|---|---|
| `id` | The person's id; referenced as deal owner and activity assignee. | [Users API](https://developers.pipedrive.com/docs/api/v1/Users): documented | 1,347 owners for 1,995 deals (median 2 each): not the shape of a real sales team (U2). |
| `name` | The person's name; shared by different users. | documented | |
| `email` | The person's login email. | documented | Shared by two users in a few cases: never join on email (U1). |
| `modified` | The last change of the user record. | not documented on the official page | An edit time, not an export cut-off. |
