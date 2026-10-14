#!/usr/bin/env bash
# Sets up and deploys the whole backend: Google Cloud, Neon database, R2 bucket, secrets, data, Cloud Run.
# Safe to run again: every stage checks what already exists and skips it, and it never changes a secret
# that already exists (so re-running cannot lock the app out by rotating its key).
#
#   backend/deploy/setup.sh --check     show what is installed, logged in, and already done. Changes nothing.
#   backend/deploy/setup.sh             do everything that is left (asks only for what it cannot find out)
#   STAGES="secrets deploy" backend/deploy/setup.sh      only some stages. Stages, in order:
#                                       tools login gcp neon r2 secrets data deploy
#
# What no script can do for you: create the Google, Neon and Cloudflare accounts (a card is needed for
# Google and for Cloudflare R2), approve the three browser logins, and create one R2 API token (a stage
# prints the link). See deploy/README.md for what each stage does by hand.
#
# Handy inputs (all optional; anything missing is asked for): PROJECT BILLING_ACCOUNT BUDGET_USD REGION
#   NEON_NAME R2_BUCKET PDMX_ROOT IMPORT_LIMIT SKIP_DATA=1 INSTALL_TOOLS=1 PYTHON
set -euo pipefail

cd "$(dirname "$0")/../.."          # repo root
STATE=backend/deploy/.setup-state   # non-secret answers, so a re-run doesn't ask again
[ -f "$STATE" ] && . "$STATE"

REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-hu-accompany}"
NEON_NAME="${NEON_NAME:-hu-accompany}"
R2_BUCKET="${R2_BUCKET:-hu-accompany-scores}"
BUDGET_USD="${BUDGET_USD:-40}"
PYTHON="${PYTHON:-python3}"
ALL_STAGES="tools login gcp neon r2 secrets data deploy"
STAGES="${STAGES:-$ALL_STAGES}"

say() { printf '\n== %s ==\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
want() { case " $STAGES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# save KEY VALUE: remember a non-secret answer (never passwords or keys).
save() {
  touch "$STATE"; chmod 600 "$STATE"
  grep -v "^$1=" "$STATE" > "$STATE.tmp" 2>/dev/null || true
  printf '%s=%q\n' "$1" "$2" >> "$STATE.tmp"
  chmod 600 "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"
  printf -v "$1" '%s' "$2"
}

# ask VAR "question" [secret]: use $VAR if already set, otherwise ask on the terminal.
ask() {
  local var=$1 prompt=$2 silent=${3:-} val
  if [ -n "${!var:-}" ]; then return 0; fi
  [ -t 0 ] || die "$var is not set and there is no terminal to ask on (set it in the environment)"
  if [ -n "$silent" ]; then read -r -s -p "$prompt: " val; echo; else read -r -p "$prompt: " val; fi
  [ -n "$val" ] || die "$var is required"
  printf -v "$var" '%s' "$val"
}

# json_get 'python expression on d' : read JSON on stdin.
json_get() { "$PYTHON" -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

install_hint() {
  case $1 in
    gcloud)  echo "brew install --cask google-cloud-sdk" ;;
    rclone)  echo "brew install rclone" ;;
    neonctl) echo "npm install -g neonctl" ;;
    wrangler) echo "npm install -g wrangler" ;;
  esac
}

# ---------------------------------------------------------------------------------------------------------
stage_tools() {
  say "tools: gcloud (Google Cloud), neonctl (Neon), wrangler (Cloudflare), rclone (bulk upload)"
  local missing=""
  for t in gcloud neonctl wrangler rclone; do
    if have $t; then note "ok       $t"; else note "MISSING  $t     $(install_hint $t)"; missing="$missing $t"; fi
  done
  have "$PYTHON" || die "$PYTHON not found"
  [ -z "$missing" ] && return 0
  [ "${CHECK_ONLY:-}" = 1 ] && return 0
  if [ "${INSTALL_TOOLS:-}" != 1 ]; then
    die "install the missing tools (commands above), or run again with INSTALL_TOOLS=1 to let me do it:$missing"
  fi
  for t in $missing; do note "installing $t ..."; $(install_hint $t); done
}

