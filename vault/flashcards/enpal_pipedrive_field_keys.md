---
tags:
  - project/enpal
  - domain/pipedrive
  - type/flashcard
---

# Flashcards — Pipedrive field keys

---

What is `changed_field_key` in the Pipedrive export? #card
The technical key of the deal field that changed, taken from the deal flow or changelog. `new_value` is the value after the change; `fields.csv` maps each key to its display name and option list.

---

Map the four `changed_field_key` values to their Pipedrive field names. #card
`add_time` = Deal created (system, date), `user_id` = Owner (default, user), `stage_id` = Stage (default, stage), `lost_reason` = Lost reason (system, single option).

---

How do default and custom fields differ in their keys? #card
Default and system fields have readable keys (`stage_id`, `user_id`). Custom fields get an auto-generated hash key. In the flow API, custom field changes appear only with `all_changes=1`.

---

Where in the Pipedrive UI do you see the deal fields? #card
Settings, Data fields (`/settings/fields`): custom, default and system fields grouped by display name. The technical key is not shown there; get it from the deal fields API.

---

Which deal fields can the export not tell you about? #card
Status (open, won, lost), Pipeline, Title, Value, Probability, Expected close date, Won time and Lost time. That is why won and lost cannot be read from the export.
