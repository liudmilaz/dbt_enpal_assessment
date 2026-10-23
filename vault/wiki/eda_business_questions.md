---
tags:
  - project/enpal
  - domain/eda
  - type/concept
---

# Business-led exploration

Profiling (keys, nulls, outliers) says whether the data is **clean**. Business questions say whether it **means what the KPI needs**. Start from what the business process would make you expect, then query the data, then write the consequence for the model.

Repo: `docs/business_context.md` (the one place for company context and the KPI-to-data map), `analyses/08_business_questions.sql` (B1 to B6).

| Block | Expectation | Data shows |
|---|---|---|
| B1 Lead Generation | created, owner assigned, enters pipeline | owner after 15 days, stage 1 after 35 days; monthly counts differ by rule |
| B2 Stages | in order, funnel narrows early | 84% skip; funnel barely narrows (most stop at stage 8) |
| B3 Sale length | weeks to months | stage 1 to Closing median 50 days |
| B4 Sales calls | around stages 2 and 3, linked to the deal | flat from January, end 2024-09-13, 50% done, unrelated deal ids |
| B5 Lost reason | set when lost, matches the stop | on every deal, after the last stage, spread evenly |
| B6 Owners | few reps, many deals each | 1,347 owners for 1,995 deals |

Simple primary key check (Postgres has no `qualify`):

```sql
select * from (
  select *, count(*) over (partition by deal_id, changed_field_key, change_time) as n_dup
  from public.deal_changes
) t where n_dup > 1;
-- Snowflake / BigQuery: ... qualify count(*) over (partition by ...) > 1
```

Related: [[02_data_findings]], [[pipedrive_crm_terms]], [[eda_skills]].
