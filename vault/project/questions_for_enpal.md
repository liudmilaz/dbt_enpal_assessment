---
tags:
  - project/enpal
  - type/questions
---

# Questions on the assumptions

Every assumption made in the implementation, as a question to whoever can confirm or correct it. Two groups:

- **Data team**: answered during onboarding, from the team and from the existing code base, documentation and data (with AI help to read the code and search the history).
- **Stakeholders**: answered in regular, proactive meetings with the people who own the process and the KPIs.

The evidence behind each question is in [[data_quality_issues]] (query per issue), [[cleansing_proposals]] (decisions) and [[deal_history_and_questions_for_enpal]] (deal 399956 and the three questions with SQL). Background: [[approach -- keep]].

## 1. Data team (onboarding)

### The export and its load

| #   | Assumption in the implementation                                                  | Question                                                                                                                                                                 | Where it shows                         |
| --- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------- |
| T1  | The six CSVs are one static export, loaded once (`create or replace`)             | How is the Pipedrive data extracted and loaded today: tool (API, Fivetran, Airbyte, own script), full or incremental, schedule? Is there a raw history of earlier loads? | `scripts/snowflake_load.sql`, X1       |
| T2  | The tables were exported at different cut-offs (X1)                               | Are all tables taken at the same moment? Why do activities and deal creations end on 2024-09-13 while stage moves run to 2025-02?                                        | `x1_export_end_dates_apart`            |
| T4  | Timestamps are read as they are (no time zone)                                    | Which time zone are the timestamps in (UTC, Europe/Berlin)? A deal near midnight can fall into another month.                                                            | report month                           |
| T5  | `activity.deal_id` should point to the deal history; it almost never does (A2)    | Do activities and deal changes come from the same deal set, or two separate exports? Is there a mapping table?                                                           | `a2_activity_deal_not_in_deal_changes` |
| T6  | Only four deal fields are exported, no pipeline id                                | Can the export add the deal status (won, lost, open), value, pipeline id, the previous value and the author of a change?                                                 | logical model                          |
| T7  | `users` is the current state only                                                 | Is there a history of users (team, role, active from/to) anywhere?                                                                                                       | U2                                     |

### Keys and deduplication

| # | Assumption | Question | Where it shows |
|---|---|---|---|
| T8 | The grain of `deal_changes` is deal + field key + change time (surrogate `deal_change_key`) | Is the change time needed in the key, or does the source have a change id? (review note in `stg_pipedrive__deal_changes`) | staging |
| T9 | A repeated `activity_id` is two versions of one activity; the latest `due_to` is kept (A1) | How are activity ids generated in the export? Can one id hold two activities? | `stg_pipedrive__activity`, A1 |
| T10 | Two creations under one `deal_id` are a merge of two deals (D3) | Does the export keep both histories of merged deals? Is there a merge log? | `d3_two_creations_per_deal` |
| T11 | `active` is the text 'Yes' / 'No' (T1) | Is the format fixed by the export tool, or could it change? | `stg_pipedrive__activity_types` |

### Platform, conventions and tooling

| # | Assumption | Question |
|---|---|---|
| T12 | One schema per layer, the same name in every environment (`generate_schema_name`), environments told apart by database | What are the team's naming and environment conventions (dev, test, prod; schemas per developer or per layer)? |
| T13 | Test data as zero-copy clones of raw (`refresh_src`) | How does the team build test environments today (clones, samples, separate account)? |
| T14 | Known data quality issues fail in Elementary and stay out of `dbt build` (default selector) | Do you use Elementary or another tool for data quality, and a deployed data catalog? Who receives the alerts? |
| T15 | Generic tests on keys plus one custom test per known issue | What is the team's test policy (severities, which layers, CI)? |
| T16 | dbt runs locally; prod from `main` only | How do dbt jobs run (dbt Cloud, Airflow, GitHub Actions) and how are deployments approved? |
| T17 | The report is monthly; coarser grains in a semantic layer | Which semantic layer and BI tool are used (Snowflake semantic views, Cortex Analyst, Looker, Lightdash)? Does lineage (Snowflake Horizon) reach them? |
| T18 | Snowflake features such as lineage are available | Which Snowflake edition and account setup (roles, warehouses, cost limits) does the team use? |

## 2. Stakeholders (regular meetings)

Who: the KPI owner (head of sales or revenue operations), sales ops (data entry), the CRM admin (Pipedrive configuration), and the after-sales lead for stages 7 to 9.

### The five questions with the highest impact on the report

