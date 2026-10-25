{{ config(
    severity='error',
    tags=['dq_known_issue', 'dq_duplicates'],
    meta={'issue': 'U1', 'owner': 'crm_admin', 'quality_dimension': 'uniqueness', 'description': 'Found (EDA 04 §2, 00 U1): some emails are shared by two users with different names. Improve (CRM admin): one login per person. Handled: users are joined on user_id only, never on email.'}
) }}

-- emails used by more than one user
with shared_emails as (
    select
        email
    from {{ source('pipedrive', 'users') }}
    group by email
    having count(*) > 1
)

-- one failed row per raw user with a shared email
select
    u.id,
    u.name,
    u.email,
    u.modified
from {{ source('pipedrive', 'users') }} u
inner join shared_emails s
    on s.email = u.email
