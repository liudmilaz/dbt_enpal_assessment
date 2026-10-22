-- Question: how much does backfilling skipped stages change each step?
-- Finding:  recorded vs backfilled deals per stage: 1: 1,995/1,995; 2: 1,479/1,990; 3: 1,305/1,951; 4: 1,086/1,862; 5: 894/1,693;
--           6: 741/1,424; 7: 588/1,081; 8: 479/723; 9: 324/324. Backfill adds 4,152 stage entries.
-- Consequence: the choice changes the report by up to 90% on the middle steps; make it a variable, document both.
with s as (select deal_id, new_value::int as st from public.deal_changes where changed_field_key = 'stage_id'),
     mx as (select deal_id, max(st) as max_st from s group by 1)
select n as stage,
       (select count(distinct deal_id) from s where st = n) as recorded,
       (select count(*) from mx where max_st >= n) as backfilled
from generate_series(1, 9) n order by 1;
