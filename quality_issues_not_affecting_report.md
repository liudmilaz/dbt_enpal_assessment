# Data quality issues that do not affect the report

Issues found in the exploratory analysis that change no count and no name of `rep_sales_funnel_monthly`. They are kept here for completeness and for the discussion with the stakeholders; the issues that do affect the report are in the [README](README.md#data-quality-issues-affecting-the-report).

| Issue | Table | What was found | Why the report is not affected |
|---|---|---|---|
| D4 Lost reason on every deal | `deal_changes` | Every deal carries a lost reason, also deals that reached Closing or after-sales; each reason is spread over all stages. | The report counts Closing by the stage only; the lost reason is not used as an outcome. It is used only to dedup Duplicate Entry deals in staging (DUP-6, which is in the README). |
| D5 Changes at the creation's time of day | `deal_changes` | Every change of a deal is recorded at the time of day of its creation: the date of a change is reliable, its time of day is not. | The report uses dates only, by month, never durations between stages. Below the monthly grain (for example by week), deals whose stages were entered in a burst can distort the counts; that needs an impact analysis per user before such a report is built. |
| A3 After Close Calls before any Closing | `activity` | After Close Calls are due before any deal of the export reached Closing. | After Close Call is not a funnel step; the report counts Sales Call 1 and Sales Call 2 only. |
| T1 Inactive activity type in use | `activity_types` | Follow Up Call is inactive but keeps its past activities (normal Pipedrive behaviour). | Follow Up Call is not a funnel step. The format of the flag (`'Yes'` / `'No'`) is checked by a generic test on the source. |
| U1 Users sharing an email | `users` | A few emails are used by two users with different names. | The report does not read `users`; users are joined on id only, never on email. Test: `u1_shared_email__users`. |
| U2 Several owners per deal | `deal_changes` (owners) | The deals are spread over many owners with few deals each, which requires an additional understanding of the domain and calls / meetings for stakeholder management, in case the slicing / dicing per rep is needed. | The report has no owner or per-rep dimension. |
