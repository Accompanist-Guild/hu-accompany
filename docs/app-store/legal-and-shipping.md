# Shipping the app and settling the legal side: what you do, in order

This is the manual part. The code already does what code can do (below); everything else needs you, an account, a decision or a professional.

> **Not legal advice.** I'm not a lawyer. Where a rule comes from a source I checked, it is linked at the end. Where I'm relying on memory or a blog, I say so, and you should confirm it. Have a lawyer read the three public pages and answer the questions in Step 6 before you launch.

## What the code already does, and what it does not

| Already done in code | Still needs you |
|---|---|
| Copyright screen on the PDMX score library: 12,984 candidate scores became 1,369 (Part 1) | Decide who the legal publisher is, and enroll with Apple |
| Public Privacy Policy, Terms and Support pages, served by the backend | A real support email, a domain, a lawyer's read of the pages |
| In-app Privacy and Terms links, account deletion, data export | Make the AI services' terms fit your use: **age 18+, Gemini billing, ElevenLabs (see the blockers)** |
| Permission box before Talk mode sends anything to Gemini or ElevenLabs | Final bundle ID, app icon, App Store listing and screenshots |
| iOS privacy manifest, microphone text, export-compliance flag | Sign, archive and upload (the app now builds here); real-device test; TestFlight |
| Credit for the dataset (CC BY 4.0) on the Terms page | Apple's questionnaires: age rating, App Privacy, trader status |

---

## Read this first: four problems found by checking the providers' own terms (2026-10-15)

**Update (2026-10-19), Mac download:** the policy and terms now adapt to the release. `LEGAL_ACCOUNTS`, `LEGAL_TALK_MODE` and `LEGAL_APP_STORE` (server settings, all off by default) switch the account, Talk mode/AI-provider and App Store parts on and off (`<!--if accounts-->` blocks in `backend/legal/*.html`, tests in `server/tests.py`). With accounts and the App Store off and Talk mode on, which is the Mac download as it ships, the pages describe Talk mode, Gemini and ElevenLabs but not accounts, and say "device" instead of "phone". (Talk mode is on by default in the app since 2026-10-19, behind the 18+ confirmation and consent box; a build with `TALK_MODE=false` should deploy with `LEGAL_TALK_MODE=false`.) Production now refuses to start without `LEGAL_PUBLISHER`. Turn the flags on again, with the app features, for an App Store build. A lawyer has still not read these pages.

**Status (2026-10-15, later):** A is handled by an 18+ confirmation in the Talk mode permission box (and the Terms and policy say Talk mode is for adults). C is handled for now by a switch: login is off (`AppConstants.loginRequired`, set with `--dart-define=LOGIN_REQUIRED=true`), and Settings hides Log out, Delete account and Export my data. **B is not fixed**: you chose to keep voice as it is, so ElevenLabs can still keep and reuse voice recordings. D is still open. Not yet done: the policy, Terms and App Privacy answers still describe accounts (Contact Info and User ID), which the app no longer collects while login is off.

I read the primary documents instead of trusting memory. These are not cosmetic, and **none is fixed by wording alone**. Each needs your decision. I did not change the app's design for any of them.

### Blocker A. Both AI providers require users to be 18 or older

- **Google Gemini API Additional Terms** ("Age Requirements"): *"You also will not use the Services as part of a website, application, or other service ... that is directed towards or is likely to be accessed by individuals under the age of 18."*
- **ElevenLabs Terms of Use, section 1(a):** *"If you are under 18 years of age ... you may not use our Services."* Its Privacy Policy adds that nobody may provide it with voice data from anyone under 18.
- Your Privacy Policy and Terms say the app is for **13 and over**, and Talk mode can be reached by a 13-year-old. That breaches both providers' terms, and the providers can cut off your key.
- Gemini also says that for users in the **EEA, Switzerland or the UK** you may use only the **Paid** tier.

Options (pick one; each is reversible):

