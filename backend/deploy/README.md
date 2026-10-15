# Production hosting: Google Cloud Run

The Django backend in `backend/` runs on **Google Cloud Run** as a container. The iOS app reaches it over HTTPS.

> **Status:** the code, the image and the deploy script are ready and tested locally. **Nothing is deployed yet:** that needs a Google Cloud project, a database, a storage bucket and secrets (see "Setting it up"). The reasoning and the full analysis are in
> [`docs/superpowers/specs/2026-10-10-backend-cloud-run-deployment-design.md`](../../docs/superpowers/specs/2026-10-10-backend-cloud-run-deployment-design.md); what was changed and how to test it is in [`docs/changes-2026-10-10.md`](../../docs/changes-2026-10-10.md).

## Architecture

| Concern | Choice |
|---|---|
| Compute | Cloud Run, **one always-on instance**, one gunicorn worker with 8 threads |
| Database | Neon Postgres (free tier to start) |
| Score files | Cloudflare R2 bucket, read over its public address (`MUSICXML_BASE_URL`) |
| TLS | Provided by Cloud Run |
| Secrets | Google Secret Manager, passed to the service as environment variables |
| Protection | App key (`X-App-Key`), rate limit, `/healthz`; see `server/middleware.py` |

```
iOS app --HTTPS + X-App-Key--> Cloud Run (gunicorn + Django) --> Neon Postgres (scores, catalog)
                                       |
                                       +--> R2 (score MusicXML, read-only)
                                       +--> Gemini / ElevenLabs APIs (talk mode)
```

## Decision: why a single always-on instance

The hum feature keeps state **inside the process and on the container's disk** between requests: an upload's file, intermediate runs, rendered stems, and spoken talk replies held in memory. A follow-up request that landed on a different copy of the container would get "That hum isn't on the server any more".

The cleaner fix is to move that state to shared storage, but that means changing `hum/`, which is deliberately left alone. So for the first release:

- `--min-instances 1 --max-instances 1`: there is only ever one copy, and it never scales to zero.
- **One gunicorn worker** (`deploy/gunicorn.conf.py`): talk replies live in that one process's memory. Concurrency comes from threads.
- **Disk is memory on Cloud Run**, so `server/janitor.py` deletes hum files older than `HUM_TTL_HOURS` (default 3) every `HUM_SWEEP_MINUTES` (default 10); otherwise uploads would pile up until the instance runs out of memory.

What this costs you: a restart or redeploy loses in-flight hums (the app already says "Hum again"), the service can't scale out, and an always-on instance costs money while idle. Checked against [Google's price list](https://cloud.google.com/run/pricing) (Tier 1 regions such as us-central1): an idle minimum instance is billed at $0.0000025 per vCPU-second and per GiB-second, so 2 vCPU + 4 GiB idle for a 30-day month is about 6 x 0.0000025 x 2,592,000 s = **$39**, plus the (higher) active rate while it serves requests and $0.40 per million requests; 1 vCPU + 2 GiB is about **$19**. Cloudflare R2's free tier ([pricing](https://developers.cloudflare.com/r2/pricing/)) covers 10 GB of storage and free egress, which is plenty for the screened score library. **Neon's free plan suspends the database after 5 minutes idle and keeps 6 hours of restore history** ([plans](https://neon.com/docs/introduction/plans)), so the first request after a quiet spell is slow; use a paid plan or disable scale-to-zero before App Review.

When this needs to change: if one instance can't handle the load, the hum state has to move out of the container (uploads and runs to R2, talk replies to shared storage) before running more than one.

## The quick way: `setup.sh`

```bash
backend/deploy/setup.sh --check      # what is installed, logged in and already done; changes nothing
backend/deploy/setup.sh              # does everything that is left
```

It runs these stages in order: install the CLIs, log in, Google Cloud (project, billing, APIs, permissions), Neon database, R2 bucket and public address, secrets, data load, deploy and verify. It is safe to run again: it skips what exists and never rotates an existing secret, so it cannot lock the app out of its own key. `STAGES="secrets deploy"` runs only some stages, and `INSTALL_TOOLS=1` lets it install `gcloud`, `neonctl`, `wrangler` and `rclone` for you.

Still yours: creating the Google, Neon and Cloudflare accounts (Google and R2 want a card), approving the three browser logins, and creating one R2 API token (the script prints where). It asks for the Gemini and ElevenLabs keys unless they are in `backend/.env`, and for the PDMX folder. At the end it prints the service URL and how to read the app key, which are what the Flutter app needs.

The script's logic was tested against stand-in `gcloud`, `neonctl`, `wrangler`, `rclone` and `curl` programs (49 checks: a full run, a re-run that changes nothing, a changed database password, missing tools, several billing accounts, and more). **It has not been run against real accounts**, and some command details (Neon's JSON output, `wrangler r2 bucket dev-url enable`) are from memory. If a step fails, the message says which; run it again after fixing that, and it carries on from there.