stage_login() {
  say "login: each of these opens a browser once"
  if gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then note "ok  Google Cloud"
  elif [ "${CHECK_ONLY:-}" = 1 ]; then note "NOT LOGGED IN  Google Cloud  (gcloud auth login)"
  else gcloud auth login; fi
  if neonctl me >/dev/null 2>&1; then note "ok  Neon"
  elif [ "${CHECK_ONLY:-}" = 1 ]; then note "NOT LOGGED IN  Neon  (neonctl auth)"
  else neonctl auth; fi
  if wrangler whoami >/dev/null 2>&1 && ! wrangler whoami 2>&1 | grep -qi "not authenticated"; then note "ok  Cloudflare"
  elif [ "${CHECK_ONLY:-}" = 1 ]; then note "NOT LOGGED IN  Cloudflare  (wrangler login)"
  else wrangler login; fi
}

stage_gcp() {
  say "gcp: project, billing, APIs, permissions"
  ask PROJECT "Google Cloud project id to use (created if it doesn't exist; lowercase, digits, hyphens)"
  save PROJECT "$PROJECT"
  if gcloud projects describe "$PROJECT" >/dev/null 2>&1; then note "project $PROJECT exists"
  else note "creating project $PROJECT"; gcloud projects create "$PROJECT"; fi
  gcloud config set project "$PROJECT" >/dev/null

  if [ "$(gcloud billing projects describe "$PROJECT" --format='value(billingEnabled)' 2>/dev/null)" = "True" ]; then
    note "billing already linked"
  else
    if [ -z "${BILLING_ACCOUNT:-}" ]; then
      local accounts; accounts="$(gcloud billing accounts list --filter=open=true --format='value(name)')"
      [ -n "$accounts" ] || die "no open billing account: add a card at https://console.cloud.google.com/billing then run again"
      if [ "$(printf '%s\n' "$accounts" | wc -l | tr -d ' ')" = 1 ]; then BILLING_ACCOUNT="$accounts"
      else gcloud billing accounts list; ask BILLING_ACCOUNT "Billing account id to charge"; fi
    fi
    note "linking billing account $BILLING_ACCOUNT"
    gcloud billing projects link "$PROJECT" --billing-account "$BILLING_ACCOUNT"
  fi
  [ -n "${BILLING_ACCOUNT:-}" ] && save BILLING_ACCOUNT "$BILLING_ACCOUNT"

  gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com \
    secretmanager.googleapis.com --project "$PROJECT"
  local number; number="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
  local sa="serviceAccount:${number}-compute@developer.gserviceaccount.com"
  # Cloud Run reads the secrets as this account; new projects also build images as it.
  for role in roles/secretmanager.secretAccessor roles/cloudbuild.builds.builder; do
    gcloud projects add-iam-policy-binding "$PROJECT" --member "$sa" --role "$role" --condition=None >/dev/null
    note "granted $role"
  done
}

stage_neon() {
  say "neon: the Postgres database"
  if [ -z "${NEON_PROJECT_ID:-}" ]; then
    local found
    found="$(neonctl projects list --output json | json_get "next((p['id'] for p in (d['projects'] if isinstance(d, dict) else d) if p['name']=='$NEON_NAME'), '')")"
    if [ -n "$found" ]; then note "using existing Neon project $NEON_NAME"; save NEON_PROJECT_ID "$found"
    else
      note "creating Neon project $NEON_NAME"
      save NEON_PROJECT_ID "$(neonctl projects create --name "$NEON_NAME" --output json | json_get "(d.get('project') or d)['id']")"
    fi
  fi
  # The direct (not pooled) address: fine for Django, and what migrations want.
  local uri; uri="$(neonctl connection-string --project-id "$NEON_PROJECT_ID")"
  POSTGRES_HOST="$(printf '%s' "$uri" | "$PYTHON" -c "import sys,urllib.parse as u; print(u.urlparse(sys.stdin.read().strip()).hostname)")"
  POSTGRES_USER="$(printf '%s' "$uri" | "$PYTHON" -c "import sys,urllib.parse as u; print(u.unquote(u.urlparse(sys.stdin.read().strip()).username))")"
  POSTGRES_DB="$(printf '%s' "$uri" | "$PYTHON" -c "import sys,urllib.parse as u; print(u.urlparse(sys.stdin.read().strip()).path.lstrip('/'))")"
  POSTGRES_PASSWORD="$(printf '%s' "$uri" | "$PYTHON" -c "import sys,urllib.parse as u; print(u.unquote(u.urlparse(sys.stdin.read().strip()).password))")"
  save POSTGRES_HOST "$POSTGRES_HOST"; save POSTGRES_USER "$POSTGRES_USER"; save POSTGRES_DB "$POSTGRES_DB"
  note "database $POSTGRES_DB on $POSTGRES_HOST as $POSTGRES_USER"
}

