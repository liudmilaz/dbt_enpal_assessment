---
tags:
  - project/enpal
  - domain/databases
  - domain/snowflake
  - domain/bigquery
  - type/reference
---

# OLTP vs OLAP — and where each database sits

## Four axes
1. **Workload:** OLTP = many small reads/writes of single rows (apps). OLAP = few queries scanning and aggregating millions of rows.
2. **Storage:** row store keeps a row together (fast single-record fetch); columnar keeps each column together and compressed (reads only the columns queried).
3. **Compute/storage:** traditional = coupled on one server (scale up); BigQuery/Snowflake = separated (storage in object storage, compute rented per query).
4. **Operations:** self-managed (indexes, vacuum, hardware) vs cloud warehouse (mostly SQL; pay per bytes scanned or per warehouse-second).

## Comparison

| | Postgres | MySQL | Oracle | SQL Server | BigQuery | Snowflake |
|---|---|---|---|---|---|---|
| Type | OLTP (some analytics) | OLTP | OLTP + enterprise DWH | OLTP + DWH | OLAP | OLAP |
| Storage | Row | Row | Row (columnar option) | Row (columnstore option) | Columnar | Columnar |
| Compute/storage | Coupled | Coupled | Coupled (Exadata, RAC) | Coupled | Separated, serverless | Separated, warehouses |
| Scaling | Vertical, replicas | Vertical, replicas | Vertical, RAC | Vertical, availability groups | Automatic | Resize / add warehouses |
| Tuning | Indexes, `EXPLAIN` | Indexes | Indexes, hints, partitions | Indexes, statistics | Partition, cluster, bytes scanned | Warehouse size, clustering, caching |
| Cost | Free | Free / paid | Expensive licences | Licences | Per TB or slots | Credits per compute time |

Experience: MySQL (Doctari), MS SQL Server (Prognoz), BigQuery (5+ yrs), Snowflake (growing).

## For the Enpal task
- Postgres has no warehouse features, so "SQL efficiency" means `EXPLAIN ANALYZE`, indexes, join order. On BigQuery/Snowflake you reduce bytes scanned / pick warehouse size instead.
- Use `dbt.date_trunc` / `dbt.datediff` so models port to Snowflake.
- Exam link (SnowPro Core): three layers (storage, compute, cloud services), micro-partitions.

See [[postgres_at_scale]].
