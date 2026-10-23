---
tags:
  - project/enpal
  - domain/databases
  - domain/infrastructure
  - type/flashcard
---

# Flashcards — Postgres at scale and low-cost data stacks

---

What is Postgres usually used for in a larger company? #card
The application database (OLTP) behind products and services, run as a managed service (RDS, Aurora, Cloud SQL, AlloyDB), with read replicas and connection pooling. Analytics is moved to a warehouse via CDC.

---

Why does Postgres "crash" when used for analytics? #card
Long scans on a row store compete with app writes for CPU/memory/I/O; one process per connection exhausts the connection limit with many BI users; dead rows bloat tables when VACUUM cannot keep up; a single writer allows only vertical scaling.

---

What is PgBouncer for? #card
A connection pooler in front of Postgres. Many clients share a few real connections, avoiding the per-connection process cost.

---

Read replica: benefit and caveat? #card
Offloads reporting reads from the primary. Caveat: replication lag — data on the replica is slightly behind.

---

Native partitioning in Postgres: why use it? #card
Large tables are split by date or tenant; queries and VACUUM only touch relevant partitions.

---

What is CDC and why is it used between Postgres and Snowflake? #card
Change Data Capture streams row changes (inserts/updates/deletes) from the Postgres log (Debezium, Fivetran, Datastream) into the warehouse. Analytics runs on columnar storage instead of the app database. Hard parts: deletes and late-arriving changes.

---

Name three Postgres extensions and their use. #card
PostGIS (geospatial), pgvector (embeddings/vector search), TimescaleDB (time series).

---

Typical architecture: app database to BI? #card
App → Postgres (primary) → CDC → Snowflake/BigQuery → dbt → BI tool. Replicas serve read-only services.

---

Why is a laptop Postgres not a startup data platform? #card
Single machine: no backups, no shared access, single point of failure. The Postgres idea is fine for a few GB of sheets; use a managed instance or a cloud warehouse with a shared landing zone.

---

Design a low-cost stack for raw Excel/CSV sheets. #card
Bucket with dated immutable raw files → Python loader (adds `_source_file`, `_loaded_at`, row hash; raw columns as text) → `raw` tables → dbt staging (cast, clean) → marts with tests → BI. Scheduled by a GitHub Action. Hosting: BigQuery free tier or managed Postgres.

---

BigQuery free tier limits, and the catch? #card
10 GB storage and 1 TB queries per month free. Catch: sandbox tables expire after 60 days unless billing is enabled; set a query cost cap.

---

Spreadsheet pitfalls to guard against? #card
Schema drift (source tests on expected columns), silent type errors (keep raw as text, cast in staging), several versions of truth (replace vs append per sheet, keep `_loaded_at`), no owner (document who produces each sheet).

---

Why does explain show `rows=100` on `jsonb_array_elements`? #card
A set-returning function has a fixed planner estimate (ROWS 100) because the planner cannot see inside the JSON. Here the real count is 5 or 9; harmless on 4 rows, but at scale a misestimate can pick the wrong join.

---

Why did the planner estimate 110 rows for the 4-row `fields` table? #card
Small tables are never auto-analyzed (threshold 50 rows + 10%), so there are no statistics and the planner guesses from the page size. `analyze public.fields;` fixes it.

---

What is a cleaner Postgres alternative to `jsonb_array_elements` + `->>` for an array of objects? #card
`cross join jsonb_to_recordset(col) as o(id text, label text)`: typed columns declared once, no repeated `->>` extraction.

---

Why aggregate before joining in the lost-reason orphan check? #card
`group by new_value` first turns 2,000 events into 5 distinct reasons, so the anti-join compares 5 rows with 5 options instead of 2,000 with 5.

---

Why is a JSON string column expensive in BigQuery? #card
BigQuery has no indexes and bills/uses slots for the bytes it reads: a STRING with JSON is read whole and parsed again in every query. Store it as ARRAY<STRUCT<id INT64, label STRING>> (or unnest once into a table) so queries read only the subfields.

---

How does Snowflake handle `lateral flatten` on a VARIANT? #card
VARIANT is stored columnar: Snowflake extracts common paths into sub-columns, so `value:id` reads little. FLATTEN is a lateral table function; on a 4-row dictionary it costs nothing. The cost is a large fact table scanned without micro-partition pruning, or JSON kept as text and `parse_json` run on every query.

---

How do you stop many CTEs from each scanning the same big table? #card
Read it once into `base as materialized (select ... from table)` and let every per-key CTE filter `base`. In the Enpal findings file `explain` went from 7 `Seq Scan on deal_changes` to 1.

---

How do you keep rows whose JSON array is NULL or empty when unpacking in Postgres? #card
`left join lateral jsonb_to_recordset(col) as o(id int, label text) on true`; a `cross join` drops them.

---

What does `extract(epoch from ...)` return in Postgres? #card
On a timestamp: seconds since 1970-01-01 00:00. On an interval (`b - a`): its total length in seconds, with fractions. Divide by 86400 for days (used in the Enpal gap and lag queries).

---

Snowflake equivalent of `extract(epoch from b - a) / 86400`? #card
`datediff('second', a, b) / 86400`. For a single timestamp: `date_part(epoch_second, ts)`. Not `datediff('day', a, b)`: it counts midnights crossed (23:59 to 00:01 = 1 day).

---

BigQuery equivalent of `extract(epoch from b - a) / 86400`? #card
`timestamp_diff(b, a, second) / 86400` (DATETIME: `datetime_diff`). For a single timestamp: `unix_seconds(ts)`; a DATETIME needs `unix_seconds(timestamp(dt))`.