The questions that change the counts of `rep_sales_funnel_monthly` the most, and the first four the count of closed deals. Ask them first.

**1. Skipped stages (D1)**
- **Question** (sales ops, KPI owner): reps often move a deal several stages at once, for example from Lead Generation straight to Needs Assessment. Did the customer pass the skipped stages, so that the deal counts under each of them?
- **Explanation**: most deals skip at least one stage. It is data entry behaviour, not a system error: with a high workload, reps update the pipeline afterwards in one move, and Pipedrive allows it.
- **Impact**: the middle steps of the funnel, Closing included, are much higher when skipped stages count as reached than with recorded stages only.
- **Proposed handling**: count a skipped stage as reached, flagged `is_inferred`, dated by the deal's earliest entry into a higher stage; the recorded-only counts stay available from `int_pipedrive__deal_stage_entries`.

**2. After-sale without a recorded Closing (D2)**
- **Question** (KPI owner, sales ops, after-sales lead): many deals reach Implementation or later without ever being moved to Closing. Was the contract signed for all of them? Is there a separate onboarding pipeline the export does not include?
- **Explanation**: installation needs a signed contract, so the Closing most likely happened but was not recorded, or after-sales runs in its own pipeline.
- **Impact**: decides the Closing step directly; a large share of the deals counted under Closing are inferred.
- **Proposed handling**: count Closing as reached (inferred) when a deal reached an after-sale stage; keep `is_inferred` so recorded and inferred closings can be reported apart.

**3. Duplicate Entry deals (DUP-6)**
- **Question** (sales ops, KPI owner): deals with the lost reason Duplicate Entry still reached Closing or later. Are they really duplicates that should leave the funnel, or is the reason used for something else, for example a re-signed contract?
- **Explanation**: a real duplicate is usually noticed and closed early; reaching Closing suggests a different use of the reason.
- **Impact**: these deals are left out of every step, Closing included.
- **Proposed handling**: leave every deal with a Duplicate Entry lost reason out in staging (`stg_pipedrive__deal_changes`), also when it is the first lost reason of a two-lifecycle deal (D3); if they are real deals, it is a one-line change in staging.

**4. A lost reason on every deal (D4)**
- **Question** (KPI owner, CRM admin): every deal has a lost reason, also deals that reached Closing or Renewal. What does a lost reason mean on a closed deal, and how do we tell won deals from lost ones?
- **Explanation**: in Pipedrive only lost deals have a lost reason; here every deal has one and each reason is spread over all stages, so it reads as a closure label, not an outcome.
- **Impact**: "closed" can only mean "reached Closing", not "won"; the win rate and revenue cannot be measured from this export.
- **Proposed handling**: keep the lost reason as a closure label, not an outcome, and count Closing by the stage only; split Closing by outcome once a won or lost status is available.

**5. Calls never marked done (A4)**
- **Question** (KPI owner, sales ops): many Sales Call 1 and Sales Call 2 activities are never marked done, although all of them were due before the export ended. Is a call that was not marked done a held call for the KPI?
- **Explanation**: with a high workload, reps hold the call but do not mark it as done.
- **Impact**: the call steps (Sales Call 1 and Sales Call 2) are about half as high with done calls only.
- **Effect of counting calls due before the export ended**: Sales Call 1 (2.1) would go from 566 to 1,142 deals and Sales Call 2 (3.1) from 558 to 1,120; the report keeps its 154 rows, and its total goes from 11,704 to 12,842.
- **Proposed handling**: count done calls only until Enpal confirms. `int_pipedrive__sales_calls` already flags the calls that were due before the export ended (the last change of the deal history) with `is_due_before_export_end`; counting them as held is a one-line change in `rep_sales_funnel_monthly` (`where is_done or is_due_before_export_end`).

Next in line: calls that cannot be linked to the funnel deals (A2) and that end months before the deal history (X1); they do not change the closed deals, but the call steps count calls by month and are empty after the activity export ends.

### Funnel definitions