| | What changes | Cost |
|---|---|---|
| **1. Make Talk mode adult-only** (recommended) | Ask for date of birth or an "I am 18 or older" confirmation before the Talk permission box; hide Talk mode otherwise. The rest of the app stays 13+. Update the Terms, the policy and the Apple age-rating answers to match. | Small code change; still relies on the person being honest. |
| **2. Make the whole app 18+** | Change the minimum age in the Terms/policy and the Apple rating; add an age confirmation at sign-up. | Smallest code, loses teenage learners (likely your main users for a practice app). |
| **3. Remove third-party AI from Talk mode** | Replace Gemini and ElevenLabs with something on the phone or a provider whose terms allow minors (needs research). | Largest change. Also removes Blockers B and the Apple 5.1.2(i) issue. |

### Blocker B. ElevenLabs may keep and reuse voice recordings, permanently

ElevenLabs' Terms (section 4(d)) give it a license to your Content, including voice, *"to improve the Services, and to develop new services and products"*, which is *"perpetual and irrevocable"* and *"sub-licensable"*. Its docs say speech-to-text audio and text are retained **by default**; the zero-retention mode is only for select enterprise customers. The Privacy Policy and the permission box now say this plainly (updated today), but being honest does not make it allowed:

- Apple 5.1.2(i): *"Data collected from apps may only be shared with third parties to improve the app or serve advertising."* Letting a third party improve **its own** products with your users' voices is not obviously allowed.
- Options: (a) **recognise speech on the phone** and send only text (iOS has on-device speech recognition; removes ElevenLabs from Talk mode); (b) get an enterprise agreement with zero retention; (c) type-only Talk mode. I recommend (a). It is a contained change.

### Blocker C. The whole app sits behind a login that does nothing else

Apple 5.1.1(v): *"If your app doesn't include significant account-based features, let people use it without a login."* In the code, `AuthGate` shows the sign-in screen to anyone signed out, and the account holds only an email and password; your shelf, hums and songs live on the phone (your own Privacy Policy says so), and hum requests are not tied to an account on the server. Review can reject this.

Options: (1) let people use practice and hum without an account and make the account optional; (2) give the account a real purpose (for example, saving songs to the cloud) so the login is justified; (3) keep it and explain in the review notes why. Option 1 is the least work and also removes the personal data you need to protect. The age question in Blocker A would then be asked only before Talk mode.

### Blocker D. The policy lacks one sentence Apple requires, and it is not yet true

Apple 5.1.1(i): the policy must *"confirm that any third party with whom an app shares user data ... will provide the same or equal protection of user data as stated in the app's privacy policy"*. I have not added it, because it is false while Gemini runs on the free tier and ElevenLabs keeps and reuses audio. Add it when A, B and the Gemini billing step are done.

---

## Part 1. The copyright screen

**Why it is needed.** PDMX calls itself public domain, but that label is chosen by whoever uploaded each score on MuseScore. Its authors do not verify it, and nothing in their paper addresses arrangements of copyrighted songs. In the real data, game, film and pop music sits in it marked public domain (*Undertale*, Nintendo, Studio Ghibli, Billie Eilish, Coldplay, Disney...). Apple guideline 5.2.1 says an app must come from "the owner or licensee of the IP", so this is an approval risk as well as a legal one.

**The rule** (`backend/scores/clearance.py`). A score is offered only if (1) the uploader's license is `publicdomain` or `cc-zero`, (2) the dataset does **not** flag a `license_conflict`, **and** (3) its composer is in a reviewed list of 242 historic composers (904 recognised spellings of their names) who died in or before **1925** (free under "life + 70" anywhere, and published before 1931 so free in the US too). Everything else is out: "NA", "Traditional", "Anonymous", every modern composer, and look-alikes such as "P.D.Q. Bach".

I tried a fourth route, "the uploader says it is their own composition", and **removed it** after auditing it: it let through covers marked "original" (Billie Eilish, Coldplay, *Frozen 2*, The Police and others). The uploader controls that flag, so it cannot clear anything.

**Result on the real data:**

| | Scores |
|---|---|
| Candidates the app would have imported (deduplicated, rated 4+) | 12,984 |
| **Offered now** | **1,369** |
| Removed | 11,615 (89%) |
| Removed by the dataset's own license-conflict flag | 25,281 of 102,635 (all ratings) |

The top of the library is now Chopin, Mozart, Leclair, Paganini, Debussy, Schubert, Bach and Wagner.

**Commands** (run from `backend/`):

