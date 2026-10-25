-- accepted_values cannot catch a missing step: fails when the funnel does not have exactly the task's 11 steps
select
    count(*) as steps
from {{ ref('int_pipedrive__funnel_steps') }}
having count(*) <> 11
