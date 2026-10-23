---
tags:
  - project/enpal
  - domain/eda
  - domain/sql
  - domain/data-modelling
  - type/flashcard
---

# Flashcards — nulls and primary / foreign keys in EDA

---

Which two analysis files come first in an EDA, and why? #card
Nulls per column, then primary and foreign keys. Every later query depends on knowing the grain of each table and what can be joined to what.

---

How do you count NULLs for every column of a table without naming the columns (Postgres)? #card
`select key, count(*), count(*) filter (where value = 'null'::jsonb) from t, jsonb_each(to_jsonb(t)) group by key`. Also count blanks with `value = '""'::jsonb`. Snowflake: flatten `object_construct_keep_null(*)` and use `is_null_value`.

---

Three meanings of a NULL to decide for each column? #card
Not applicable (a field with no value by design, e.g. no option list on a field type without options), not yet happened (an end date on an open record), or missing (a defect). Only the last is a data-quality problem; none is fixed silently.

---

Why count blank strings as well as NULLs? #card
A CSV load turns missing text into `''`, not NULL, so a NULL-only check misses it.

---

How do you test whether a column or column set is a primary key? #card
Rows equal distinct values and there are no NULLs: `count(*) = count(distinct id)` and `count(*) - count(id) = 0`. For a composite key use `count(distinct (a, b, c))` (Postgres tuple).

---

Declared constraints vs real keys: which do you trust? #card
Neither alone. Declared constraints are often missing or not enforced (Snowflake, BigQuery), so test the candidates and report both. In this data only 4 of 6 tables declare a primary key and none declares a foreign key.

---

What is an alternate key and why does it matter for foreign keys? #card
A second unique column (a code string next to a numeric id). Other tables often reference the alternate key: `activity.type` references `activity_types.type`, not its primary key `id`; `deal_changes.changed_field_key` references `fields.field_key`, not `fields.id`.

---

How do you test a foreign key candidate? #card
Inclusion test: left join child to the parent's distinct key and count matches and orphans. 100% matched means a usable foreign key; near the chance overlap of two id ranges means unrelated keys (`activity.deal_id`: 8 of 4,579).

---

Why is name matching not enough to find foreign keys? #card
It misses keys with different names (`assigned_to_user` to `users.id`) and flags look-alike names (`name`). Use it as a start, then confirm with the inclusion test and test pairs of matching types.

---

What is a conditional foreign key in a key-value event log? #card
One value column references different parents depending on a key column: `new_value` is a user id when the key is `user_id`, a stage id when `stage_id`, a lost-reason option when `lost_reason`. Test each condition separately.

---

Why is `deal_id` not a primary key in `deal_changes`? #card
It repeats once per event (7.7 events per deal) and there is no deals table. The table key is composite (`deal_id`, `changed_field_key`, `change_time`); the deal is an implicit entity to name in the docs.

---

What do you state for the primary keys in the keys analysis? #card
One primary key per table, with a comment saying whether it was given by the task (declared in the schema) or identified by testing, and a unique and not-null check (rows = distinct, zero nulls). Not every candidate key.

---

What do you show for each foreign key? #card
Child rows, null count of the child column, matches, orphans, and whether the parent column is unique. It holds when every non-null value matches and the parent is unique; only foreign keys that exist are listed. The result drives `relationships` tests.

---

A column `<table>_id` has a few duplicates. What is the process? #card
Assume a data quality issue when the share is low; prove it (distinct values of other columns per duplicate group, composite candidates `(id, col)`, chance collisions `n(n-1)/2 / range`); write the conclusion; then ask the owner to categorize: data quality (which cleansing) or a data entry / export process to identify first.

---

How do you tell exact copies from id collisions in a duplicate group? #card
Count distinct values of every other column per group: all 1 = exact copies (double load, drop one); 2 in user, deal and date = unrelated records sharing an id (collision, keep both under a surrogate key or ask).

---

Why is (activity_id, assigned_to_user) unique but still not the key? #card
It is unique only because the two activities in each pair are unrelated. A Pipedrive activity id is global, not per user, so the combination has no business meaning; and (activity_id, type) still repeats.
