---
tags:
  - project/enpal
  - domain/eda
  - domain/dbt
  - domain/data-quality
  - type/flashcard
---

# Flashcards — dbt test probes during EDA

---

What is a dbt test probe? #card
A test written during exploration to check an assumption about a raw source. A failure is treated as a finding (not silenced); a pass is evidence. Confirmed probes are later promoted to permanent tests in staging.

---

Which command runs all source and singular tests and keeps the failing rows? #card
`dbt test --select "source:*" "test_type:singular" --store-failures`. The failing rows land in a `*_dbt_test__audit` schema you can query.

---

Phase 1 vs phase 2 of the probe workflow? #card
Phase 1, probe: many tests on the sources, run once, failures triaged. Phase 2, promote: keep the few that guard a real claim, move them to the staging YAML with a severity, delete the rest.

---

How do you test one key of a key-value event log? #card
Add `config: { where: "changed_field_key = 'x'" }` to the generic test (for example `accepted_values` on `new_value`, or `unique_combination_of_columns [deal_id]` to check one creation event per deal). Give repeated tests a unique `name:`.

---

Why does `relationships` fail to test a text column against an integer id? #card
It cannot cast; the types must match. Write a singular test with a cast (`left join parent on parent.id = child.value::int where parent.id is null`).

---

A YAML parse error appears on `to: source('a', 'b')` inside `{ ... }`. Why? #card
The comma inside the flow mapping ends the mapping. Use block style: `arguments:` then `to:` and `field:` on separate lines.

---

Two generic tests fail to compile with "name must be unique". Fix? #card
Give each a custom `name:` (dbt otherwise generates identical names when arguments match). Example: `unique_add_time_per_deal` and `unique_lost_reason_per_deal`.

---

What is an informational probe? #card
A test expected to fail, whose failure count is the finding (for example stage moves that are not exactly +1: 2,512 rows = 2,502 skips + 8 backward + 2 repeats). Do not promote it as an error.

---

How do you triage a failing probe? #card
Many rows on a key = keys unrelated or a wrong assumption (compare with chance overlap). Few rows = real defect, pull the rows and look for a shared cause. Expected = informational. Test wrong = fix and rerun.

---

First probe run on the Pipedrive sources: result? #card
44 tests, 37 pass, 7 fail: activity deal_id relationships (4,571), stage moves not +1 (2,512, informational), activity_id unique (11), users.email unique (4), two add_time per deal (5), two lost_reason per deal (5), lost_reason before last stage (4).

---

What did the probes show that profiling alone had missed? #card
That the same 5 two-lifecycle deals also carry two `lost_reason` events (2,000 events for 1,995 deals), and that a full-grain uniqueness test passes, proving there was no double load. Tests only find what you encode, so pair them with profiling.

---

When is a dbt test severity `warn` and when `error`? #card
`error` for defects caused by our own pipeline (double load, bad join). `warn` for known upstream defects we cannot fix (with a comment and the fix in staging) and for expected incomplete data (never deleted).
