# Data quality issues

Every data quality issue found in the exploratory analysis of the Pipedrive export: what was found and how much of the export it affects, the business case behind it (an assumption, to confirm with Enpal), and how the pipeline cleanses or transforms it. The counts are rows of the raw export at the grain of each issue, so they describe this export and change with a new load.

The queries behind the counts are not repeated here. They are in the dashboards built with Claude charts (private artifacts on claude.ai, shared with the reviewers):

- [Pipedrive exploratory analysis](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e): one tab per raw table with the affected raw rows of each issue and its query, plus the tabs "Tables, keys and nulls" and "Issues and decisions".
- [Pipedrive funnel EDA](https://claude.ai/artifact/TFJEc4EbMPTMELGNdeFpvJ): the Pipedrive terms, the data cleansing assumptions, a preview of the monthly report and a reading of the results.

The same issues run as dbt tests in `tests/data_quality/` (tag `dq_known_issue`); `bash scripts/dq_report.sh` shows their affected rows locally.

## Summary

| Issue | Table | Affects the report | Rows affected | Distinct affected | Test |
|---|---|---|---|---|---|
| [D1](#d1) Skipped stages | `deal_changes` | yes | 2,502 stage moves | 1,684 deals | `d1_deals_with_skipped_stages` |
| [D2](#d2) After-sale without a recorded Closing | `deal_changes` | yes | 3,207 stage moves | 683 deals | `d2_after_sale_without_closing` |
| [D3](#d3) One deal_id, two lifecycles | `deal_changes` | yes | 10 lifecycles | 5 deals | `d3_two_creations_per_deal` |
| [DUP-6](#dup-6) Duplicate Entry deals that reached Closing | `deal_changes` | yes | 274 lost reasons | 274 deals | `dup6_duplicate_entry_deals_past_closing` |
| [A1](#a1) One activity_id, two activities | `activity` | yes | 22 activities | 11 activity ids | `a1_repeated_activity_id` |
| [A2](#a2) Activities not linked to the deal history | `activity` | yes | 4,571 activities | 4,564 deal ids | `a2_activity_deal_not_in_deal_changes` |
| [A4](#a4) Past activities never marked done | `activity` | yes | 2,289 activities | 2,285 activity ids | `a4_past_activities_not_done` |
| [X1](#x1) Exports end on different dates | `activity` | yes | 5 table and event types | 2 tables | `x1_export_end_dates_apart` |
| [S1](#s1) Stage spelled two ways | `stages` | yes | 1 stage | 1 stage name | `s1_stage_name_differs_from_field_label` |
| [D4](#d4) Lost reason on deals that reached Closing or later | `deal_changes` | no | 1,429 lost reasons | 1,424 deals | none (documented) |
| [D5](#d5) Changes at the creation's clock time | `deal_changes` | no | 13,373 changes | 1,995 deals | none (documented) |
| [A3](#a3) After Close Calls before any Closing | `activity` | no | 157 activities | 157 deal ids | none (documented) |
| [T1](#t1) Inactive activity type in use | `activity_types` | no | 1,133 activities | 1 activity type (follow_up) | generic `accepted_values` on `active` (format only) |
| [U1](#u1) Users sharing an email | `users` | no | 8 users | 4 emails | `u1_shared_email__users` |
| [U2](#u2) Several owners per deal | `users` | no | 501 deals | 501 deals | none (documented) |

## Issues that affect the report

They change a count or a name of `rep_sales_funnel_monthly`.

### D1
**Skipped stages** · `deal_changes` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#deal_changes)

- **Found:** 2,502 stage moves (1,684 deals). Grain: one row per stage move that jumps over at least one stage.
- **Business case (assumption):** Data entry behaviour, not a system error: with a high workload, reps update the pipeline after the fact and move a deal several stages at once. Pipedrive allows this unless the stages are mandatory.
- **Cleansing / transformation:** Count a skipped stage as reached (`is_inferred`), dated by the deal's earliest entry into a higher stage.
- **Test:** `d1_deals_with_skipped_stages`

### D2
**After-sale without a recorded Closing** · `deal_changes` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#deal_changes)

- **Found:** 3,207 stage moves (683 deals). Grain: the stage moves of deals that reached stage 7 to 9 but never stage 6.
- **Business case (assumption):** Same behaviour as D1 for Closing: the contract was signed (installation needs it), but the rep skipped the stage. Or after-sales runs in a separate pipeline that the export does not include.
- **Cleansing / transformation:** Count Closing as reached (inferred) when a deal reached an after-sale stage.
- **Test:** `d2_after_sale_without_closing`

### D3
**One deal_id, two lifecycles** · `deal_changes` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#deal_changes)

- **Found:** 10 lifecycles (5 deals). Grain: one row per deal and lifecycle (each lifecycle has its own creation clock time).
- **Business case (assumption):** Two deals were merged in Pipedrive: the deal that remains keeps one id and both histories. Business reason: the same household contacted Enpal twice through different channels (for example the web form and a partner or comparison site), two reps worked the two deals in parallel, and when the duplicate was found the deals were merged instead of one being closed. The two lifecycles overlap in time, which fits two parallel deals rather than a customer who came back later.
- **Cleansing / transformation:** Count each deal once per stage, by its first entry.
- **Test:** `d3_two_creations_per_deal`

### DUP-6
**Duplicate Entry deals that reached Closing** · `deal_changes` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#deal_changes)

- **Found:** 274 lost reasons (274 deals). Grain: one row per Duplicate Entry lost reason of a deal that reached Closing or later. In total 377 deals of the export carry a Duplicate Entry lost reason; staging leaves all of them out.
- **Business case (assumption):** Reps notice a duplicate late, after working the deal, or use Duplicate Entry for other cases.
- **Cleansing / transformation:** Dedup deals in staging.
- **Test:** `dup6_duplicate_entry_deals_past_closing`

### A1
**One activity_id, two activities** · `activity` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#activity)

- **Found:** 22 activities (11 activity ids). Grain: one row per activity that shares its id.
- **Business case (assumption):** The export gives two different activities the same id.
- **Cleansing / transformation:** Keep one row per activity id, the one with the latest due date.
- **Test:** `a1_repeated_activity_id`

### A2
**Activities not linked to the deal history** · `activity` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#activity)

- **Found:** 4,571 activities (4,564 deal ids). Grain: one row per activity whose deal_id is not in deal_changes.
- **Business case (assumption):** Activities and deals were exported from different sets of deals.
- **Cleansing / transformation:** Count calls by due month with their own deal id; do not join them to the funnel deals.
- **Test:** `a2_activity_deal_not_in_deal_changes`

### A4
**Past activities never marked done** · `activity` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#activity)

- **Found:** 2,289 activities (2,285 activity ids). Grain: one row per activity due before the export cut-off and not done.
- **Business case (assumption):** Data entry behaviour: with a high workload, reps hold the call but do not mark it as done.
- **Cleansing / transformation:** Count done calls only; the calls due before the export ended are flagged (is_due_before_export_end in int_pipedrive__sales_calls) to count them if the business confirms.
- **Test:** `a4_past_activities_not_done`

### X1
**Exports end on different dates** · `activity` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#activity)

- **Found:** 5 table and event types (2 tables). Grain: one row per table and event type with its first and last date.
- **Business case (assumption):** The tables were exported at different times.
- **Cleansing / transformation:** Report up to the last month with data; the call steps are 0 after 2024-09.
- **Test:** `x1_export_end_dates_apart`

### S1
**Stage spelled two ways** · `stages` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#stages)

- **Found:** 1 stage (1 stage name). Grain: one row per stage whose name differs from its label in the Stage field.
- **Business case (assumption):** The stage was renamed in one place and not in the other.
- **Cleansing / transformation:** Take the step names from the Stage field labels.
- **Test:** `s1_stage_name_differs_from_field_label`

## Issues that do not affect the report

Recorded for completeness and for the discussion with the stakeholders; they change no count and no name of the report.

### D4
**Lost reason on deals that reached Closing or later** · `deal_changes` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#deal_changes)

- **Found:** 1,429 lost reasons (1,424 deals). Grain: one row per lost reason of a deal that reached Closing or an after-sale stage.
- **Business case (assumption):** The export fills a lost reason for every deal, also for deals that reached Closing. In Pipedrive only lost deals have one.
- **Cleansing / transformation:** Keep the lost reason as a closure label; do not use it as an outcome.
- **Test:** none (documented)

### D5
**Changes at the creation's clock time** · `deal_changes` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#deal_changes)

- **Found:** 13,373 changes (1,995 deals). Grain: one row per change after the creation that falls on the creation's time of day.
- **Business case (assumption):** Every change of a deal is recorded at the time of day of its creation, so the date of a change is reliable, its time of day is not. Remark: Deals whose stages were moved within a short time, most likely because reps kept notes locally and entered them into Pipedrive later, can distort the results below the monthly grain, for example by week. An impact and driver analysis, also per user, would show whether there is a pattern in this behaviour, and whether to approach the stakeholders who report on the funnel KPIs proactively: explain how the calculation works, and agree whether to adjust the calculation, the process, or the guidance for data entry.
- **Cleansing / transformation:** Use dates only, never durations between stages.
- **Test:** none (documented)

### A3
**After Close Calls before any Closing** · `activity` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#activity)

- **Found:** 157 activities (157 deal ids). Grain: one row per After Close Call due before the first Closing of any deal.
- **Business case (assumption):** These calls follow deals that are not in this export (see A2).
- **Cleansing / transformation:** No change; After Close Call is not a funnel step.
- **Test:** none (documented)

### T1
**Inactive activity type in use** · `activity_types` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#activity_types)

- **Found:** 1,133 activities (1 activity type (follow_up)). Grain: one row per activity of a type with active = 'No'.
- **Business case (assumption):** Normal Pipedrive behaviour: a deactivated activity type keeps its past activities.
- **Cleansing / transformation:** Store active as true or false and keep the activities.
- **Test:** generic `accepted_values` on `active` (format only)

### U1
**Users sharing an email** · `users` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#users)

- **Found:** 8 users (4 emails). Grain: one row per user whose email is used by another user.
- **Business case (assumption):** A Pipedrive login email is unique, so a shared email points to edited user data, not to one person twice.
- **Cleansing / transformation:** Join users on id, never on email.
- **Test:** `u1_shared_email__users`

### U2
**Several owners per deal** · `users` · [rows and query](https://claude.ai/artifact/6PhtBmyakkfguDDMiyXj1e#users)

- **Found:** 501 deals (501 deals). Grain: one row per deal with more than one owner.
- **Business case (assumption):** The deals are spread over many owners with few deals each, which requires an additional understanding of the domain and calls / meetings for stakeholder management, in case the slicing / dicing per rep is needed.
- **Cleansing / transformation:** No per-rep KPIs from this export; a per-user funnel is proposed in the README, section "Further development: the funnel per user".
- **Test:** none (documented)
