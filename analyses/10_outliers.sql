-- Question: are there outliers in the time between stage events or in the creation lag?
-- Finding:  gaps between stage events: max 35 days, IQR upper fence 45.5 -> none above. Creation lag: fence 75 days, 12 deals above (76-83 days), all plausible.
-- Consequence: no outlier treatment; the 12 are valid and stay in.
with g as (
  select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as days
  from public.deal_changes where changed_field_key = 'stage_id'
), t as (select days from g where days is not null),
b as (select percentile_cont(0.25) within group (order by days) as q1, percentile_cont(0.75) within group (order by days) as q3 from t)
select q1, q3, q3 + 1.5 * (q3 - q1) as upper_fence, count(*) filter (where days > q3 + 1.5 * (q3 - q1)) as n_above, max(days) as max_days
from t, b group by q1, q3;
