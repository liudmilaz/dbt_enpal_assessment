-- One plain select per raw table loaded from raw_data/*.csv (schema public).
-- Run one statement at a time: cursor in the statement, then Cmd+E, Cmd+E.

select *
from public.deal_changes;

select *
from public.activity;

select *
from public.activity_types;

select *
from public.users;

select *
from public.stages;

select *
from public.fields;
