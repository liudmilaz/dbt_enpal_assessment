-- Question: what activity types exist and how many are done?
-- Finding:  four types (meeting, sc_2, follow_up, after_close_call), about 1,100 each, about 50% done; 11 activity_ids appear twice with different content.
-- Consequence: steps 2.1 / 3.1 use meeting and sc_2 only; surrogate key for activity; source uniqueness test at warn.
select type, done, count(*) as n from public.activity group by 1, 2 order by 1, 2;
-- repeated activity ids
select activity_id, count(*) as n from public.activity group by 1 having count(*) > 1 order by 1;
