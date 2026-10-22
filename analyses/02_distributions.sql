-- Question: what is the shape of the time between stage events, of the categories, and of events per deal?
-- Finding:  gaps between stage events are flat from 0 to about 30 days: mean 15.6, median 16, skewness -0.01, excess kurtosis -1.19
--           (a uniform distribution has -1.2), deciles hold 691 values each. Only 2 gaps are above 30 days.
--           Activity types are evenly split (about 25% each). Events per deal range from 4 to 17; the 5 deals with 15-17 events
--           are the two-lifecycle deals. Activity volume is flat at about 500 per month until mid September.
-- Consequence: the timing looks generated, not behavioural: do not read business meaning into stage durations or medians.
--              Events per deal confirms the five merged deals as the cause of the uniqueness failures.
-- Run in VS Code (SQLTools) or psql; the "-- section:" lines are labels.
-- section: '--- 1 numeric summary (x = days between consecutive events)'
with t as (
  select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
  from deal_changes where changed_field_key = 'stage_id'
), v as (select x from t where x is not null),
s as (select avg(x) as mu, stddev_samp(x) as sd, count(*) as n from v)
select s.n, round(s.mu::numeric, 2) as mean,
       round((percentile_cont(0.5) within group (order by v.x))::numeric, 2) as median,
       round(s.sd::numeric, 2) as stddev, round(min(v.x)::numeric, 2) as min, round(max(v.x)::numeric, 2) as max,
       round((sum(power((v.x - s.mu) / s.sd, 3)) / s.n)::numeric, 2) as skewness,
       round((sum(power((v.x - s.mu) / s.sd, 4)) / s.n - 3)::numeric, 2) as excess_kurtosis
from v, s group by s.n, s.mu, s.sd;

-- section: '--- 2 quantiles'
with v as (select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
           from deal_changes where changed_field_key = 'stage_id')
select percentile_cont(array[0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99]) within group (order by x) as qs from v where x is not null;

-- section: '--- 3 histogram with text bars'
with v as (select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
           from deal_changes where changed_field_key = 'stage_id'),
t as (select x from v where x is not null),
b as (select min(x) as lo, max(x) + 1e-9 as hi from t),
h as (select width_bucket(t.x, b.lo, b.hi, 10) as bucket, min(t.x) as bin_min, max(t.x) as bin_max, count(*) as n from t, b group by 1)
select bucket, round(bin_min::numeric, 1) as bin_min, round(bin_max::numeric, 1) as bin_max, n,
       repeat('#', (40.0 * n / max(n) over ())::int) as bar
from h order by bucket;

-- section: '--- 4 deciles'
with v as (select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x
           from deal_changes where changed_field_key = 'stage_id'),
d as (select x, ntile(10) over (order by x) as decile from v where x is not null)
select decile, count(*) as n, round(min(x)::numeric, 1) as lo, round(max(x)::numeric, 1) as hi
from d group by decile order by decile;

-- section: '--- 5 categorical frequency with cumulative share'
select type, count(*) as n, round(100.0 * count(*) / sum(count(*)) over (), 1) as pct,
       round(100.0 * sum(count(*)) over (order by count(*) desc, type rows unbounded preceding) / sum(count(*)) over (), 1) as cum_pct
from activity group by type order by n desc;

-- section: '--- 6 distribution over time (monthly counts + share of peak)'
select date_trunc('month', due_to)::date as month, count(*) as n,
       repeat('#', (30.0 * count(*) / max(count(*)) over ())::int) as bar
from activity group by 1 order by 1 limit 4;

-- section: '--- 7 distribution of a count per entity (events per entity)'
select n_events, count(*) as n_entities from (
  select deal_id, count(*) as n_events from deal_changes group by 1) x group by 1 order by 1;

-- section: '--- 8 cardinality and uniqueness ratio per column'
select 'activity.activity_id' as col, count(*) as n_rows, count(distinct activity_id) as n_distinct,
       round(count(distinct activity_id)::numeric / count(*), 4) as distinct_ratio, count(*) - count(activity_id) as n_null from activity
union all select 'activity.type', count(*), count(distinct type), round(count(distinct type)::numeric / count(*), 4), count(*) - count(type) from activity;

-- section: '--- 9 compare a distribution across groups (type x month)'
select to_char(date_trunc('month', due_to), 'YYYY-MM') as month,
       count(*) filter (where type = 'meeting') as meeting, count(*) filter (where type = 'sc_2') as sc_2,
       count(*) filter (where done) as done_n, round(100.0 * count(*) filter (where done) / count(*), 1) as done_pct
from activity group by 1 order by 1 limit 3;
