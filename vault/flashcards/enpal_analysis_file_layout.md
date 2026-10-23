---
tags:
  - project/enpal
  - domain/eda
  - type/flashcard
---

# Flashcards — layout of the analysis files

---

How are the EDA analysis files organised? #card
One file per raw table (facts first, then dictionaries), each with the same six sections, plus one overall data-quality findings file listed last.

---

What are the six sections of a per-table analysis file? #card
1 all columns, 2 primary key (given or identified, unique, not null), 3 foreign keys (nulls, matches, orphans, parent unique), 4 nulls and not nulls, 5 outliers, 6 descriptive analytics.

---

What does the overall findings file contain? #card
One result row per data-quality check: table, class (record, field, referential, business logic, coverage), finding, violations, proposed severity (error, warn, info), result (pass, flag, info) and the section of the per-table file with the detail query.

---

Where do cross-table analyses go in the per-table layout? #card
In the file of the table that holds the foreign key (the child), for example the activity-to-deal overlap in the activity file.

---

What do error, warn and info mean as proposed test severities? #card
Error: our own pipeline would be wrong (double load, bad join). Warn: a known upstream defect that is fixed in staging and kept visible. Info: documented, expected or descriptive, not an error.
