# Creating the accounts and linking them to this project

You create the accounts (they need your identity, a card and your agreement). The repo already has a script that does the rest: `backend/deploy/setup.sh`. This page says what to create, in what order, what to copy out of each one, and where it goes.

> **What I checked and what I did not.** Billing and signup facts below were read from each company's own pages on 2026-10-15 and are linked at the end. **Not verified:** the exact menu names inside each dashboard (they change), Neon's card requirement (the plans page says the Free plan is $0/month and I saw no card mention, but confirm at signup), ElevenLabs' current plan prices, and `setup.sh` itself, which has only been tested against stand-in programs and **has never run against real accounts**. If a step does not match what you see, trust your screen and tell me.

> **Never paste a key into a chat, a commit or a screenshot.** Keys go only into `backend/.env` (git-ignored; I checked) or into the prompts `setup.sh` shows, which hide what you type.

## What you will have at the end

```
 your iPhone app --HTTPS + app key--> Google Cloud Run (the backend)
                                         |-- Neon (database)
                                         |-- Cloudflare R2 (score files)
                                         |-- Gemini (Google)   } Talk mode
                                         `-- ElevenLabs        }
 Apple Developer account  -> App Store Connect (the listing, TestFlight, review)
```

## The order (each step needs the ones above it)

| # | Account | Needs a card? | Cost | Needed for |
|---|---|---|---|---|
| 1 | A support email address | no | free | printed on the Privacy Policy; the server refuses to start without it |
| 2 | Google account, then **Google Cloud** | yes | about $19 to $39 a month for the always-on server, see the deploy README | hosting the backend |
| 3 | **Gemini billing** (inside Google AI Studio) | yes | prepay at least $5, then pay for use | Talk mode text, and it keeps your users' requests out of Google's training |
| 4 | **Neon** | not seen | Free plan is $0, but it sleeps after 5 idle minutes | the database |
| 5 | **Cloudflare**, with **R2** | checkout flow | free tier: 10 GB, free downloads | the score files |
| 6 | **ElevenLabs** | for a paid plan | check their pricing page | Talk mode voice |
| 7 | **Apple Developer Program** | yes | US$99 a year | putting the app on the App Store |

Do 1 first. Do 7 whenever you like (approval can take days, so start it early).

---

## Step 1. A support email address

You need an address you will really read. It is shown to the public and Apple's reviewers.

- **Simplest:** make a new free mailbox just for the app (for example a new Gmail or iCloud address). Works today, no domain needed.
- **More professional:** buy a domain, then use Cloudflare Email Routing to forward `support@yourdomain` to your own inbox. Cloudflare's docs say you must be using Cloudflare DNS for it, and it **receives and forwards** mail; replying *from* that address needs extra setup, so reply from your own mailbox at first or ask me about it.

**Link it:** nothing to paste now. `setup.sh` will ask for it as `SUPPORT_EMAIL`, and you will also pass it to the app build later.

## Step 2. Google Cloud (the server)

1. Go to <https://console.cloud.google.com> and sign in with your Google account. Accept the terms.
2. Open **Billing** and create a billing account (country, then card). Google will ask for this; without a billing account Cloud Run will not deploy. The script stops with "add a card at https://console.cloud.google.com/billing" if it is missing.
3. Install the command-line tool on your Mac: `brew install --cask google-cloud-sdk`.
4. In a terminal: `gcloud auth login` (opens a browser, choose the same Google account).

**Link it:** you do not create the project by hand. `setup.sh` creates one (you choose its id), links your billing account, turns on the services it needs and gives the server permission to read its secrets. Pick a project id that is lowercase letters, digits and hyphens, for example `hu-accompany-prod`.

## Step 3. Gemini (Talk mode), on a **paid** project

Google's terms say that only access through a Cloud project with an active billing account is a "Paid Service", and the unpaid tier lets Google use your users' requests to improve its products and tells you not to send it personal information. So the key must belong to a billed project.

1. Do Step 2 first, and run the `gcp` stage of `setup.sh` (Step 8) so that your Cloud project exists with billing linked.
2. Go to <https://aistudio.google.com/api-keys> and sign in with the same Google account.
3. Import that Cloud project into AI Studio on the **Projects** page, <https://aistudio.google.com/projects> (Google's billing page says you can "create a project and set up billing, or import an existing project"). Then click **Set up billing** next to it. Google's docs say upgrading means linking a billing account and prepaying a minimum of $5 of credit.
4. Click **Create API key** and choose that project. Copy the key.

**Link it:** put it in `backend/.env` as `GEMINI_API_KEY=...` (Step 8 shows the file). `setup.sh` copies it into Google Secret Manager for you.

Do **not** use the key AI Studio makes for you by default for the free-tier project: that one is the unpaid tier.

## Step 4. Neon (database)

1. Go to <https://neon.com> and sign up (the console offers sign-in with an account such as GitHub or Google, or an email).
2. You do not need to create a project by hand.

**Link it:** `setup.sh` runs `neonctl auth` (browser approval, once), creates a project named `hu-accompany`, reads its host, user, database and password, and stores the password in Secret Manager.

**Before App Review**, upgrade from the Free plan or turn off scale-to-zero. Neon's plans page says Free suspends after 5 minutes idle and keeps only 6 hours of restore history, so the first request after a pause is slow.

## Step 5. Cloudflare and R2 (score files)

1. Go to <https://dash.cloudflare.com/sign-up> and create an account, then verify your email.
2. In the dashboard open **Storage & databases, then R2**. Cloudflare's docs: you need "a Cloudflare account with an R2 subscription", added by completing a checkout flow. R2 has a free monthly allowance and is billed monthly for use beyond it. Expect to add a payment method there.
3. Install the tool: `npm install -g wrangler` (the script can do it with `INSTALL_TOOLS=1`).

**Link it:** `setup.sh` runs `wrangler login` (browser, once), creates the bucket `hu-accompany-scores`, and turns on its public `r2.dev` address, which becomes `MUSICXML_BASE_URL`.

**One thing only you can do:** uploading the score files needs an access key. In the dashboard go to **R2, Manage API tokens, Create API token**, give it **Object Read & Write** on that one bucket, and copy the **Access Key ID** and **Secret Access Key**. `setup.sh` asks for them when it reaches the data stage and does not save them.

## Step 6. ElevenLabs (Talk mode voice)

1. Go to <https://elevenlabs.io> and sign up.
2. Choose a **paid plan** before launch. Their pricing page says commercial-use licensing is on "Starter+" plans (it says so next to the music product; read the plan's terms to confirm it covers the speech API you use). Read these two things first, because they change what you tell users: **their Terms require users to be 18 or older**, and they may keep and reuse voice recordings (see "Read this first" in `legal-and-shipping.md`).
3. Open your profile menu, find **API Keys** (it is in the account or developer settings; the location moves), create a key and copy it.

**Link it:** put it in `backend/.env` as `ELEVENLABS_API_KEY=...`.

## Step 7. Apple Developer Program

1. On an iPhone or Mac, install the **Apple Developer** app and sign in with an Apple Account that has two-factor authentication on. Apple's enrollment page says to use your **legal name** in the first and last name fields (a nickname or company name delays approval), and you must be of legal age.
2. Start enrollment as an **Individual** (it is simplest, and the seller name shown on the App Store is your legal name; see Step 1 of `legal-and-shipping.md`). Pay the **US$99 per year** fee.
3. Wait for approval email (can take days).

**Link it:** after approval, in Xcode open `frontend/ios/Runner.xcworkspace`, select the **Runner** target, **Signing & Capabilities**, tick **Automatically manage signing** and choose your team. Set the real **Bundle Identifier** there first (not `com.example...`). The same bundle ID is used when you create the app in App Store Connect.

---

## Step 8. Wire it all together with the script

All of this is done from the repo root, in a terminal on your Mac.

1. **Create `backend/.env`** with only the two keys (copy the template: `cp backend/.env.example backend/.env`, then edit these lines):
   ```
   GEMINI_API_KEY=...from Step 3
   ELEVENLABS_API_KEY=...from Step 6
   ```
2. **Get the score data:** you need the PDMX download on your Mac (a folder that contains `mxl/`). It is CC BY 4.0, from Zenodo record 13763756. The import only loads the screened scores (about 1,369 of the rated ones), so it is small.
3. **Check where you stand** (changes nothing):
   ```bash
   backend/deploy/setup.sh --check
   ```
   It lists which tools are installed and which logins are done. Install anything missing, or let it: `INSTALL_TOOLS=1 backend/deploy/setup.sh`.
4. **Run the stages in this order the first time**, so the Gemini project exists before you make its key:
   ```bash
   STAGES="tools login gcp" backend/deploy/setup.sh     # three browser logins, then your Google Cloud project
   ```
   Now do Step 3 (import the project into AI Studio, set up billing, make the key) and put the key in `backend/.env`. Then:
   ```bash
   backend/deploy/setup.sh                              # does what is left: Neon, R2, secrets, data, deploy
   ```
   It asks for: the Cloudflare access key pair (Step 5), the PDMX folder, and your support email. It is safe to run again; it skips what already exists and never changes an existing secret.
5. **The end of the script prints** your service address, the three page addresses and how to read the app key:
   ```
   Service URL: https://hu-accompany-xxxxx.a.run.app
   App Store Connect Privacy Policy URL: <url>/privacy       Support URL: <url>/support
   ```
   Open `<url>/privacy`, `<url>/terms` and `<url>/support` in a browser on your phone. Read them once.

## Step 9. Link the app to the server (not built yet)

This is the one link I have **not** made. Today the app finds the backend by searching your Wi-Fi (mDNS), over plain `http`, and never sends the app key, so with the cloud server it would be refused. To finish it I need to change the app so that it:

- uses the fixed `https://` address from Step 8, passed at build time,
- sends the app key in the `X-App-Key` header,
- no longer asks for the local network permission (three entries in `Info.plist`), and
- keeps the local mDNS route only for development.

