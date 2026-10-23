---
tags:
  - project/enpal
  - domain/databases
  - domain/snowflake
  - domain/bigquery
  - type/flashcard
---

# Flashcards — OLTP vs OLAP and database families

---

OLTP vs OLAP: what is the difference in workload? #card
OLTP serves applications: many small reads/writes of single rows ("update this order"). OLAP serves analytics: few queries that scan and aggregate millions of rows.

---

Row store vs columnar storage: why does it matter for analytics? #card
A row store keeps each row together (fast to fetch one record, slow to scan one column over a billion rows). A columnar store keeps each column together and compressed, so a query reading 3 of 100 columns touches about 3% of the data.

---

What does "separated storage and compute" mean (BigQuery, Snowflake)? #card
Data lives in cheap object storage; compute is rented per query or per warehouse. You can run many warehouses on the same data at once and scale them independently. Traditional databases couple both on one server, so you scale by buying a bigger machine.

---

Which of Postgres, MySQL, Oracle, SQL Server are columnar? #card
None by default — all are row stores built for OLTP. Oracle (in-memory/Exadata) and SQL Server (columnstore indexes) offer columnar options; Postgres has extensions (Citus columnar). BigQuery and Snowflake are columnar by design.

---

Tuning levers: Postgres vs BigQuery vs Snowflake? #card
Postgres: indexes, `EXPLAIN ANALYZE`, join order, vacuum. BigQuery: partitioning, clustering, bytes scanned. Snowflake: warehouse size, clustering, caching, micro-partition pruning.

---

Cost models: Postgres vs BigQuery vs Snowflake vs Oracle? #card
Postgres: free (you pay for hosting). BigQuery: per TB scanned or slots. Snowflake: credits per second of warehouse compute. Oracle: expensive licences.

---

Why does "SQL efficiency" look different on Postgres than on Snowflake? #card
On Postgres you create indexes and read query plans. On Snowflake there are no indexes: you reduce data scanned (pruning, selecting fewer columns) and choose warehouse size. Say which one you optimised for.

---

Which Snowflake architecture layers are exam topics (SnowPro Core)? #card
Storage (micro-partitions), compute (virtual warehouses), cloud services (metadata, optimisation, security). Plus pruning, caching and Time Travel.

---

Which databases has Liudmila used, and in which family? #card
MySQL (Doctari) and MS SQL Server (Prognoz): row-store OLTP engines with indexes. BigQuery (5+ years) and Snowflake: columnar cloud warehouses with separated compute.
