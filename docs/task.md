# Assignment text

The take-home assessment as received from Enpal, copied unchanged for reference. The plan and decisions are in `NOTES.md` and `docs/model_plan.md`.

## Analytics Engineer Take-Home Assessment

Thank you for your interest in the Senior Analytics Engineer role at Enpal. As part of our selection process, we have a take-home assessment to better understand your skills and approach to analytics engineering. The assessment is structured as follows:

### What We’re Assessing

In this task, we’ll focus on evaluating three core areas:

- Exploratory Analysis – Assessing your ability to thoroughly investigate, analyze, and comprehend the data.
- Data Modeling – Your ability to structure and organize data meaningfully.
- SQL Code Efficiency – Reviewing how you optimize your SQL queries for performance.
- Project Organization and Clarity – Examining how you structure and document your work for ease of understanding and collaboration.

### The Task

#### Setup

1. Download Docker Desktop (if you don’t have installed) using the official website, install and launch.
2. Fork this Github project to your Github account. Clone the forked repo to your device.
3. Open your Command Prompt or Terminal, navigate to that folder, and run the command `docker compose up`.
4. Now you have launched a local Postgres database with the following credentials:
5. Connect to the db via a preferred tool (e.g. DataGrip, Dbeaver etc)
6. Install dbt-core and dbt-postgres using pip (if you don’t have) on your preferred environment.
7. Now you can run `dbt run` with the test model and check `public_pipedrive_analytics` schema to see the dbt result (with one test model)

#### Project

1. Remove the test model once you make sure it works
2. Dive deep into the Pipedrive CRM source data to gain a thorough understanding of all its details. (You may also research the Pipedrive CRM tool terms).
3. Define DBT sources and build the necessary layers organizing the data flow for optimal relevance and maintainability.
4. Build a reporting model (`rep_sales_funnel_monthly`) with monthly intervals, incorporating these funnel steps (KPIs):
   - Step 1: Lead Generation
   - Step 2: Qualified Lead
   - Step 2.1: Sales Call 1
   - Step 3: Needs Assessment
   - Step 3.1: Sales Call 2
   - Step 4: Proposal/Quote Preparation
   - Step 5: Negotiation
   - Step 6: Closing
   - Step 7: Implementation/Onboarding
   - Step 8: Follow-up/Customer Success
   - Step 9: Renewal/Expansion

   Column names of the reporting model: `month`, `kpi_name`, `funnel_step`, `deals_count`
5. “Git commit” all the changes and create a PR to your forked repo (not the original one). Send your repo link to us.

Once complete, also compress your project back into a .zip file and submit it via reply to this email.

We look forward to seeing your approach to this task. Please feel free to reach out if you have any questions.