## Setting it up by hand (what `setup.sh` automates)

1. **Google Cloud:** create a project, link billing, install the CLI (`brew install --cask google-cloud-sdk`), `gcloud auth login`, `gcloud config set project <id>`.
2. **Neon:** create a project; note host, database, user, password (use the direct host).
3. **R2:** enable R2, create a bucket, enable public access (the `r2.dev` address; this is your `MUSICXML_BASE_URL`), create an API token with write access.
4. **Load the data** (needs the PDMX folder with `mxl/` on your machine):
   ```bash
   cd backend
   export POSTGRES_HOST=<host> POSTGRES_DB=<db> POSTGRES_USER=<user> POSTGRES_PASSWORD=<pw> PGSSLMODE=require
   python manage.py migrate
   python manage.py import_pdmx --pdmx-root /path/to/PDMX
   rclone sync storage/musicxml r2:<bucket>/musicxml      # keys must be musicxml/<name>.musicxml
   ```
5. **Secrets** (names must match `cloud-run.sh`): `django-secret-key`, `app-api-key`, `postgres-password`, `gemini-api-key`, `elevenlabs-api-key`:
   ```bash
   printf '%s' '<value>' | gcloud secrets create app-api-key --data-file=-
   gcloud projects add-iam-policy-binding <id> \
     --member serviceAccount:<project-number>-compute@developer.gserviceaccount.com \
     --role roles/secretmanager.secretAccessor
   ```
   Make the app key with `python3 -c "import secrets; print(secrets.token_urlsafe(32))"` and keep a copy: the Flutter app must send it.
6. **Deploy:**
   ```bash
   PROJECT=<id> POSTGRES_HOST=<host> POSTGRES_DB=<db> POSTGRES_USER=<user> \
   MUSICXML_BASE_URL=https://pub-xxxx.r2.dev SUPPORT_EMAIL=<your support address> BILLING_ACCOUNT=<id> BUDGET_USD=<amount> \
   backend/deploy/cloud-run.sh          # DRY_RUN=1 prints the commands without running them
   ```
   It builds the image in Cloud Build, deploys with the flags above, then sets `ALLOWED_HOSTS` to the service's address and creates a budget alert.
7. **Check:** `curl <url>/healthz` answers `ok`; `curl -H 'X-App-Key: <key>' <url>/api/quiz/topics` returns the list; and `<url>/privacy`, `<url>/terms` and `<url>/support` open in a browser with no key. Those three are the addresses App Store Connect and the app need (see [`docs/app-store/submission-checklist.md`](../../docs/app-store/submission-checklist.md)).

## Environment variables (production)

Required (the server refuses to start without them): `DJANGO_SECRET_KEY`, `ALLOWED_HOSTS`, `APP_API_KEY`, and `SUPPORT_EMAIL` (a real address: it is printed on the public privacy policy). Database: `POSTGRES_HOST`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `PGSSLMODE=require` for Neon. Also `MUSICXML_BASE_URL`, `GEMINI_API_KEY`, `ELEVENLABS_API_KEY`. Optional: `RATE_LIMIT_HUM_PER_MINUTE`, `RATE_LIMIT_DEFAULT_PER_MINUTE`, `HUM_TTL_HOURS`, `HUM_SWEEP_MINUTES`, `GUNICORN_THREADS`. See `backend/.env.example`.

## Try the image on your own machine

```bash
cd backend
docker build --platform linux/amd64 -t hu-accompany-backend .      # Cloud Run runs amd64
docker run --rm -p 8080:8080 -e DJANGO_SECRET_KEY=x -e ALLOWED_HOSTS=localhost -e APP_API_KEY=k \
  -e POSTGRES_HOST=<a reachable postgres> -e POSTGRES_PASSWORD=<pw> hu-accompany-backend
curl localhost:8080/healthz
```

The image is production mode by default, so it refuses to start without those three variables.

## Not done yet

- Everything in "Setting it up". Until then nothing here has run on Google Cloud.
- The first deploy must confirm two assumptions: that the **last** `X-Forwarded-For` entry is the real client address behind Cloud Run (used by the rate limit), and that Cloud Run accepts the request sizes the app uploads (hums are small, but the code allows 50 MB and Cloud Run's HTTP/1 request limit is about 32 MiB, from memory).
- The Flutter app does not send `X-App-Key` yet and still finds the server by mDNS on the local network; it needs the fixed `https://` address and the key.
- The privacy labels and policy must say that users' voice recordings go to this server and on to Gemini and ElevenLabs.