# The database details are needed by later stages even when "neon" was skipped this run.
need_neon() {
  if [ -z "${NEON_PROJECT_ID:-}" ] || [ -z "${POSTGRES_PASSWORD:-}" ]; then stage_neon; fi
}

stage_r2() {
  say "r2: the bucket that holds the score files"
  if wrangler r2 bucket list 2>/dev/null | grep -q "$R2_BUCKET"; then note "bucket $R2_BUCKET exists"
  else note "creating bucket $R2_BUCKET"; wrangler r2 bucket create "$R2_BUCKET"; fi
  save R2_BUCKET "$R2_BUCKET"
  if [ -z "${MUSICXML_BASE_URL:-}" ]; then
    local out url
    out="$(wrangler r2 bucket dev-url enable "$R2_BUCKET" 2>&1 || true)"
    url="$(printf '%s' "$out" | grep -oE 'https://pub-[a-z0-9]+\.r2\.dev' | head -1 || true)"
    if [ -z "$url" ]; then
      url="$(wrangler r2 bucket dev-url get "$R2_BUCKET" 2>&1 | grep -oE 'https://pub-[a-z0-9]+\.r2\.dev' | head -1 || true)"
    fi
    if [ -z "$url" ]; then
      note "couldn't read the public address automatically. In the Cloudflare dashboard open R2 > $R2_BUCKET > Settings"
      note "and enable the r2.dev subdomain."
      ask MUSICXML_BASE_URL "Paste the public address (https://pub-....r2.dev)"
      url="$MUSICXML_BASE_URL"
    fi
    save MUSICXML_BASE_URL "$url"
  fi
  note "public address: $MUSICXML_BASE_URL"
}

# ensure_secret NAME VALUE: create it; if it exists, leave it alone.
ensure_secret() {
  if gcloud secrets describe "$1" --project "$PROJECT" >/dev/null 2>&1; then note "kept existing secret $1"
  else printf '%s' "$2" | gcloud secrets create "$1" --data-file=- --project "$PROJECT" >/dev/null; note "created secret $1"; fi
}

dotenv_value() { [ -f backend/.env ] && sed -n "s/^$1=//p" backend/.env | head -1 | sed -e "s/^['\"]//" -e "s/['\"]$//" || true; }

stage_secrets() {
  say "secrets: stored in Google Secret Manager, never in files"
  ask PROJECT "Google Cloud project id"
  need_neon
  ensure_secret django-secret-key "$("$PYTHON" -c 'import secrets; print(secrets.token_urlsafe(50))')"
  ensure_secret app-api-key "$("$PYTHON" -c 'import secrets; print(secrets.token_urlsafe(32))')"
  # The database password is the one secret that may change under us (a reset in Neon), so keep it current.
  if gcloud secrets describe postgres-password --project "$PROJECT" >/dev/null 2>&1; then
    if [ "$(gcloud secrets versions access latest --secret postgres-password --project "$PROJECT")" != "$POSTGRES_PASSWORD" ]; then
      printf '%s' "$POSTGRES_PASSWORD" | gcloud secrets versions add postgres-password --data-file=- --project "$PROJECT" >/dev/null
      note "updated secret postgres-password (it changed in Neon)"
    else note "kept existing secret postgres-password"; fi
  else ensure_secret postgres-password "$POSTGRES_PASSWORD"; fi
  local gem eleven
  gem="${GEMINI_API_KEY:-$(dotenv_value GEMINI_API_KEY)}"; eleven="${ELEVENLABS_API_KEY:-$(dotenv_value ELEVENLABS_API_KEY)}"
  if ! gcloud secrets describe gemini-api-key --project "$PROJECT" >/dev/null 2>&1; then
    GEMINI_API_KEY="$gem"; ask GEMINI_API_KEY "Gemini API key for talk mode (type none to skip)" secret; gem="$GEMINI_API_KEY"
    [ "$gem" = none ] && gem="not-configured"
  fi
  if ! gcloud secrets describe elevenlabs-api-key --project "$PROJECT" >/dev/null 2>&1; then
    ELEVENLABS_API_KEY="$eleven"; ask ELEVENLABS_API_KEY "ElevenLabs API key for talk mode (type none to skip)" secret; eleven="$ELEVENLABS_API_KEY"
    [ "$eleven" = none ] && eleven="not-configured"
  fi
  ensure_secret gemini-api-key "$gem"
  ensure_secret elevenlabs-api-key "$eleven"
}

