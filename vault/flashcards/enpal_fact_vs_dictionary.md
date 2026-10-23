---
tags:
  - project/enpal
  - domain/data-modelling
  - type/flashcard
---

# Flashcards — fact tables vs dictionary tables

---

How do you tell a fact table from a dictionary table? #card
A fact has one row per event or transaction, a timestamp, grows over time and refers to the dictionaries by key. A dictionary is a small reference table that decodes ids or codes into names, has one row per thing, no events, and is referenced by the facts.

---

Which Pipedrive export tables are facts, and why? #card
`deal_changes` (one row per change of a deal field, timestamp change_time, 15,406 rows) and `activity` (one row per scheduled activity, timestamp due_to, 4,579 rows).

---

Which export tables are dictionaries? #card
`activity_types` (key string to name), `stages` (stage id to name), `fields` (field key to display name plus option lists) and `users` (user id to name and email, master data with current state only).

---

What evidence confirms a dictionary? #card
Few rows, static content, no event timestamps, a unique key, and every row (or nearly every row) is referenced by a fact: 4 of 4 activity types, 9 of 9 stages, 4 of 4 field keys, 1,757 of 1,787 users.

---

Why is `users` a dictionary although it has 1,787 rows? #card
It is master data: one row per person, current state only (the modified column is the last change, there is no history), referenced by the facts. It is larger than a lookup but is not made of events.
