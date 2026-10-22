-- Question: are there deals with more than one creation event?
-- Finding:  5 deals have two add_time events; they hold two full lifecycles (paths like 1>2>3>4>5>8>1>2>4>5)
--           and explain every backward move.
-- Consequence: count each deal once per step and month (first entry wins); list the ids as an open question.
select deal_id, count(*) as n_creations,
       (select string_agg(new_value, '>' order by change_time) from public.deal_changes s
        where s.deal_id = a.deal_id and s.changed_field_key = 'stage_id') as stage_path
from public.deal_changes a where changed_field_key = 'add_time'
group by deal_id having count(*) > 1 order by 1;
