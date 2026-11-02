#!/usr/bin/env bash
# Brings the live database's tables up to date with the code (Django migrations), from this computer. The database
# address comes from the Cloud Run service's own settings and the password from Secret Manager, so nothing is typed
# or saved. update.sh runs this before every deploy: new code must never meet tables it doesn't know.
#
#   backend/deploy/migrate.sh            apply what is missing (shows the plan first)
#   PLAN_ONLY=1 backend/deploy/migrate.sh    only show what would be applied
#   PYTHON=/path/to/python ...           a Python with the backend's packages (default: backend/.venv, else python3)
set -euo pipefail

PROJECT="${PROJECT:-accompanist-prod}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-hu-accompany}"
BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${PYTHON:-}" ]; then
  if [ -x "$BACKEND_DIR/.venv/bin/python" ]; then PYTHON="$BACKEND_DIR/.venv/bin/python"; else PYTHON=python3; fi
fi

"$PYTHON" -c "import django, psycopg, dotenv" 2>/dev/null || {
  echo "error: $PYTHON can't run the backend. Make it a Python that can:" >&2
  echo "  python3 -m venv backend/.venv && backend/.venv/bin/pip install django psycopg[binary] python-dotenv" >&2
  exit 1
}

echo "== Reading the database address from Cloud Run ($SERVICE) =="
env_json="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT" --format json)"
eval "$(printf '%s' "$env_json" | "$PYTHON" -c '
import json, shlex, sys
env = {e["name"]: e.get("value") for e in json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0].get("env", [])}
for name in ("POSTGRES_HOST", "POSTGRES_DB", "POSTGRES_USER"):
    if not env.get(name):
        sys.exit(f"error: the service has no {name} setting")
    print(f"export {name}={shlex.quote(env[name])}")
')"
POSTGRES_PASSWORD="$(gcloud secrets versions access latest --secret postgres-password --project "$PROJECT")"
export POSTGRES_PASSWORD PGSSLMODE=require
echo "database: $POSTGRES_DB on $POSTGRES_HOST"

cd "$BACKEND_DIR"
# --skip-checks: the checks import every route, and with them the whole audio stack, which migrating doesn't need.
echo "== Migrations not yet applied =="
"$PYTHON" manage.py migrate --plan --skip-checks
if [ "${PLAN_ONLY:-}" = 1 ]; then exit 0; fi
echo "== Applying =="
"$PYTHON" manage.py migrate --noinput --skip-checks
