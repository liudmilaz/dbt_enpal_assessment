---
tags:
  - project/enpal
  - tools/vscode
  - tools/postgres
  - type/flashcard
---

# Flashcards — VS Code and Postgres exploration

---

How do you make the `code` command available in the terminal? #card
In VS Code: `Cmd + Shift + P` -> "Shell Command: Install 'code' command in PATH". Then `code <folder>` opens a project and `code --install-extension <id>` installs extensions.

---

Which VS Code extensions give you a SQL client for Postgres? #card
SQLTools (`mtxr.sqltools`) plus the PostgreSQL driver (`mtxr.sqltools-driver-pg`). Microsoft's "PostgreSQL" extension is an alternative.

---

Connection settings for the Enpal Postgres in Docker? #card
Server `localhost`, port `5432`, database `postgres`, user `admin`, password `admin`. Docker must be running; otherwise the connection is refused.

---

How do you run a single statement in SQLTools? #card
Select it and press `Cmd + E, Cmd + E` (or right-click -> Run Selected Query). Right-click a table for Show Table Records / Describe Table.

---

How do you open psql when it is not installed on the Mac? #card
Run it inside the container: `docker exec -it dbt_enpal_assessment-db-1 psql -U admin -d postgres`.

---

Name five useful psql meta-commands. #card
`\dt` list tables, `\d table` describe columns, `\x` expanded output, `\timing` show query time, `\copy (query) to 'file.csv' csv header` export, `\q` quit.

---

What does `explain analyze` give you and why use it in the assessment? #card
The executed plan with real timings and row counts (scans, joins, indexes used). It is the evidence for the "SQL code efficiency" criterion on Postgres.

---

What is the manual EDA routine per table? #card
Look at 20 rows; count rows and distinct keys (grain); nulls and group-bys per categorical column; min/max and monthly counts of every date; key overlap with other tables; write Question / Finding / Consequence.

---

How do you run dbt from the VS Code terminal with the project profile? #card
`source ~/.venvs/enpal/bin/activate`, `export DBT_PROFILES_DIR=.`, then `dbt debug` and `dbt run`. The project's `profiles.yml` sits in the repo root.