```bash
python manage.py build_clearance               # rules -> scores/clearance/cleared_mxl.txt + clearance_report.json
python manage.py import_pdmx --pdmx-root ...   # only imports cleared scores; refuses to run without the list
python manage.py prune_uncleared               # report scores in the database that are not cleared
python manage.py prune_uncleared --yes --keys-file removed.txt   # remove them (and list their bucket files)
```

If you already filled the production database or the R2 bucket before this existed, run `prune_uncleared --yes --keys-file removed.txt`, then delete every name in `removed.txt` from the bucket (`rclone delete`, or the Cloudflare dashboard).

**Growing the library.** `clearance_report.json` lists the 200 most common composer names that were *not* recognised. Review them; add genuine historic composers (died 1925 or earlier) to `COMPOSERS` in `clearance.py` with their death year, rebuild, and commit. Do not raise `PUBLIC_DOMAIN_DEATH_YEAR` (Ravel d.1937, Rachmaninoff d.1943 and so on) without a lawyer's advice: their music is free in some countries but not clearly in all.

**What it cannot do:**

- A recognised name can still sit on the wrong piece, and a modern edition may carry its own copyright. The screen reduces the risk; it does not remove it.
- It does not read the music or lyrics.
- Hand-written quiz questions are not covered by it (they are your own text).

**When someone complains about a score** (do this promptly; keep the email):

1. Find it: `python manage.py shell -c "from scores.models import Score; print(list(Score.objects.filter(title__icontains='...').values('id','title','composer','pdmx_path','musicxml_path')))"`.
2. Add its `pdmx_path` to `backend/scores/clearance/blocked_mxl.txt` with a dated comment (who asked, when).
3. `python manage.py build_clearance`, commit the new list and blocklist, redeploy.
4. On the server: `python manage.py prune_uncleared --yes --keys-file removed.txt`; delete the names in that file from the R2 bucket.
5. Reply to the person. The Terms promise prompt removal.

---

## Part 2. Step by step

Do these in order; later steps depend on earlier ones. **For creating each account and wiring it to this repo, follow [`accounts-and-setup.md`](accounts-and-setup.md).**

### Step 1. Decide who "AG" is (before you enroll with Apple)

The policy and terms call the publisher **AG**. Apple shows a *seller name* on the App Store, and it must be a real legal party.

