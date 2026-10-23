---
tags:
  - project/enpal
  - domain/eda
  - type/flashcard
---

# Flashcards — business-led exploration

---

What is the difference between profiling and business-led exploration? #card
Profiling checks whether the data is clean (keys, nulls, outliers). Business-led exploration checks whether it means what the KPI needs: state what the sales process would lead you to expect, query, write the consequence.

---

How do you find duplicate candidate-key rows in Postgres without QUALIFY? #card
Wrap a window count in a subquery: `select * from (select *, count(*) over (partition by k1, k2) as n_dup from t) x where n_dup > 1;` In Snowflake or BigQuery: `qualify count(*) over (partition by k1, k2) > 1`.

---

Why does Step 1 (Lead Generation) need a decision in the Enpal data? #card
A deal is created, gets an owner after ~15 days and enters stage 1 after ~35 days, so counting by creation or by stage 1 entry puts deals in different months (2024-01: 247 created vs 30 entered).

---

Why can Sales Calls 1 and 2 not be tied to the funnel deals? #card
Calls are flat (~130 per type per month) from January when almost no deal had reached stage 2, stop 2024-09-13, are 50% done in every type, and only 8 of 4,579 deal ids match, mostly with impossible timing.

---

What does the funnel shape say about the Enpal sample? #card
It barely narrows: only 5 deals stop at Lead Generation and the most common last stage is 8. A real funnel loses most deals early, so the sample looks pre-filtered or generated.

---

Why is lost_reason not a deal outcome in the Enpal data? #card
Every deal has one, set 1 to 30 days after its last stage event, including deals at Renewal/Expansion, and the five reasons are spread evenly over all stages.

---

How do you replace `from (select ...) t` in an analysis query? #card
Name the inner query as a CTE (`with moves as (...)`) and select from it: one CTE per step, then a flat final select.

---

How do you replace a scalar subquery in the select list, like `(select count(*) from x where x.k = t.k)`? #card
Aggregate once in a CTE (`x_counts as (select k, count(*) as n from x group by k)`) and join it on `k`.

---

How do you write `not in (select ...)` / `not exists` with CTEs, and why? #card
Put the keys in a CTE and anti-join: `left join cte on cte.key = t.key where cte.key is null`. Readable, and `not in` returns nothing if the list contains a NULL.

---

How do you check that a CTE rewrite did not change a result? #card
Run the old and new file, save both outputs, and `diff` them: a style change must not change a number.

---

Is Postgres case sensitive for table and column names? #card
Not for unquoted names: they are folded to lowercase, so `PUBLIC.DEAL_CHANGES` works. Quoted names are exact: `"Deal_Changes"` fails. Snowflake folds unquoted names to UPPERCASE instead.

---

Is Postgres case sensitive for values? #card
Yes. `changed_field_key = 'STAGE_ID'` matches 0 rows, `'Qualified lead' <> 'Qualified Lead'`, and JSON keys too (`o ->> 'Label'` is NULL). Use `lower()` or `ilike` for free-text labels.

---

What is the house SQL layout for analysis queries? #card
`select` alone, one column per line indented four spaces; `from`, `join`, `where`, `group by` at the margin; the join condition on the next line (`    on ...`); extra conditions as `    and ...`; CTEs instead of subqueries; snake_case aliases on every computed column.

---

Is `activity_types.active` a boolean in the Enpal data? #card
No: it is text with the values 'Yes' and 'No' (`pg_typeof` = character varying). Staging must cast it to a boolean `is_active`.

---

Where does a filter on the LEFT table go in a left join, and why? #card
In `where` or, better, in a CTE before the join. In the `on` clause it does not remove rows, it only stops them matching, so they come back with NULLs: the Pipedrive orphan check reported 6,500 false orphans.

---

Where does a filter on the RIGHT table go in a left join? #card
In `on` (`left join stages s on s.stage_id = e.stage_id and s.is_active`). In `where` it removes the NULL rows and turns the left join into an inner join.

---

Why must the stage events be filtered before `new_value::int` in deal_changes? #card
`new_value` also holds timestamps for `add_time`, so casting every row fails (`invalid input syntax for type integer`). Filter `changed_field_key = 'stage_id'` in a CTE first, then cast.

---

Does filtering in a CTE make the Enpal query faster? #card
Not here: `explain` shows Postgres already pushes the `where` filter down to the scan (same Hash Anti Join plan). The gain is correctness (safe cast) and readability.

---

What is the Snowflake equivalent of Postgres `cross join jsonb_array_elements(col) o` with `o ->> 'id'`? #card
`, lateral flatten(input => col) f` with `f.value:id::string` (use `parse_json(col)` if the column is text; `outer => true` keeps rows whose array is NULL or empty).

---

What is the BigQuery equivalent of Postgres `cross join jsonb_array_elements(col) o` with `o ->> 'id'`? #card
`cross join unnest(json_query_array(col)) as o` with `json_value(o, '$.id')` (returns STRING; `left join unnest(...)` keeps rows whose array is NULL or empty).

---

What are the three outlier queries for a fact table? #card
Rows per month (with quarter and year), rows per dimension (for a user: the distribution of the count per user), and rows per dimension and month (one column per value). Dictionaries: not applicable.

---

Why does a monthly count not show empty months, and how do you fix it? #card
`group by month` only returns months that have rows. Left join a month spine from `generate_series(min_month, max_month, interval '1 month')` and `coalesce` the count to 0.

---

What did the activity time distribution reveal about After Close Calls? #card
143 After Close Calls are due in 2024-01 and 157 before 2024-02-02, the first date any deal reaches Closing: the calls cannot belong to these deals.

---

Why does the IQR rule find no outliers in the Enpal stage gaps? #card
The gaps are flat (uniform) from 0.5 to 35 days; IQR fences assume one peak with tails, so a flat distribution has nothing outside them. The flatness itself is the finding (generated timing).

---

How many changes does an active Enpal deal get per month, and what does that say? #card
About 1.75 (1.74 to 1.84 until 2024-10, then down to 1.0 as deals finish). The rate is stable, so monthly totals move with the number of active deals, not with more activity per deal.

---

Why profile at monthly granularity, and when to go finer? #card
The export covers 15 months and the report is monthly, so the month shows ramp-up, run-off and outlier months; days or weeks are noise on ~2,000 deals. Seasonality or performance questions are separate deep dives per domain, with their own grain.
