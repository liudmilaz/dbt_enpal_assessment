---
tags:
  - project/enpal
  - domain/databases
  - domain/infrastructure
  - type/reference
---

# Postgres in a bigger company

Postgres is normally the **application database (OLTP)**, not the warehouse.

## Why it "crashes" under analytics
- Long scans on a row store compete with app inserts/updates for CPU, memory, I/O.
- One process per connection → hundreds of BI users/dbt threads exhaust the limit.
- Dead rows from updates/deletes bloat tables when `VACUUM` cannot keep up.
- Single writer → only vertical scaling.

## Roles at scale

| Role | How | Why |
|---|---|---|
| App backend | Managed: RDS, Aurora, Cloud SQL, AlloyDB, Azure | Backups, failover, patching handled |
| Read scaling | Read replicas | Offload reports; replica lag |
| Connections | PgBouncer / provider proxy | Many clients share few real connections |
| Big tables | Native partitioning | Queries and VACUUM touch only relevant partitions |
| Horizontal scale | Citus sharding, DB per service | Splits writes; more complexity |
| Warehouse source | CDC (Debezium, Fivetran, Datastream) → Snowflake/BigQuery | Analytics runs on columnar |
| Special workloads | PostGIS, pgvector, TimescaleDB | One DB instead of several |
| Tool metadata | Airflow, Lightdash, Metabase backends | Small and reliable |
| Operational data store | Curated warehouse results served with low latency | Warehouses are slow for single-row lookups |
| Light analytics | Citus columnar, AlloyDB columnar engine, `pg_duckdb` | Moderate analytics without a second platform |

## Typical architecture
```
App → Postgres (primary) ──replica──→ read-only services
         └── CDC ──→ Snowflake / BigQuery ──→ dbt ──→ BI
```
Hard part: the pipeline in the middle (deletes, late-arriving changes).

Interview line: "At 15k rows Postgres is enough. At production scale I treat it as the source and run the same dbt models on Snowflake or BigQuery."

See [[oltp_vs_olap_databases]].
