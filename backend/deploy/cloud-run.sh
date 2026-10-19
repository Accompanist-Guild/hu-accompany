#!/usr/bin/env bash
# Builds the backend image in Google Cloud Build and deploys it to Cloud Run.
# Read deploy/README.md first: it lists what must exist before this runs (project, billing,
# secrets, database, object storage).
#
#   PROJECT=my-project POSTGRES_HOST=ep-xyz.neon.tech POSTGRES_DB=music_catalog POSTGRES_USER=app \
#   MUSICXML_BASE_URL=https://pub-xxxx.r2.dev SUPPORT_EMAIL=support@yourdomain.com LEGAL_PUBLISHER="Your Name"  backend/deploy/cloud-run.sh
#
# Optional: LEGAL_ACCOUNTS, LEGAL_TALK_MODE and LEGAL_APP_STORE switch the matching parts of the public privacy
# policy and terms on or off. The Mac download has no accounts and no App Store, but it does have Talk mode, so
# LEGAL_TALK_MODE defaults to true here; set LEGAL_TALK_MODE=false only for an app built with TALK_MODE=false.
#
# DRY_RUN=1 prints every command instead of running it.
set -euo pipefail

: "${PROJECT:?set PROJECT to the Google Cloud project id}"
: "${POSTGRES_HOST:?set POSTGRES_HOST (the database server)}"
: "${POSTGRES_DB:?set POSTGRES_DB}"
: "${POSTGRES_USER:?set POSTGRES_USER}"
: "${MUSICXML_BASE_URL:?set MUSICXML_BASE_URL (the public address of the bucket holding musicxml/)}"
: "${SUPPORT_EMAIL:?set SUPPORT_EMAIL (the address printed on the public privacy policy; the server will not start without it)}"
: "${LEGAL_PUBLISHER:?set LEGAL_PUBLISHER (who the privacy policy and terms name as the publisher; the server will not start without it)}"
# --set-env-vars splits on commas, so a comma in the name would be read as the start of another variable.
case "$LEGAL_PUBLISHER" in *,*) echo "LEGAL_PUBLISHER must not contain a comma (it is '$LEGAL_PUBLISHER')" >&2; exit 1 ;; esac
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
# The Gemini and ElevenLabs keys are optional: with no key the server answers Talk mode with a plain "key is missing"
# message. Mount each only if its secret exists (a dry run assumes they do).
SECRETS="DJANGO_SECRET_KEY=django-secret-key:latest,APP_API_KEY=app-api-key:latest,POSTGRES_PASSWORD=postgres-password:latest"
for pair in gemini-api-key:GEMINI_API_KEY elevenlabs-api-key:ELEVENLABS_API_KEY; do
  secret="${pair%%:*}"; var="${pair##*:}"
  if [ "${DRY_RUN:-}" = 1 ] || gcloud secrets describe "$secret" --project "$PROJECT" >/dev/null 2>&1; then
    SECRETS="$SECRETS,$var=$secret:latest"
  else
    echo "note: no secret $secret, so $var is not set and that part of Talk mode will say its key is missing"
  fi
done

echo "== 3. Deploy =="
run gcloud run deploy "$SERVICE" --image "$IMAGE" --region "$REGION" --project "$PROJECT" \
  --allow-unauthenticated \
  --min-instances 0 --max-instances 1 \
  --concurrency 8 --cpu 1 --memory 2Gi --cpu-throttling --timeout 300 --cpu-boost \
  --set-env-vars "ALLOWED_HOSTS=${ALLOWED_HOSTS:-placeholder.invalid},POSTGRES_HOST=${POSTGRES_HOST},POSTGRES_DB=${POSTGRES_DB},POSTGRES_USER=${POSTGRES_USER},PGSSLMODE=require,MUSICXML_BASE_URL=${MUSICXML_BASE_URL},SUPPORT_EMAIL=${SUPPORT_EMAIL},LEGAL_PUBLISHER=${LEGAL_PUBLISHER},LEGAL_ACCOUNTS=${LEGAL_ACCOUNTS:-false},LEGAL_TALK_MODE=${LEGAL_TALK_MODE:-true},LEGAL_APP_STORE=${LEGAL_APP_STORE:-false}" \
  --set-secrets "$SECRETS"

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
  run gcloud billing budgets create --billing-account "$BILLING_ACCOUNT" \
    --display-name "${SERVICE} monthly budget" --budget-amount "${BUDGET_USD:-10}USD" \
    --filter-projects "projects/${PROJECT}" \
    --threshold-rule percent=0.5 --threshold-rule percent=0.9 --threshold-rule percent=1.0
else
  echo "== 5. Budget alert skipped: set BILLING_ACCOUNT (and optionally BUDGET_USD) to create one =="
fi

echo
echo "Deployed: ${URL}"
echo "Check:    curl ${URL}/healthz"
echo "          curl -H 'X-App-Key: <your key>' ${URL}/api/quiz/topics"
