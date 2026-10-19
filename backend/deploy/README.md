# Production hosting: Google Cloud Run

The Django backend in `backend/` runs on **Google Cloud Run** as a container. The iOS app reaches it over HTTPS.

> **Status:** the code, the image and the deploy script are ready and tested locally. **Nothing is deployed yet:** that needs a Google Cloud project, a database, a storage bucket and secrets (see "Setting it up"). The reasoning and the full analysis are in
> [`docs/superpowers/specs/2026-10-10-backend-cloud-run-deployment-design.md`](../../docs/superpowers/specs/2026-10-10-backend-cloud-run-deployment-design.md); what was changed and how to test it is in [`docs/changes-2026-10-10.md`](../../docs/changes-2026-10-10.md).

## Architecture

| Concern | Choice |
|---|---|
| Compute | Cloud Run, **at most one instance, scaling to zero when idle** (1 CPU, 2 GiB), one gunicorn worker with 8 threads |
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

## Decision: why at most one instance, and none when idle

The hum feature keeps state **inside the process and on the container's disk** between requests: an upload's file, intermediate runs, rendered stems, and spoken talk replies held in memory. A follow-up request that landed on a different copy of the container would get "That hum isn't on the server any more".

The cleaner fix is to move that state to shared storage, but that means changing `hum/`, which is deliberately left alone. So for the first release:

- `--max-instances 1`: there is never more than one copy.
- `--min-instances 0`: when nobody has used the app for a while (about 15 minutes) Google stops the copy and you pay nothing. The next request starts it again, which takes several seconds (the app retries a request that times out).
- **One gunicorn worker** (`deploy/gunicorn.conf.py`): talk replies live in that one process's memory. Concurrency comes from threads.
- **Disk is memory on Cloud Run**, so `server/janitor.py` deletes hum files older than `HUM_TTL_HOURS` (default 3) every `HUM_SWEEP_MINUTES` (default 10); otherwise uploads would pile up until the instance runs out of memory.

What this costs you: a stop, restart or redeploy loses in-flight hums (the app already says "Hum again"), the service can't scale out, and the first request after a quiet spell is slow (a cold Cloud Run copy, plus Neon waking up). Cost, with the service on request-based billing (`--cpu-throttling`) so only the seconds spent handling requests are charged: the monthly free allowance is 180,000 vCPU-seconds, which is about 50 busy hours at 1 vCPU. Past that, 1 vCPU + 2 GiB is about **$0.10 per busy hour** (third-party figures of $0.000024 per vCPU-second and $0.0000025 per GiB-second, plus $0.40 per million requests; check the [Cloud Run price list](https://cloud.google.com/run/pricing) before relying on them). A quiet month is **$0**. The worst case, one instance busy around the clock, is about **$75**; the rate limits and `--max-instances 1` bound it, but a Google budget alert only warns, it does not stop spending. For comparison, keeping one copy always on (`--min-instances 1`) would cost about $19 a month for 1 vCPU + 2 GiB idle, at $0.0000025 per vCPU-second and per GiB-second. Whether 2 GiB is enough for the hum engine has not been measured: after the first deploy, check the service's memory use in Cloud Run's Metrics tab, and raise `--memory` (or `--cpu`) in `cloud-run.sh` if it runs close to the limit or hums are slow. Cloudflare R2's free tier ([pricing](https://developers.cloudflare.com/r2/pricing/)) covers 10 GB of storage and free egress, which is plenty for the screened score library. **Neon's free plan suspends the database after 5 minutes idle and keeps 6 hours of restore history** ([plans](https://neon.com/docs/introduction/plans)), so the first request after a quiet spell is slow; use a paid plan or disable scale-to-zero before App Review.

When this needs to change: if one instance can't handle the load, the hum state has to move out of the container (uploads and runs to R2, talk replies to shared storage) before running more than one.

## The quick way: `setup.sh`

```bash
backend/deploy/setup.sh --check      # what is installed, logged in and already done; changes nothing
backend/deploy/setup.sh              # does everything that is left
```

It runs these stages in order: install the CLIs, log in, Google Cloud (project, billing, APIs, permissions), Neon database, R2 bucket and public address, secrets, data load, deploy and verify. It is safe to run again: it skips what exists and never rotates an existing secret, so it cannot lock the app out of its own key. `STAGES="secrets deploy"` runs only some stages, and `INSTALL_TOOLS=1` lets it install `gcloud`, `neonctl`, `wrangler` and `rclone` for you.

Still yours: creating the Google, Neon and Cloudflare accounts (Google and R2 want a card), approving the three browser logins, and creating one R2 API token (the script prints where). It stores the Gemini and ElevenLabs keys as `not-configured` (Talk mode is off in the first release; the comments in `stage_secrets` say how to add real keys later), and asks for the PDMX folder. At the end it prints the service URL and how to read the app key, which are what the Flutter app needs.

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