stage_data() {
  say "data: build the score table in Neon and upload the score files to R2"
  if [ "${SKIP_DATA:-}" = 1 ]; then note "skipped (SKIP_DATA=1)"; return 0; fi
  need_neon
  [ -n "${MUSICXML_BASE_URL:-}" ] || die "run the r2 stage first"
  ask PDMX_ROOT "Folder that contains the PDMX 'mxl/' directory"
  [ -d "$PDMX_ROOT/mxl" ] || die "no mxl/ folder in $PDMX_ROOT"
  "$PYTHON" -c "import django, psycopg, dotenv" 2>/dev/null \
    || die "$PYTHON needs the backend's packages: pip install -r backend/requirements-prod.txt (or use your backend venv via PYTHON=...)"
  export POSTGRES_HOST POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD PGSSLMODE=require
  ( cd backend
    "$PYTHON" manage.py migrate --noinput
    "$PYTHON" manage.py import_pdmx --pdmx-root "$PDMX_ROOT" ${IMPORT_LIMIT:+--limit "$IMPORT_LIMIT"} )

  note "Uploading needs an R2 API token (the one thing that can't be scripted). In the Cloudflare dashboard:"
  note "R2 > Manage API tokens > Create API token > permission 'Object Read & Write' on bucket $R2_BUCKET."
  ask R2_ACCESS_KEY_ID "R2 Access Key ID"
  ask R2_SECRET_ACCESS_KEY "R2 Secret Access Key" secret
  local account; account="$(wrangler whoami 2>&1 | grep -oE '[0-9a-f]{32}' | head -1 || true)"
  [ -n "$account" ] || { ask CLOUDFLARE_ACCOUNT_ID "Cloudflare account id"; account="$CLOUDFLARE_ACCOUNT_ID"; }
  RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
  RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  RCLONE_CONFIG_R2_ENDPOINT="https://${account}.r2.cloudflarestorage.com" \
    rclone sync backend/storage/musicxml "r2:${R2_BUCKET}/musicxml" --exclude import_report.json --progress
}

stage_deploy() {
  say "deploy: build the image, deploy to Cloud Run, set the budget alert"
  ask PROJECT "Google Cloud project id"
  need_neon
  [ -n "${MUSICXML_BASE_URL:-}" ] || die "run the r2 stage first"
  PROJECT="$PROJECT" REGION="$REGION" SERVICE="$SERVICE" \
  POSTGRES_HOST="$POSTGRES_HOST" POSTGRES_DB="$POSTGRES_DB" POSTGRES_USER="$POSTGRES_USER" \
  MUSICXML_BASE_URL="$MUSICXML_BASE_URL" BILLING_ACCOUNT="${BILLING_ACCOUNT:-}" BUDGET_USD="$BUDGET_USD" \
    backend/deploy/cloud-run.sh

  say "verify"
  local url key
  url="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT" --format 'value(status.url)')"
  key="$(gcloud secrets versions access latest --secret app-api-key --project "$PROJECT")"
  save SERVICE_URL "$url"
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/healthz")" = 200 ] && note "ok   $url/healthz" || note "FAIL $url/healthz"
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/quiz/topics")" = 401 ] && note "ok   refuses requests without the key" || note "FAIL expected 401 without the key"
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "X-App-Key: $key" "$url/api/quiz/topics")" = 200 ] && note "ok   accepts the key" || note "FAIL expected 200 with the key"
  echo
  echo "Done."
  echo "  Service URL: $url"
  echo "  App key:     read it any time with:"
  echo "               gcloud secrets versions access latest --secret app-api-key --project $PROJECT"
  echo "Give both to Claude for the app changes."
}

# ---------------------------------------------------------------------------------------------------------
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=1; STAGES="tools login"
  stage_tools || true
  have gcloud && have neonctl && have wrangler && stage_login || true
  say "already done"
  [ -n "${PROJECT:-}" ] && note "Google Cloud project: $PROJECT" || note "Google Cloud project: not chosen yet"
  [ -n "${NEON_PROJECT_ID:-}" ] && note "Neon project: $NEON_PROJECT_ID" || note "Neon project: not created yet"
  [ -n "${MUSICXML_BASE_URL:-}" ] && note "R2 public address: $MUSICXML_BASE_URL" || note "R2 bucket: not set up yet"
  [ -n "${SERVICE_URL:-}" ] && note "Deployed: $SERVICE_URL" || note "Deployed: not yet"
  exit 0
fi

for s in $ALL_STAGES; do
  if want "$s"; then "stage_$s"; fi
done