Then you build with:
```bash
flutter build ipa \
  --dart-define=API_BASE_URL=<service url> \
  --dart-define=APP_API_KEY=<the key, read with the gcloud command the script printed> \
  --dart-define=PRIVACY_POLICY_URL=<url>/privacy --dart-define=TERMS_OF_SERVICE_URL=<url>/terms \
  --dart-define=SUPPORT_EMAIL=<your support address>
```
(`API_BASE_URL` and `APP_API_KEY` are the names I would use; they do not exist yet.) Note that a key built into an app can be extracted by anyone who unpacks it, so it is a gate against casual misuse, not a secret.

## When something fails

- Run `backend/deploy/setup.sh --check` and read what it says is missing.
- Run the same command again after fixing it; it carries on from where it stopped.
- If a stage prints a command error, copy the error (not the keys) and show me.

## Sources (checked 2026-10-15)

- [Gemini API billing and paid tier](https://ai.google.dev/gemini-api/docs/billing) and [terms](https://ai.google.dev/gemini-api/terms)
- [Cloudflare R2 getting started](https://developers.cloudflare.com/r2/get-started/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/), [Email Routing](https://developers.cloudflare.com/email-routing/get-started/enable-email-routing/)
- [Neon plans](https://neon.com/docs/introduction/plans)
- [Apple Developer Program enrollment](https://developer.apple.com/programs/enroll/) and [what's included](https://developer.apple.com/programs/whats-included/)
- [ElevenLabs API pricing](https://elevenlabs.io/pricing/api) and [Terms of Use](https://elevenlabs.io/terms-of-use)
- Your own repo: `backend/deploy/README.md`, `backend/deploy/setup.sh`, `backend/.env.example`
