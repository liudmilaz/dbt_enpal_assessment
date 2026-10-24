#!/usr/bin/env bash
# Data quality run and Elementary report on localhost (vault/project/elementary_rollout.md).
# The export ends in 2025-03 and today is later, so the run date is set inside the data:
# the anomaly monitors then test the last 4 weeks against the weeks since 2024-01.
# The run date is a Monday at midnight: weekly buckets start on Mondays, and a run date on another
# weekday cuts new buckets that overlap the stored ones, so every rerun would double the anomalies.
# Usage: bash scripts/dq_report.sh [port] [target]   (report served on http://localhost:<port>, default 8081)
#   target test (default): refreshes the zero-copy clones in ENPAL_TEST.SRC first; target prod reads ENPAL_RAW.
#   Credentials from ~/.snowflake/enpal.env (template: scripts/snowflake_env.example).
set -euo pipefail

cd "$(dirname "$0")/.."
export DBT_PROFILES_DIR=.
RUN_DATE="2025-03-10T00:00:00"
PORT="${1:-8081}"
TARGET="${2:-test}"
REPORT="elementary_report_${TARGET}.html"
source ~/.snowflake/enpal.env

# dbt: fresh clones (test only), Elementary tables, then all tests
source ~/.venvs/enpal_sf/bin/activate
dbt deps --quiet
if [ "$TARGET" = "test" ]; then
  dbt run-operation refresh_src --target test
fi
dbt run --select elementary --target "$TARGET" --quiet
dbt test --target "$TARGET" --vars "{custom_run_started_at: \"$RUN_DATE\"}" || true   # warnings and failures are findings, the report shows them
deactivate

# Elementary CLI in its own venv, so it cannot change the project's dbt version
~/.venvs/edr/bin/edr report \
  --profiles-dir . \
  --project-dir . \
  --profile-target "$TARGET" \
  --days-back 30 \
  --open-browser false \
  --file-path "edr_target/$REPORT"

echo "Report: http://localhost:$PORT/$REPORT"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory edr_target
