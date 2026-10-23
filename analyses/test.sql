with moves as (  -- filter first: only stage events, so the cast to int is safe
    select *
        -- new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as move
    from public.deal_changes
    where changed_field_key = 'stage_id'
)
select
    move,
    count(*) as n_moves
from moves
where move is not null  -- the first stage event of a deal has no previous stage
group by 1
order by 1;

;

    select
        new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as move
    from public.deal_changes
    where changed_field_key = 'stage_id'
    -- 399956
    ;

select *
    -- new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as move
from public.deal_changes
where 1=1
-- where changed_field_key = 'stage_id'
    and deal_id = '399956'
    order by 2 desc
;
