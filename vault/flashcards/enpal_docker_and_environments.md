---
tags:
  - project/enpal
  - tools/docker
  - tools/python
  - type/flashcard
---

# Flashcards — Docker and environments

---

What is the difference between a Docker image and a container? #card
An image is the frozen template (OS libraries, program, config). A container is a running copy of an image. You can start many containers from one image.

---

What does `docker-compose.yml` do in the Enpal project? #card
It defines two services: `db` (Postgres, tables created by `init.sql`) and `data_loader` (waits for the DB, `\COPY`s the six CSVs, then exits). One `docker compose up` gives every reviewer the same populated database.

---

Docker vs Python venv: what does each isolate? #card
Docker isolates the whole runtime (OS libraries, services, ports) — here it runs the Postgres server. A venv isolates Python packages only — here it holds dbt. dbt (venv) is the client; Postgres (Docker) is the server, connected over `localhost:5432`.

---

Why is the dbt venv kept outside Google Drive (`~/.venvs/enpal`)? #card
A venv contains thousands of small files that Drive would sync, and venvs break when moved (absolute paths in scripts). Recreate it instead of moving it.

---

Give four reasons to run Postgres in Docker instead of natively for a take-home. #card
Reviewers get the identical environment; setup (tables + CSV load) is automated; a reset is one command (`down -v`); nothing is installed on the host and no port clashes. Also the version can be pinned via the image tag.

---

What is wrong with `image: postgres:latest` in the compose file? #card
It is not pinned: a future major release can change behaviour (planner, `jsonb` handling) and break the project. Pin a tag such as `postgres:16`.

---

Where is Docker used at scale, and where is it not? #card
Used for dev, testing, CI (throwaway Postgres per run) and stateless workloads (dbt jobs, Airflow workers, APIs) on Kubernetes/Cloud Run. Production databases run as managed services (RDS, Cloud SQL, Snowflake), not as self-managed containers.

---

Error: `no configuration file provided: not found`. Cause and fix? #card
`docker compose` looks for `docker-compose.yml` in the current directory. You are in the wrong folder (e.g. `~`). `cd` into the project, or use `-f <path>/docker-compose.yml`, or `docker exec <container-name> ...`.

---

What do `docker compose stop`, `down` and `down -v` do? #card
`stop` pauses containers and keeps everything. `down` removes the containers and network. `down -v` also removes the data volume, so the next `up` reloads the CSVs from scratch.

---

How do you check Docker is running, and what if it is not? #card
`docker ps` prints a table header (even if empty) when the daemon is reachable. On this Mac Docker runs via Colima: `colima start`, and `docker context use colima` if the wrong context (Docker Desktop) is active.