| # | Assumption in the implementation | Question | Who |
|---|---|---|---|
| S1 | Step 1 Lead Generation = first entry into stage 1, not the creation of the deal (weeks earlier) | When is a lead a lead: when the deal is created, or when it enters the pipeline? | KPI owner |
| S2 | A skipped stage counts as reached, dated at the earliest entry of a higher stage (D1, D2) | Is a deal in Negotiation counted under Qualified Lead and Needs Assessment? Should the report also show recorded-only steps? | KPI owner, sales ops |
| S3 | Steps 2.1 and 3.1 count done calls only; calls due before the export ended are flagged (`is_due_before_export_end`), not counted (A4) | Is a call that was due before the export ended but never marked done a held call for the KPI? Counting them would raise 2.1 from 566 to 1,142 and 3.1 from 558 to 1,120 deals. | KPI owner |
| S20 | The export ended at the last change of the deal history; every call was due before it | When was the export taken? Is the last change of the deal history the right cut-off for a call that is due but not marked done, or should overdue calls only count after a grace period (for example a few days)? | CRM admin, KPI owner |
| S4 | Calls are counted per month by their own deal ids, not per funnel deal (A2) | Should Sales Call 1 and 2 count calls, deals with a call, or deals of the funnel? | KPI owner |
| S5 | Sales Call 1 belongs after Qualified Lead (2.1), Sales Call 2 after Needs Assessment (3.1) | Is this the order of the sale, or can a call happen at any stage? | sales ops |
| S6 | The report runs from the first to the last month with data; steps 2.1 and 3.1 are 0 after 2024-09 | Should months without call data be shown as 0, left blank, or cut? | KPI owner |
| S7 | Step names use the Stage field labels (S1: "Qualified Lead") | Which spelling is official? | CRM admin |

### Deals, duplicates and outcomes

| # | Assumption | Question | Who |
|---|---|---|---|
| S8 | Deals with a Duplicate Entry lost reason are not real opportunities and leave the funnel (DUP-6), also when the reason is on the first of two lifecycles | How does a rep choose Duplicate Entry? Why do many of them reach Closing or later? Should they leave the funnel? | sales ops, KPI owner |
| S9 | Two lifecycles under one deal id count once per step, by the first entry (D3) | After a merge, which history counts, and for which owner? | sales ops, CRM admin |
| S10 | A lost reason is a closure label, not an outcome (D4): every deal has one, also deals in Renewal | What does a lost reason mean on a deal that reached Closing or after-sales? How do we tell won from lost? | CRM admin, KPI owner |
| S11 | Deals reach after-sales without a recorded Closing; Closing is inferred (D2) | Is there a separate onboarding pipeline (seen in the Pipedrive UI)? Should Closing be required before Implementation? | CRM admin, after-sales lead |

### Data entry and the process

| # | Assumption | Question | Who |
|---|---|---|---|
| S12 | Reps hold calls without marking them done (A4) | How do reps record held calls? Could the phone system mark them done? | sales ops |
| S13 | Follow Up Call is inactive but was used all year (T1) | When was it switched off, and what replaced it? | CRM admin |
| S14 | After Close Calls belong to deals outside this export (A3) | Which deals do after-close calls follow? | after-sales lead |
| S15 | Several owners per deal, many owners with few deals each (U2); owner is not used | How is the sales team organised (teams, roles, lead routing)? Are per-rep KPIs needed later? | KPI owner |
| S16 | Users share emails only in edited user data (U1) | Can two people share a CRM login? | CRM admin |

### Working together on data quality

| # | Question | Who |
|---|---|---|
| S17 | Who owns each issue at the source, who decides the rules, and when does an issue count as solved? | all |
| S18 | How often do we review the data quality report together, and who receives the alerts? | all |

### Renamed or replaced stages and activity types

| # | Assumption | Question | Who |
|---|---|---|---|
| S19 | Stages are matched by `stage_id` and activity types by their key (`type`), which Pipedrive never changes; the call steps pick the types by their current name (Sales Call 1, Sales Call 2), so a type that was replaced by a new one would drop out of steps 2.1 and 3.1 without notice | Have any activity types or stages been renamed or replaced, and when? The fix: match on the keys (`meeting`, `sc_2`), or keep a small mapping of old to new keys once a type is replaced. | CRM admin |

## How to organise the stakeholder meetings

It depends on the stakeholders and the company's culture; a few common set-ups:

- **Kick-off per KPI**: one meeting with the KPI owner, sales ops and the CRM admin to agree the definitions (S1 to S7) before the report is used; the decisions are written into the model descriptions.
- **Regular data quality review**: every two weeks at first, then monthly, walking through the data quality dashboard (one tab per raw table, the affected rows per issue) with the owners of the open issues (S8 to S16).
- **Async where the culture is async**: a Slack channel with the Elementary alerts and a short written update; meetings only for decisions.
- **One owner per decision**: decision rights agreed up front (for example a simple RACI: the KPI owner decides definitions, the CRM admin fixes the configuration, sales ops changes the data entry, the data team implements and tests).
- **Start small**: the data team first, then the most affected stakeholders (sales ops, CRM admin), then the wider audience once the definitions are agreed.
