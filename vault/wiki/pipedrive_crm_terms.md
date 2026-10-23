---
tags:
  - project/enpal
  - domain/pipedrive
  - domain/crm
  - type/reference
---

# Pipedrive CRM terms and how the export maps to them

Sources: [How Pipedrive data is organized](https://support.pipedrive.com/en/article/how-is-pipedrive-data-organized), [Deals API](https://developers.pipedrive.com/docs/api/v1/Deals), [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes). Where a point is my reading and not documentation it is marked *inference*.

## Terms

| Term | Meaning |
|---|---|
| **Lead** | Unqualified prospect in the Leads Inbox; becomes a deal once qualified. Here "Lead Generation" is stage 1 of a *deal*, not the Leads Inbox |
| **Deal** | Ongoing sales conversation with a person/organization/project; moves through pipeline stages until won or lost. API `status`: open, won, lost, deleted. The hub object |
| **Pipeline / stage** | Pipeline = a sales process; stages = ordered steps, each with a win probability and days-until-rotten. Export keeps only stage id + name |
| **Activity** | Scheduled action toward closing a sale (call, meeting, task, deadline, email, lunch); can link to a lead, deal, person, organization, project, or nothing |
| **Activity type** | Configurable; `key_string` generated from the name at creation, **cannot be changed**; activities reference it (`activity.type` = `activity_types.type`) |
| **Owner / assigned user** | Deal owner (`owner_id` in the API, can change); activity assigned user (`user_id`) |
| **Deal flow / changelog** | `GET /deals/{id}/flow` (updates; custom-field changes only with `all_changes=1`) and `GET /deals/{id}/changelog` (field value updates) |
| **Lost reason** | Can only be set when status = lost |
| **Person / organization** | Contacts; not in the export |
| **Rotten deal** | Deal with no update for the stage's days-to-rotten setting |
| **Product / project** | Catalogue items on deals / delivery work after won deals; not in the export |

## Export tables -> Pipedrive

| Table | Pipedrive object | Watch out |
|---|---|---|
| `deal_changes` | deal flow/changelog entry, one change per row | new value only, no old value, no actor; 4 field keys |
| `fields` | deal field definitions | has stage labels ("Qualified Lead") and lost-reason options; add_time is named "Deal created" |
| `stages` | stage | no pipeline/probability/rotten; "Qualified lead" casing differs |
| `activity` | activity | deal_id does not match deals; activity_id repeats for 11 ids; `due_to` = planned time, `done` = marked done |
| `activity_types` | activity type | `meeting` = Sales Call 1, `sc_2` = Sales Call 2; follow_up inactive; after_close_call not a funnel step |
| `users` | user | 4 shared emails; key on id |

## Not in the export
Deal status/close date, value/currency/products, pipeline, probability/rotten, persons/organizations/leads, change author and previous value, activity completion time.

## Consequences
- Moving a deal to any stage is normal Pipedrive behaviour (general product knowledge, not confirmed in the pages read) -> skipped stages and backward moves are not errors.
- A lost reason on every deal conflicts with "only set on lost deals" -> treat as end-of-lifecycle metadata, ask Enpal how it was produced.
- *Inference:* key `meeting` for Sales Call 1 suggests the built-in Meeting type was renamed; its key cannot change.

Related: [[02_data_findings]].

## Field keys (`changed_field_key`)

Every Pipedrive field has a display name and a key. Default and system fields have readable keys; custom fields get an auto-generated hash key. A deal's flow or changelog names the changed field by its key. In the export: `add_time` = "Deal created" (system, date), `user_id` = "Owner" (default, user), `stage_id` = "Stage" (default, stage), `lost_reason` = "Lost reason" (system, single option); `fields.csv` is the key-to-name lookup with option lists. UI: Settings, Data fields (`/settings/fields`) lists default, system and custom fields by display name (the technical key is not shown there; it comes from the deal fields API, not verified in the UI). Not tracked in the export: Status, Pipeline, Title, Value, Probability, Expected close date, Won time, Lost time.
