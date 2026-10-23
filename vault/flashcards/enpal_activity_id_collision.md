---
tags:
  - project/enpal
  - domain/data-quality
  - domain/pipedrive
  - type/flashcard
---

# Flashcards — repeated ids: duplicate or collision?

---

How do you tell a true duplicate from an id collision? #card
Compare the other attributes of the rows sharing the id. A true duplicate repeats the same entity (same deal, user, time). A collision joins unrelated entities: different deal, user, type and date, as in the 11 repeated `activity_id`s (e.g. 521731).

---

How many chance collisions does the birthday formula predict for n ids drawn from N values? #card
About n(n-1)/(2N). For 4,579 activity ids from a 900,000-wide range that is about 11.6; 11 were observed, so the repeats are consistent with randomly generated ids.

---

Why is a repeated `activity_id` a pipeline or export issue and not a business issue in Pipedrive? #card
Pipedrive ids are unique within an account, so two different activities cannot legitimately carry the same id. If both exist in the UI under different ids, the shared id came from the extraction or from generated data (to confirm with the data owner).

---

Where in the Pipedrive UI can you see activity and deal ids? #card
Activities list -> Customize columns (gear icon) -> search "ID": options include ID (Activity), ID (Deal), ID (Person), ID (Organization). Custom fields such as "Source deal id" can be added the same way.

---

How do you verify a suspected duplicate against the source system? #card
Open both deals, check their Activities and the deal History for the two activities (type, user, due date, done), and compare with the data rows. Both exist as separate activities -> the shared id is an export artifact; one missing -> deleted or merged record (check Restore data and Merge duplicates).
