"""Build Pipedrive import files from the task CSVs in raw_data/.

Usage: python3 -I pipedrive_trial/build_import_files.py
Writes pipedrive_trial/deals_import.csv and pipedrive_trial/activities_import.csv.

Pipedrive imports the CURRENT state of a record, not its change history, so the event log
(deal_changes) is collapsed to one row per deal: its last stage, its first creation time,
its last owner and its lost reason. The history itself cannot be imported.
"""
import csv
from collections import defaultdict
from pathlib import Path

root = Path(__file__).resolve().parent.parent
raw = root / "raw_data"
out = Path(__file__).resolve().parent

stage_names = {int(r["stage_id"]): r["stage_name"] for r in csv.DictReader(open(raw / "stages.csv", newline=""))}
stage_names[2] = "Qualified Lead"  # casing used by the task and by fields.csv
type_names = {r["type"]: r["name"] for r in csv.DictReader(open(raw / "activity_types.csv", newline=""))}

events = defaultdict(list)
for r in csv.DictReader(open(raw / "deal_changes.csv", newline="")):
    events[r["deal_id"]].append(r)

with open(out / "deals_import.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Deal - Title", "Organization - Name", "Deal - Stage", "Deal - Source deal id",
                "Deal - Source created at", "Deal - Source owner id", "Deal - Source lost reason id",
                "Deal - Source stage path"])
    for deal_id in sorted(events, key=int):
        ev = sorted(events[deal_id], key=lambda r: r["change_time"])
        stages = [r for r in ev if r["changed_field_key"] == "stage_id"]
        created = min(r["new_value"] for r in ev if r["changed_field_key"] == "add_time")
        owners = [r for r in ev if r["changed_field_key"] == "user_id"]
        lost = [r for r in ev if r["changed_field_key"] == "lost_reason"]
        w.writerow([
            f"Deal {deal_id}", "Source export (test data)",
            stage_names[int(stages[-1]["new_value"])], deal_id, created.replace("T", " "),
            owners[-1]["new_value"] if owners else "", lost[-1]["new_value"] if lost else "",
            ">".join(r["new_value"] for r in stages),
        ])

with open(out / "activities_import.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Activity - Subject", "Activity - Type", "Activity - Due date", "Activity - Due time",
                "Activity - Done", "Activity - Note"])
    for r in csv.DictReader(open(raw / "activity.csv", newline="")):
        date, time = r["due_to"].split("T")
        w.writerow([f'{type_names[r["type"]]} (source activity {r["activity_id"]})', type_names[r["type"]],
                    date, time, "Yes" if r["done"] == "True" else "No",
                    f'source deal id {r["deal_id"]}; source assigned user id {r["assigned_to_user"]}; source type key {r["type"]}'])
print("ok")
