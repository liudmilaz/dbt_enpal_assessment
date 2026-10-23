---
tags:
  - project/enpal
  - tools/docker
  - tools/python
  - domain/infrastructure
  - type/reference
---

# Docker and environments

## What Docker is for
Docker runs software in isolated **containers**. An **image** is the frozen template (OS libraries + program + config); a **container** is a running copy. Here it provides a real Postgres without installing one on the Mac.

`docker-compose.yml` defines two services:
- `db`: Postgres; `init.sql` creates the tables on first start.
- `data_loader`: waits for the database, `\COPY`s the six CSVs, exits.

## Docker vs Python venv

| | Docker | venv |
|---|---|---|
| Isolates | Whole runtime: OS libs, services, ports | Python packages only |
| Role here | Database server (Postgres) | Client (dbt) |
| Start | `docker compose up -d` | `source ~/.venvs/enpal/bin/activate` |
| Reset | `docker compose down -v` | `rm -rf ~/.venvs/enpal` |
| Size | VM (Colima) + ~400 MB image | tens of MB |
| Holds data | Yes | No |

dbt (venv) sends SQL to Postgres (Docker) over `localhost:5432`. The venv lives outside Google Drive so Drive does not sync its thousands of files.

## Why not run Postgres natively?
1. Reviewers get the same environment (`docker compose up` is the task's instruction).
2. Setup is automated (tables + CSV load).
3. Cheap resets (`down -v`).
4. Nothing installed on the Mac; no port clashes.
5. Version pinned. Fix needed: the compose file uses `postgres:latest`; pin e.g. `postgres:16`.

Cost: VM layer, slower disk, one more thing that can break (Docker context: Colima vs Docker Desktop).

## Docker at scale
Docker is for dev, testing and CI, and for stateless work (dbt jobs, Airflow workers, APIs) on Kubernetes/Cloud Run. Production databases run as managed services, not self-managed containers.

## Manual steps

```bash
cd "~/GoogleDrive/career/code/dbt_enpal_assessment"
docker ps                      # is Docker running? if not: colima start
docker context use colima      # if the wrong context is active
docker compose up -d           # start (detached)
docker compose exec db psql -U admin -d postgres -c "select count(*) from activity"
docker compose stop            # pause, keep data
docker compose down -v         # remove containers AND data; next up reloads CSVs
```

Run Compose commands **inside the project folder**: `no configuration file provided: not found` means wrong folder (or use `-f <path>/docker-compose.yml`, or `docker exec <container-name> ...`).

Related: [[dbt_source_tests_and_loader_gotcha]] (never `up` twice on a loaded DB).
