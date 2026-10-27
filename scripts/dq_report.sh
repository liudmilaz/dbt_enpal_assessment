#!/usr/bin/env bash
# Data quality run and Elementary report on localhost.
# Runs every test (selector dq_report), the known data quality issues included: they fail by design and the report
# lists their affected raw rows (var test_sample_row_count). Overview: the dashboard; per issue: its test result page.
# Then builds the data quality dashboard (scripts/dq_dashboard.py): one tab per raw table, a chart per tab and the
# affected raw rows of the clicked issue, read from the same Elementary results. Needs the Snowflake CLI (`snow`).
# Usage: bash scripts/dq_report.sh [port] [target]   (report served on http://localhost:<port>, default 8081)
#   target test (default): refreshes the zero-copy clones in ENPAL_TEST.SRC first; target prod reads ENPAL_RAW.
#   Needs, before running: the Snowflake variables of scripts/snowflake_env.example exported (or ENPAL_ENV_FILE
#   set to a file that exports them), `dbt` on the PATH (the project's venv active) and the Elementary CLI `edr`
#   on the PATH or in EDR_BIN (a separate venv, so it cannot change the project's dbt version).
set -euo pipefail

cd "$(dirname "$0")/.."
export DBT_PROFILES_DIR=.
PORT="${1:-8081}"
TARGET="${2:-test}"
REPORT="elementary_report_${TARGET}.html"
# credentials: from the environment, or from the file named in ENPAL_ENV_FILE (kept outside the repository)
if [ -n "${ENPAL_ENV_FILE:-}" ]; then
  # shellcheck disable=SC1090
  source "$ENPAL_ENV_FILE"
fi
: "${SNOWFLAKE_ACCOUNT:?export the variables of scripts/snowflake_env.example, or set ENPAL_ENV_FILE}"
command -v dbt >/dev/null || { echo "dbt not found: activate the project's venv" >&2; exit 1; }
EDR="${EDR_BIN:-edr}"
command -v "$EDR" >/dev/null || { echo "edr not found: put the Elementary CLI on the PATH or set EDR_BIN" >&2; exit 1; }

# dbt: fresh clones (test only), models and Elementary tables, then all tests
dbt deps --quiet
if [ "$TARGET" = "test" ]; then
  dbt run-operation refresh_src --target test
fi
dbt run --target "$TARGET" --quiet
dbt test --selector dq_report --target "$TARGET" || true   # the known issues fail by design; the report shows them

# Elementary CLI in its own venv, so it cannot change the project's dbt version
"$EDR" report \
  --profiles-dir . \
  --project-dir . \
  --profile-target "$TARGET" \
  --days-back 30 \
  --open-browser false \
  --file-path "edr_target/$REPORT"

python3 -I scripts/dq_dashboard.py --target "$TARGET" --connection "${SNOW_CONNECTION:-enpal}"

echo "Report: http://localhost:$PORT/$REPORT"
echo "Data quality dashboard: http://localhost:$PORT/dq_dashboard_${TARGET}.html"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory edr_target
