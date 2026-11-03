#!/usr/bin/env bash
# Puts new backend code live, and nothing else: builds the image from backend/ as it is on disk and deploys it to
# the existing Cloud Run service. Cloud Run keeps the service's settings (environment, secrets, size, address) when
# only the image changes, so this needs none of setup.sh's answers and cannot break the database or key wiring.
# Use setup.sh / cloud-run.sh only to set the server up or change its settings. It first brings the database's tables
# up to date (migrate.sh), so new code never meets tables it doesn't know.
#
#   backend/deploy/update.sh            (PROJECT, REGION, SERVICE can be overridden)
#
# DRY_RUN=1 prints every command instead of running it.
set -euo pipefail

PROJECT="${PROJECT:-accompanist-prod}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-hu-accompany}"
REPO="${REPO:-hu-accompany}"
TAG="${TAG:-$(date +%Y%m%d-%H%M%S)}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/backend:${TAG}"
BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"

run() {
  if [ "${DRY_RUN:-}" = 1 ]; then printf '+'; printf ' %q' "$@"; echo; else "$@"; fi
}

if [ "${DRY_RUN:-}" = 1 ]; then echo "+ $(dirname "$0")/migrate.sh"; else "$(dirname "$0")/migrate.sh"; fi

echo "== 1. Build $IMAGE (in Google Cloud Build, a few minutes) =="
run gcloud builds submit "$BACKEND_DIR" --tag "$IMAGE" --project "$PROJECT"

echo "== 2. Deploy it to $SERVICE, keeping every setting =="
run gcloud run deploy "$SERVICE" --image "$IMAGE" --region "$REGION" --project "$PROJECT"

echo "== 3. Check =="
if [ "${DRY_RUN:-}" = 1 ]; then exit 0; fi
url="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT" --format 'value(status.url)')"
code="$(curl -s -o /dev/null -w '%{http_code}' "$url/privacy")"
[ "$code" = 200 ] || { echo "error: $url/privacy answered $code; see the service's Logs tab in Cloud Run" >&2; exit 1; }
echo "Live: $url (privacy page answers 200)"
