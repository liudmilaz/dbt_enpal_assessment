# Approach

## Why compare with the UI and talk to the stakeholders

The tables show what was stored; the source system's UI shows how it was entered: which stage moves are allowed, what a lost reason or a merge does, which fields are mandatory. Many findings (skipped stages, duplicates, contradicting values) can be a defect or a rule of the data-entry process, and only the people who own the process and the KPIs can say which. So I compare the data with the UI, and I take the open points to the stakeholders with the evidence and a proposed default. The open questions are tracked in [[NOTES]] (register).

The general method is the skill `data-project-with-claude-code` (skills repo, PR #7).

## How I set up the Pipedrive trial account

Goal: see the deals and activities of the export the way a sales rep sees them, and learn the process from the UI.

1. **Opened a Pipedrive trial account** (free 14-day trial).
2. **Configured it like the source:**
   - pipeline renamed and extended to the 9 stages of the export (Lead Generation to Renewal/Expansion);
   - activity types created to match `activity_types`: Sales Call 1 (the default type Meeting renamed, so its key stays `meeting`), Sales Call 2, Follow Up Call, After Close Call;
   - Pipedrive's sample data removed.
3. **Prepared the import files** with `pipedrive_trial/build_import_files.py`:
   - `deals_import.csv`: one row per deal (1,995), with its current stage, owner, creation date and lost reason; the source ids and the stage path kept in custom text fields (Source deal id, Source owner id, Source lost reason id, Stage path); a placeholder organisation "Source export (test data)";
   - `activities_import.csv`: one row per activity (4,579).
4. **Imported the deals** with the import wizard: creation date mapped to "Deal created", stages mapped value by value, duplicates merged. An import can be reverted within 48 hours.
5. **Still to do:** confirm the deal count, import the activities, set Follow Up Call inactive (as in the export), then walk through the deals and activities in the UI.

Limits to know:
- Pipedrive imports the **current state** of a record, not its change history, so the stage timeline and the monthly funnel numbers can only be checked in the data.
- Times shift by 1 to 2 hours with the account's time zone.
- What the UI can confirm: deals per stage, activity totals by type and done flag, one deal's fields, how a lost reason and a merge behave.
