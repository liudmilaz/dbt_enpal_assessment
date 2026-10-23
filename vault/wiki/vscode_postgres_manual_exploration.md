---
tags:
  - project/enpal
  - tools/vscode
  - tools/postgres
  - domain/eda
  - type/how-to
---

# VS Code + Postgres: exploring the data manually

State of this Mac (2026-10-22): VS Code is installed; the `code` command and `psql` are **not** on the PATH. Postgres runs in Docker (`dbt_enpal_assessment-db-1`, `localhost:5432`, `admin`/`admin`, database `postgres`).

## 1. Put `code` on the PATH
VS Code: `Cmd + Shift + P` -> **Shell Command: Install 'code' command in PATH**. Then in a new terminal:
```bash
code "~/GoogleDrive/career/code/dbt_enpal_assessment"
```

## 2. Install a SQL client extension
```bash
code --install-extension mtxr.sqltools
code --install-extension mtxr.sqltools-driver-pg
```
(Alternative: Microsoft's *PostgreSQL* extension. SQLTools is the long-standing one.)
Useful extra: *Better Jinja* or *dbt Power User* for the dbt files later.

## 3. Add the connection
SQLTools icon in the sidebar -> **Add New Connection** -> PostgreSQL:

| Field | Value |
|---|---|
| Connection name | enpal_local |
| Server / Port | localhost / 5432 |
| Database | postgres |
| Username / Password | admin / admin (throwaway credential from the task) |

Or in the user settings JSON (not in the repo):
```json
"sqltools.connections": [{
  "name": "enpal_local", "driver": "PostgreSQL",
  "server": "localhost", "port": 5432,
  "database": "postgres", "username": "admin", "password": "admin"
}]
```
Click **Connect**. Docker must be running (`docker ps`), otherwise the connection is refused.

## 4. Run queries
- Open any file in `analyses/` (they use plain `public.<table>` names, so they run as they are).
- Select a statement -> `Cmd + E, Cmd + E` (Run selected query), or right-click -> *Run Selected Query*.
- Sidebar: expand the connection -> `public` -> tables; right-click a table -> **Show Table Records** / **Describe Table**.
- Results can be exported to CSV from the result tab.

## 5. psql in the container (no install needed)
```bash
docker exec -it dbt_enpal_assessment-db-1 psql -U admin -d postgres
```
| Command | What it does |
|---|---|
| `\dt` | list tables |
| `\d deal_changes` | columns, types, keys |
| `\x` | toggle expanded output |
| `\timing` | show query time |
| `\copy (select ...) to '/tmp/x.csv' csv header` | export |
| `\q` | quit |

## 6. Manual EDA routine (per table)
1. `select * from public.t limit 20;` look at it.
2. `select count(*), count(distinct key) ...` grain and uniqueness.
3. Nulls per column; `group by` on every categorical column.
4. `min/max` of every date; counts by month.
5. Key overlap between tables (left join, count matches).
6. Write down Question / Finding / Consequence in `analyses/NN_*.sql`.
For speed checks: `explain analyze <query>;` (this is the "SQL efficiency" part of the assessment).

## 7. dbt from the VS Code terminal
```bash
source ~/.venvs/enpal/bin/activate
export DBT_PROFILES_DIR=.
dbt debug
dbt run
```
Select the interpreter `~/.venvs/enpal/bin/python` (`Cmd + Shift + P` -> *Python: Select Interpreter*).

Never run `docker compose up` a second time on a loaded DB: see [[dbt_source_tests_and_loader_gotcha]].
