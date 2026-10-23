---
tags:
  - project/enpal
  - domain/eda
  - domain/sql
  - type/flashcard
---

# Flashcards — distributions in SQL

---

Why look at the distribution and not only the mean? #card
A mean hides bimodal data, spikes at default values, long tails and truncated ranges. Describe the shape in words (flat, right tail, one value holds 40%) before trusting any summary number.

---

Which SQL builds an equal-width histogram? #card
`width_bucket(x, lo, hi, 10)` with `lo = min(x)` and `hi = max(x) + 1e-9` (a value equal to the upper bound otherwise lands in an extra bucket), then `count(*)` per bucket. Add `repeat('#', (40.0 * n / max(n) over ())::int)` for a text bar.

---

How do you get equal-count bins? #card
`ntile(10) over (order by x)` in a CTE, then group by the decile. Do not put the window function and the `group by` in the same select.

---

Which numbers describe shape beyond mean and median? #card
Skewness (asymmetry; near 0 is symmetric, above 1 is a long right tail) and excess kurtosis (tails and peak; 0 is normal, about -1.2 is uniform). In Snowflake `skew(x)` and `kurtosis(x)`; in Postgres compute them from standardised powers.

---

What do skewness near 0 and excess kurtosis near -1.2 mean? #card
The values are uniformly distributed (flat histogram), typical for generated data, a capped timer or an assigned slot. Ask how the data was produced; do not read business meaning into the median.

---

How do you check how concentrated a categorical column is? #card
Frequency with cumulative share: `sum(count(*)) over (order by count(*) desc rows unbounded preceding) / sum(count(*)) over ()`. It shows how few values cover most rows (Pareto).

---

What does the distinct ratio tell you? #card
`count(distinct col) / count(*)`: 1.0 is a key candidate, near 0 is a category or constant. Pair it with the null count.

---

How do you look at how many events each entity has? #card
Group twice: `select n_events, count(*) from (select entity_id, count(*) as n_events from events group by 1) group by 1`. Entities far above the typical count are often merged or duplicated records that also break uniqueness tests.

---

How do you spot gaps or cut-offs in time coverage? #card
Count rows per month with a text bar and read the ramp-up, the stop date and any empty months. A table that ends before another produces zeros that are not real zeros.

---

Quantiles in one pass: Postgres vs Snowflake? #card
Postgres: `percentile_cont(array[0.05, 0.5, 0.95]) within group (order by x)`. Snowflake: `percentile_cont` takes one quantile per call (or use `approx_percentile`). Also `filter (where ...)` in Postgres is `count_if(...)` in Snowflake.

---

What did the Pipedrive gap distribution show? #card
Time between stage events is flat from 0 to about 30 days: mean 15.6, median 16, skewness -0.01, excess kurtosis -1.19, 691 gaps in every decile. The timing looks generated, so stage durations carry no business signal.

---

Why show `count(distinct activity_id)` and `count(*)` side by side in a done x type distribution? #card
With duplicate ids they differ wherever duplicate rows share both values: Sales Call 2 not done has 563 distinct ids but 564 rows (id 283914). Showing both lets the metric choose knowingly.

---

What does the done x type distribution say about the Enpal activities? #card
Every type is split about 50/50 done / not done, including Sales Calls; a real log of held calls would be mostly done, so the flag carries little business signal.