- **Individual account:** the seller shown is your **legal name**. No D-U-N-S number needed. Then set `LEGAL_PUBLISHER` on the server to your legal name (or "Your Name, trading as AG") so the pages and Apple name the same person. Simplest, and fine to start.
- **Organization account:** the seller can be "AG", but only if AG is a **recognised legal entity** (a corporation, not a sole proprietor's trade name; Apple rejects DBAs and trade names) with a **D-U-N-S number** (free; Apple says allow up to 5 business days). It costs more effort and money to set up, and separates your personal liability from the app's.

If the app will earn money, take advice on incorporating. If not, start as an individual. A secondary source says an account can be converted later; confirm with Apple Developer Support.

- [ ] Choose individual or organization. If organization: register the entity, get the D-U-N-S number.
- [ ] Set `LEGAL_PUBLISHER` to the matching name when you deploy.

### Step 2. Make the public identity real

- [ ] Buy a domain you control (optional but recommended; an email at your own domain looks credible and survives changing providers).
- [ ] Create the **support address** and make sure you read it daily. It is printed on the Privacy Policy, Terms and Support pages. The server will not start in production with a placeholder.
- [ ] Decide who is "the person responsible for privacy". The policy names the publisher and the support address. Quebec's private-sector privacy Act (s. 3.1) makes the person with the highest authority in the business the person in charge unless they delegate it in writing, and requires that person's **title and contact details to be published on the website**; s. 3.2 requires governance policies to be published in plain language ([statute](https://www.legisquebec.gouv.qc.ca/en/document/cs/p-39.1)). If someone other than you holds that role, change the wording in `backend/legal/privacy.html`.
- [ ] Keep a **breach record**. Under federal law (PIPEDA and its Breach of Security Safeguards Regulations) you must record every breach of security safeguards for **24 months** and report breaches with a real risk of significant harm to the Privacy Commissioner and the people affected; the sources I found disagree on whether the 24 months run from the breach or from when you learned of it, so ask your lawyer. A text file with date, what happened and what you did is enough to start.

### Step 3. Enroll in the Apple Developer Program

- [ ] Use an Apple ID with two-factor authentication. Enroll at developer.apple.com/programs. The fee is **US$99 per membership year** ([Apple](https://developer.apple.com/programs/whats-included/); waivers exist only for eligible nonprofits, accredited schools and government entities). Approval can take days.
- [ ] In App Store Connect, accept the **Free Apps agreement**. To my knowledge a free app needs no bank or tax details; if you ever charge or add in-app purchases you must complete the Paid Apps agreement, bank and tax forms first.

### Step 4. Declare your Digital Services Act trader status

Required by Apple **even if you do not sell in the EU**. In App Store Connect: App Information, then the Digital Services Act section (only the Account Holder or Admin can edit it).

- A **trader** is someone acting for business or professional purposes. If you declare yourself a trader, Apple verifies your **address, phone number and email** (it sends codes to the phone and email) and **shows them publicly** on your product page in the EU.
- Whether you are a trader depends on your plans and on the law; ask a lawyer if unsure.

- [ ] Declare the status. If trader: have a reachable phone and email, and decide whether you are comfortable with a public address (a business address is better than home).

### Step 5. Make the outside services legal for this use

These are real privacy exposures today.

- [ ] **Gemini: put the key on a billing-enabled Google Cloud project.** Google's terms: access is a Paid Service only *"through a Cloud Project associated with an active billing account"*. The Unpaid Services let Google *"use the content you submit ... to provide, improve, and develop Google products"*, let human reviewers read it, and say *"Do not submit sensitive, confidential, or personal information to the Unpaid Services."* The paid tier is not used for that. Once done, you may add: *"We use Google's paid Gemini service, which Google says does not use requests to improve its products."* Not before it is true.
- [ ] **Blockers A and B above** (18+ and ElevenLabs).
- [ ] Accept the terms and any data processing addendum for **Google Cloud, Neon and Cloudflare**; check each for a standard addendum (I did not verify that each offers one).
- [ ] **Neon's free plan suspends the database after 5 minutes idle** and keeps only 6 hours of restore history ([Neon plans](https://neon.com/docs/introduction/plans)). The first request after a quiet spell is slow, which can look like a broken app to App Review, and a mistake older than 6 hours cannot be undone. Take the paid plan, or turn off scale-to-zero, before you submit.
- [ ] **Cloud Run logs keep each request's IP address for 30 days** by default (the `_Default` log bucket; [Google](https://docs.cloud.google.com/logging/quotas)), so the policy's "limited time" is right and the Apple label declares it (Other Diagnostic Data). You may shorten it in Logging settings.
- [ ] Note in a file where each service is, so the policy ("mainly the United States") stays true.

### Step 6. Have a lawyer read it (one session)

Send them `/privacy`, `/terms`, `/support` and this document. Ask specifically:

1. Is the **governing-law** clause right for where you live (I wrote "the province or territory of Canada where the publisher is based")?
2. Is the **liability limit** (greater of 12 months' payments or CAD $50) acceptable and enforceable?
3. Do you need to **appoint a privacy officer**, keep a **breach register**, or take other steps under PIPEDA and Quebec's Law 25 (the sources I found were vendor blogs, not the statute)?
4. If you let EU/UK people download the app, do you need an **EU/UK representative** under GDPR?
5. Is "AG" a legal party, and are **you** personally exposed under Step 1's choice?
6. Is the **PDMX screen** (Part 1) enough care, and is the **takedown process** adequate? Do you need an agent registered under US copyright law for notices?
7. Is the **Apple clause** block in the Terms enough if you rely on it instead of Apple's standard agreement?
8. Given the providers' **18+ rules** and ElevenLabs' perpetual license (Blockers A and B), what is the safest design for Talk mode, and is a self-declared age check enough?
9. Do you need the **Quebec governance policy** (s. 3.2) as a separate published document, or does the Privacy Policy cover it?

- [ ] Book it. Update the pages with their changes (edit `backend/legal/*.html`, bump `EFFECTIVE_DATE` in `backend/server/legal.py`, redeploy).

### Step 7. Narrow where you launch (strongly recommended)

In App Store Connect, Pricing and Availability, choose the countries. **Start with Canada** (and the US if you want) instead of everywhere. Each region adds laws to follow (GDPR and EU trader display, age-assurance laws such as Texas's App Store Accountability Act, which a source says took effect June 4, 2026 and may have developer obligations; check Apple's developer news for Texas if you include the US). You can add countries later.

- [ ] Pick launch territories.

### Step 8. Finish the app work only a developer machine can do

- [x] **iOS platform installed** (done 2026-10-15). It must **match the Xcode's SDK build exactly**: Xcode 26.4.1 needs iOS 26.4.1 (`xcodebuild -downloadPlatform iOS`, with no version flag). Asking for "26.4" installs the wrong build and the device destination still says "iOS 26.4 is not installed". The simulator app and the release device app (53.5 MB) both build now.
- [ ] **SDK rule.** Apple's submit page (checked 2026-10-15) says that **from April 2027** uploads must be built with the **iOS 27 SDK (Xcode 27) or later and target iOS 15 or later**. Builds from Xcode 26.4.1 should be accepted until then, but plan to move to Xcode 27 before April 2027; check the page again before you submit.
- [ ] **Final bundle ID.** It is still the placeholder `com.example.huAccomponist`. Pick your own reverse-domain ID (for example `com.yourdomain.accomponist`) in Xcode *before* you create the app in App Store Connect; it cannot be changed after release.
- [ ] **App icon.** The icon set has not been touched since the project was created and is almost certainly still Flutter's default. Design a real 1024×1024 icon (no transparency).
- [ ] **Artwork ownership.** The only bundled image is `assets/images/wave.png`; confirm you own or license it. (The OpenSheetMusicDisplay viewer ships with its license file.)
- [ ] **Third-party notices.** The in-app "Open-source licenses" screen lists Dart and Flutter packages only. The Rust engine's libraries and the bundled pitch model are under licenses (Apache-2.0 and similar) that expect their notices to ship with the app, and the bundled viewer's license is not on that screen. Ask me to add them.
- [ ] **Backend connection** (still open): the app must send `X-App-Key`, use the fixed `https://` address, and have the three local-network entries removed from `Info.plist`.
- [x] **Minimum iOS is 15.0** (Flutter raised it; Apple's page above requires iOS 15 or later from April 2027, so I kept it). Commit the project file when you commit this work.
- [ ] **Build:** `flutter build ipa` with the three `--dart-define`s from `submission-checklist.md`, then Product, Archive, **Generate Privacy Report** and check it lists the manifest. `C617.1` was checked against Apple's definition ("metadata of files inside the app container"), and the compiled release app imports only `stat`, `lstat`, `fstat` and `fstatat` from Apple's required-reason list, so the manifest's one declaration is complete. `frontend/test/privacy_manifest_test.dart` pins the manifest.
- [ ] **Test on a real iPhone**: sign up, practise, hum, Talk mode (the permission box), log out, delete the account. Then **TestFlight** to yourself.

### Step 9. Fill in App Store Connect

Create the app (bundle ID from Step 8), then:

- [ ] Name, subtitle, description, keywords; categories (Music, perhaps Education as secondary).
- [ ] Screenshots: at least one for the **iPhone with Dynamic Island (medium display)** size class (1 to 10 per size, JPEG or PNG), plus one for iPad 13-inch only if the app supports iPad ([Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)). The app name is 2 to 30 characters. The 1024 icon.
- [ ] **Privacy Policy URL** `https://<service-url>/privacy`, **Support URL** `.../support`.
- [ ] **App Privacy** answers: copy them from section 2 of `submission-checklist.md`.
- [ ] **Age rating questionnaire.** Apple replaced the old tiers with 4+, 9+, 13+, 16+ and 18+ and added questions, including about AI chatbot features; answer for Talk mode honestly. (Apple's deadline for existing apps to answer the new questions was January 31, 2026; you will answer the current version when you create the app.)
- [ ] **Content Rights:** answer that the app shows third-party content, and confirm you have the rights. Keep `clearance_report.json` and the PDMX download's hash as your evidence.
- [ ] **Export compliance** (already declared in the app: standard encryption only).
- [ ] **App Review Information:** a demo account on the production server, working notes, the backend running (guideline 2.1(a) requires working URLs and a live backend). Notes text is in `submission-checklist.md`.
- [ ] Copyright line (for example "© 2026 <publisher>"), price Free, release manually after approval.

### Step 10. Submit and handle review

Guidelines most likely to come up for this app: 2.1 (app must work; backend up; demo account), 5.1.1 and 5.1.2 (privacy policy in app and listing, account deletion, permission before sharing with third-party AI), 5.2.1 (IP), 4.2 (minimum functionality; yours is clearly an app). Reply in the Resolution Center with specifics. First reviews often take a day or two but vary.

- [ ] Submit; watch for questions; keep the backend and the demo account working until approved.

### Step 11. After launch

- [ ] Reply to privacy requests within 30 days (the policy promises that). Export and deletion are self-service.
- [ ] Act on a takedown complaint quickly using Part 1.
- [ ] Watch the Google Cloud budget alert and the Gemini/ElevenLabs bills.
- [ ] Keep the pages, `PrivacyInfo.xcprivacy` and the App Privacy answers in sync whenever the app starts sending data somewhere new. Bump `EFFECTIVE_DATE` when the text changes.
- [ ] Renew the Apple membership every year, or the app disappears.
- [ ] Apple has been raising the minimum SDK for uploads once a year (the iOS 26 SDK became required on April 28, 2026), so expect to rebuild with newer Xcode at least yearly.

---

## Part 3. Risks that remain

- **Mislabelled or misattributed scores.** The screen is cautious but not perfect. Mitigation: the blocklist and a fast response.
- **AI services keep data.** ElevenLabs may keep recordings. The policy and the consent box say so; moving speech recognition onto the phone would remove it.
- **Still unverified.** Whether free apps need tax or bank forms; the Texas law's developer obligations (news sources only); the 24-month breach-record trigger date; whether ElevenLabs section 4(d) applies to speech-to-text audio sent through its API exactly as written (read it as applying until they say otherwise); that Cloud Run's request log entries include the client IP (the logging pages show an `httpRequest` field; the IP field is documented elsewhere); the legal status of "AG". Verified against primary sources on 2026-10-15: Apple's guidelines (updated June 8, 2026), the minimum-SDK page, the required-reason API list, the App Privacy definitions, the screenshot sizes, the $99 fee, Gemini and ElevenLabs terms, Neon, Cloud Run and R2 pricing, and the Quebec statute.

---

## Sources

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (5.1.1, 5.1.2(i), 5.2.1, 4.8, 2.1(a), 4.2)
- [Apple: submit your apps (minimum SDK since April 28, 2026)](https://developer.apple.com/ios/submit/)
- [Apple: Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) (definition of "collect"; retained IP addresses)
- [Apple: D-U-N-S numbers and organization enrollment](https://developer.apple.com/support/d-u-n-s/)
- [Apple: Digital Services Act trader status in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-eu-digital-services-act-compliance-information)
- [Apple age ratings update (9to5Mac)](https://9to5mac.com/2025/07/24/apple-notifies-developers-of-new-app-store-age-rating-system/)
- [PDMX dataset record and license (Zenodo)](https://zenodo.org/records/15571083) and [paper](https://arxiv.org/abs/2409.10831)
- [Gemini API additional terms (18+, paid vs unpaid data use, EEA/UK paid only)](https://ai.google.dev/gemini-api/terms)
- [ElevenLabs Terms of Use (18+, section 4(d) license)](https://elevenlabs.io/terms-of-use) and [Privacy Policy](https://elevenlabs.io/privacy-policy)
- [Cloud Logging retention](https://docs.cloud.google.com/logging/quotas), [Cloud Run pricing](https://cloud.google.com/run/pricing), [Neon plans](https://neon.com/docs/introduction/plans), [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- [Quebec private-sector privacy Act, s. 3.1 and 3.2](https://www.legisquebec.gouv.qc.ca/en/document/cs/p-39.1) and [Breach of Security Safeguards Regulations (SOR/2018-64)](https://gazette.gc.ca/rp-pr/p2/2018/2018-04-18/html/sor-dors64-eng.html)
- [ElevenLabs zero retention mode](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode)
- [Quebec Law 25 overview (BCLP)](https://www.bclplaw.com/en-US/events-insights-news/quebec-law-no-25-a-little-known-privacy-law-with-a-big-reach.html)
- [Texas App Store age-verification law and Apple's response (Tom's Guide)](https://www.tomsguide.com/phones/iphones/texass-age-verification-law-means-apple-has-had-to-change-part-of-the-app-store-heres-what-that-means-for-you)
