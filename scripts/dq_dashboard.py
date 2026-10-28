"""Data quality dashboard: one tab per raw table, built from the results Elementary stores in Snowflake.

Reads the latest run of every known-issue test (tag dq_known_issue): its failed raw rows, its description
(Found / Handled) and its compiled SQL, and writes one self-contained HTML page next to the
Elementary report. Run it after the tests (scripts/dq_report.sh does both).

Usage: python3 scripts/dq_dashboard.py [--target test|prod] [--connection <snow connection>]
Needs the Snowflake CLI (`snow`) with a connection to the account (default name: enpal).
"""
import argparse
import json
import pathlib
import re
import subprocess

DATABASES = {"test": "ENPAL_TEST", "prod": "ENPAL_ANALYTICS_PROD"}
# the raw table an issue belongs to, by the prefix of its issue id
RAW_TABLE = {"DUP": "deal_changes", "D": "deal_changes", "A": "activity", "X": "activity", "T": "activity_types",
             "U": "users", "S": "stages"}
TABS = ["deal_changes", "activity", "activity_types", "users", "stages", "fields"]

TESTS_SQL = """
-- the latest result of every known-issue test, with its description
with latest as (
    select
        id,
        test_unique_id,
        test_short_name,
        failures,
        detected_at,
        test_results_query
    from {db}.ELEMENTARY.ELEMENTARY_TEST_RESULTS
    where tags like '%dq_known_issue%'
    qualify row_number() over (partition by test_unique_id order by detected_at desc) = 1
)
select
    l.id,
    l.test_short_name,
    l.failures,
    l.detected_at,
    l.test_results_query,
    t.meta,
    t.description
from latest l
inner join {db}.ELEMENTARY.DBT_TESTS t
    on t.unique_id = l.test_unique_id
order by l.test_short_name
"""

ROWS_SQL = """
-- the stored failed rows of those results
select
    elementary_test_results_id,
    row_index,
    result_row
from {db}.ELEMENTARY.TEST_RESULT_ROWS
where elementary_test_results_id in ({ids})
order by
    elementary_test_results_id,
    row_index
"""


def query(connection, sql):
    out = subprocess.run(["snow", "sql", "-c", connection, "-q", sql, "--format", "json"],
                         capture_output=True, text=True, check=True).stdout
    return [{k.lower(): v for k, v in row.items()} for row in json.loads(out)]


def split_description(text):
    # "Found (...): ... Handled: ..." -> two parts
    parts = {"found": text or "", "handled": ""}
    m = re.match(r"(?s)(Found.*?)(?:\s+Handled:(.*))?$", text or "")
    if m:
        parts = {"found": re.sub(r"^Found\s*", "", m.group(1) or "").strip(), "handled": (m.group(2) or "").strip()}
    return parts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="test", choices=DATABASES)
    ap.add_argument("--connection", default="enpal")
    args = ap.parse_args()
    db = DATABASES[args.target]

    tests = query(args.connection, TESTS_SQL.format(db=db))
    ids = ", ".join("'" + t["id"] + "'" for t in tests)
    rows = query(args.connection, ROWS_SQL.format(db=db, ids=ids)) if tests else []

    by_result = {}
    for r in rows:
        by_result.setdefault(r["elementary_test_results_id"], []).append(json.loads(r["result_row"]))

    issues = []
    for t in tests:
        issue = json.loads(t["meta"] or "{}").get("issue", t["test_short_name"])
        prefix = "DUP" if issue.startswith("DUP") else issue[:1]
        issues.append({
            "issue": issue,
            "test": t["test_short_name"],
            "raw_table": RAW_TABLE.get(prefix, "other"),
            "failures": t["failures"],
            "detected_at": t["detected_at"],
            "sql": (t["test_results_query"] or "").strip(),
            **split_description(t["description"]),
            "rows": by_result.get(t["id"], []),
        })

    data = {"target": args.target, "tabs": TABS, "issues": issues}
    root = pathlib.Path(__file__).resolve().parent.parent
    template = (root / "scripts" / "dq_dashboard_template.html").read_text()
    page = template.replace("/*__DATA__*/null", json.dumps(data, default=str).replace("</", "<\\/"))
    out = root / "edr_target" / f"dq_dashboard_{args.target}.html"
    out.parent.mkdir(exist_ok=True)
    out.write_text(page)
    print(f"{len(issues)} issues, {sum(len(i['rows']) for i in issues)} rows -> {out}")


if __name__ == "__main__":
    main()
