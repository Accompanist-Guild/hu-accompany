#!/usr/bin/env bash
# Builds the backend image in Google Cloud Build and deploys it to Cloud Run.
# Read deploy/README.md first: it lists what must exist before this runs (project, billing,
# secrets, database, object storage).
#
#   PROJECT=my-project POSTGRES_HOST=ep-xyz.neon.tech POSTGRES_DB=music_catalog POSTGRES_USER=app \
#   MUSICXML_BASE_URL=https://pub-xxxx.r2.dev SUPPORT_EMAIL=support@yourdomain.com  backend/deploy/cloud-run.sh
#
# DRY_RUN=1 prints every command instead of running it.
set -euo pipefail

: "${PROJECT:?set PROJECT to the Google Cloud project id}"
: "${POSTGRES_HOST:?set POSTGRES_HOST (the database server)}"
: "${POSTGRES_DB:?set POSTGRES_DB}"
: "${POSTGRES_USER:?set POSTGRES_USER}"
: "${MUSICXML_BASE_URL:?set MUSICXML_BASE_URL (the public address of the bucket holding musicxml/)}"
: "${SUPPORT_EMAIL:?set SUPPORT_EMAIL (the address printed on the public privacy policy; the server will not start without it)}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-hu-accompany}"
REPO="${REPO:-hu-accompany}"
TAG="${TAG:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/backend:${TAG}"
BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"

run() {
  if [ "${DRY_RUN:-}" = 1 ]; then printf '+'; printf ' %q' "$@"; echo; else "$@"; fi
}

echo "== 1. APIs and image repository =="
run gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com secretmanager.googleapis.com --project "$PROJECT"
if [ "${DRY_RUN:-}" = 1 ] || ! gcloud artifacts repositories describe "$REPO" --location "$REGION" --project "$PROJECT" >/dev/null 2>&1; then
  run gcloud artifacts repositories create "$REPO" --repository-format docker --location "$REGION" --project "$PROJECT"
fi

echo "== 2. Build (Cloud Build builds linux/amd64, which is what Cloud Run runs) =="
run gcloud builds submit "$BACKEND_DIR" --tag "$IMAGE" --project "$PROJECT"

# At most one instance, and none while nobody is using the app: the hum feature keeps state in the process, so it must
# never be two copies (see deploy/README.md), but an idle copy is not worth paying for. 1 CPU / 2 GiB is billed only
# while a request is being handled (--cpu-throttling), so a quiet month costs nothing.
# The first deploy doesn't know the service's address yet, so ALLOWED_HOSTS gets a placeholder that
# step 4 replaces. /healthz answers regardless of Host, so the service still starts.
echo "== 3. Deploy =="
run gcloud run deploy "$SERVICE" --image "$IMAGE" --region "$REGION" --project "$PROJECT" \
  --allow-unauthenticated \
  --min-instances 0 --max-instances 1 \
  --concurrency 8 --cpu 1 --memory 2Gi --cpu-throttling --timeout 300 --cpu-boost \
  --set-env-vars "ALLOWED_HOSTS=${ALLOWED_HOSTS:-placeholder.invalid},POSTGRES_HOST=${POSTGRES_HOST},POSTGRES_DB=${POSTGRES_DB},POSTGRES_USER=${POSTGRES_USER},PGSSLMODE=require,MUSICXML_BASE_URL=${MUSICXML_BASE_URL},SUPPORT_EMAIL=${SUPPORT_EMAIL}" \
  --set-secrets "DJANGO_SECRET_KEY=django-secret-key:latest,APP_API_KEY=app-api-key:latest,POSTGRES_PASSWORD=postgres-password:latest,GEMINI_API_KEY=gemini-api-key:latest,ELEVENLABS_API_KEY=elevenlabs-api-key:latest"

echo "== 4. Allow the service's own address =="
if [ "${DRY_RUN:-}" = 1 ]; then
  URL="https://${SERVICE}-example.${REGION}.run.app"
else
  URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT" --format 'value(status.url)')"
fi
HOST="${URL#https://}"
run gcloud run services update "$SERVICE" --region "$REGION" --project "$PROJECT" \
  --update-env-vars "ALLOWED_HOSTS=${HOST}"

if [ -n "${BILLING_ACCOUNT:-}" ]; then
  echo "== 5. Budget alert =="
  # A budget must be in the billing account's own currency (and names the project by number).
  CURRENCY="$(gcloud billing accounts describe "$BILLING_ACCOUNT" --format 'value(currencyCode)' 2>/dev/null || echo USD)"
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format 'value(projectNumber)' 2>/dev/null || echo "$PROJECT")"
  run gcloud billing budgets create --billing-account "$BILLING_ACCOUNT" \
    --display-name "${SERVICE} monthly budget" --budget-amount "${BUDGET_USD:-30}${CURRENCY:-USD}" \
    --filter-projects "projects/${PROJECT_NUMBER}" \
    --threshold-rule percent=0.5 --threshold-rule percent=0.9 --threshold-rule percent=1.0
else
  echo "== 5. Budget alert skipped: set BILLING_ACCOUNT (and optionally BUDGET_USD) to create one =="
fi

echo
echo "Deployed: ${URL}"
echo "Check:    curl ${URL}/healthz"
echo "          curl -H 'X-App-Key: <your key>' ${URL}/api/quiz/topics"
