### The five questions with the highest impact on the report

The questions that change the counts of `rep_sales_funnel_monthly` the most, and the first four the count of closed deals. Ask them first.

**Note:** the provided data set is most probably synthetic, so some of its behaviour may be inconsistent and not fully reflect reality. The questions below treat each pattern as if it came from a real export, to show how I would clarify it with the business.

**1. Skipped stages
- **Question** (sales ops, KPI owner): reps often move a deal several stages at once, for example from Lead Generation straight to Needs Assessment. Did the customer pass the skipped stages, so that the deal counts under each of them?
- **Explanation**: most deals skip at least one stage. It is data entry behaviour, not a system error: with a high workload, reps update the pipeline afterwards in one move, and Pipedrive allows it.
- **Impact**: the middle steps of the funnel, Closing included, are much higher when skipped stages count as reached than with recorded stages only.
- **Proposed handling**: count a skipped stage as reached, flagged `is_inferred`, dated by the deal's earliest entry into a higher stage; the recorded-only counts stay available from `int_pipedrive__deal_stage_entries`.

**2. After-sale without a recorded Closing
- **Question** (KPI owner, sales ops, after-sales lead): many deals reach Implementation or later without ever being moved to Closing. Was the contract signed for all of them? Is there a separate onboarding pipeline the export does not include?
- **Explanation**: installation needs a signed contract, so the Closing most likely happened but was not recorded, or after-sales runs in its own pipeline.
- **Impact**: decides the Closing step directly; a large share of the deals counted under Closing are inferred.
- **Proposed handling**: count Closing as reached (inferred) when a deal reached an after-sale stage; keep `is_inferred` so recorded and inferred closings can be reported apart.

**3. Duplicate Entry deals 
- **Question** (sales ops, KPI owner): deals with the lost reason Duplicate Entry still reached Closing or later. Are they really duplicates that should leave the funnel, or is the reason used for something else, for example a re-signed contract?
- **Proposed handling**: leave every deal with a Duplicate Entry lost reason out in staging (`stg_pipedrive__deal_changes`), also when it is the first lost reason of a two-lifecycle deal (D3); if they are real deals, it is a one-line change in staging.

**4. A lost reason on every deal
- **Question** (KPI owner, CRM admin): every deal has a lost reason, also deals that reached Closing or Renewal. What does a lost reason mean on a closed deal, and how do we tell won deals from lost ones?
- **Proposed handling**: keep the lost reason as a closure label, not an outcome, and count Closing by the stage only; split Closing by outcome once a won or lost status is available.

**5. Calls never marked done
- **Question** (KPI owner, sales ops): many Sales Call 1 and Sales Call 2 activities are never marked done, although all of them were due before the export ended. Is a call that was not marked done a held call for the KPI?
- **Impact**: the call steps (Sales Call 1 and Sales Call 2) are about half as high with done calls only.
- **Effect of counting calls due before the export ended**: Sales Call 1 (2.1) would go from 566 to 1,142 deals and Sales Call 2 (3.1) from 558 to 1,120; the report keeps its 154 rows, and its total goes from 11,704 to 12,842.
- **Proposed handling**: count done calls only until Enpal confirms; the calls due before the export ended are already flagged (`is_due_before_export_end`), so counting them is a one-line change.

Next in line: calls that cannot be linked to the funnel deals (A2) and that end months before the deal history (X1); they do not change the closed deals, but the call steps count calls by month and are empty after the activity export ends.