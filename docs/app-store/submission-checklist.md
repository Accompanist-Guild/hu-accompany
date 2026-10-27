# App Store submission checklist

The full ordered list of what you do yourself, including the legal questions and the copyright screen of the score library, is in [`legal-and-shipping.md`](legal-and-shipping.md). This file is the App Store Connect reference.

What to enter in App Store Connect, what to answer, and what App Review will look for. The pages and the privacy manifest are built; this lists the rest. It assumes the backend is deployed (see `backend/deploy/README.md`) and that the Apple Developer account exists.

## 1. The addresses Apple asks for

The backend is deployed at `https://hu-accompany-u4wd4ohuga-uc.a.run.app` (Cloud Run, since 2026-10-24):

| App Store Connect field | Value |
|---|---|
| App Information > Privacy Policy URL | `https://hu-accompany-u4wd4ohuga-uc.a.run.app/privacy` |
| Version page > Support URL | `https://hu-accompany-u4wd4ohuga-uc.a.run.app/support` |
| Version page > Marketing URL | `https://accompanist.app` |
| App Information > License Agreement | Apple's standard agreement is fine. `https://hu-accompany-u4wd4ohuga-uc.a.run.app/terms` is the app's own Terms of Service, and already includes Apple's required clauses if you choose a custom agreement. |

The pages follow the server's `LOGIN_REQUIRED` and `TALK_MODE` settings (both off unless set), the same switches the app is built with, so they describe the app as released: no accounts, no Talk mode. If you ever build the app with either switched on, set the same variable on the Cloud Run service first, or the policy won't mention what the app does. With `TALK_MODE` off the server also refuses Talk mode requests, so nothing can reach Gemini or ElevenLabs while the policy leaves them out.

Build the app with the server address and key; the in-app Privacy Policy and Terms links then default to the same server's pages, and the support address defaults to `support@accompanist.app`:

```bash
flutter build ipa \
  --dart-define=SERVER_URL=https://hu-accompany-u4wd4ohuga-uc.a.run.app \
  --dart-define=APP_KEY=<the app-api-key secret from Google Cloud>
```

**A build without `SERVER_URL` can't reach the server and links to pages on accompanist.app that don't exist**, which is a rejection.

The server shows the support address on the pages, so it must match: set `SUPPORT_EMAIL` on the service (production refuses to start without a real one). To change the publisher name, set `LEGAL_PUBLISHER` (default `AG`; it should match the name on your Developer account).

## 2. App Privacy answers ("nutrition label")

Declare these for the app as released (no accounts, no Talk mode). They match `frontend/ios/Runner/PrivacyInfo.xcprivacy` and the public Privacy Policy; if one changes, change all three.

| Data type | Collected | Linked to the person | Used to track | Purpose |
|---|---|---|---|---|
| User Content > Audio Data (hum recordings, deleted after a few hours) | Yes | No | No | App Functionality |
| User Content > Other User Content (notes detected while practising, with the piece's title) | Yes | No | No | App Functionality |
| Diagnostics > Other Diagnostic Data (IP address in the hosting provider's request log) | Yes | No | No | App Functionality |

Everything else: not collected. **Tracking: No.** The app has no analytics, advertising or tracking code.

If a later version turns on accounts (`LOGIN_REQUIRED`), add Contact Info > Email Address, Contact Info > Name and Identifiers > User ID, all *linked*, to the answers and the manifest. Talk mode (`TALK_MODE`) adds no new type (its voice and requests fall under the two User Content rows), but the policy then names Gemini and ElevenLabs.

Judgement calls to confirm yourself, because Apple's wording is not always clear:

- **IP addresses (changed after checking Apple's text).** Apple says data sent to a server and "not retained" need not be declared, but "if you collect and store IP address" you declare it by how you use it, such as diagnostics. Cloud Run's request log keeps the client IP, so it is declared as Other Diagnostic Data (not linked, not tracking). The manifest has the same entry and `frontend/test/privacy_manifest_test.dart` pins the list. Confirm the log retention in your Google Cloud project's Logging settings.
- **Search text and quiz topics** go to the server but are not kept, so they are not declared.
- **Third parties.** Audio goes to ElevenLabs and Talk mode text to Google Gemini. That is already covered by the Audio Data and Other User Content rows above; Apple counts partners' collection too.

## 3. Things Apple checks, and where each stands

| Requirement | Status |
|---|---|
| Privacy Policy link inside the app | Done: Settings > Privacy Policy, and on the sign-in screen |
| Privacy Policy and Terms pages exist and open without signing in | Done: `/privacy`, `/terms`, `/support` on the backend, no key needed |
| In-app account deletion (5.1.1(v)) | Not applicable: the released app has no accounts (login is off, and Settings hides Log out, Delete account and Export my data). With accounts on: Settings > Delete account |
| Login only where needed (5.1.1(v)) | Done: no login at all |
| Sign in with Apple | Not required: no sign-in |
| Clear permission to share data with third-party AI (5.1.2(i)) | Not applicable: Talk mode is not in the released app, and the server refuses it. When it returns, it asks first (names Google Gemini and ElevenLabs) |
| Microphone purpose string | Done: says it hears playing, humming and voice. With Talk mode off, "voice" is unused but harmless; shorten it if Review asks |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | Added and registered in the Runner target. It declares the data in section 2 and one required-reason API (file timestamps, reason `C617.1`, from the Rust engine's `stat`/`lstat`); I checked the linked library by name and found no boot-time, uptime, disk-space or user-defaults calls. Plugins and Flutter carry their own manifests. Confirm with Generate Privacy Report (section 5). |
| Export compliance | Done: `ITSAppUsesNonExemptEncryption` is false (standard HTTPS and the Keychain only) |
| Local network permission | Done: Release builds drop `NSLocalNetworkUsageDescription`, `NSBonjourServices` and `NSAllowsLocalNetworking` (the "Strip local network keys" build phase), so no local-network prompt. Debug builds keep them for finding a server on your laptop |
| App talks to the server with its key | Done: a build with `SERVER_URL` uses that address only (never searches the network) and sends `X-App-Key` |
| App icon | Done (2026-10-27): 1024 px, opaque |
| Bundle ID | `app.accompanist` |

## 4. What to give App Review

The released app has no sign-in, so untick **Sign-in required** in App Store Connect > App Review Information.

1. Notes to paste, adjusted as needed:
   > No account is needed. Practice: open any score from the library, tap the record button and play the piece on a piano or other instrument near the device; the score marks each note as right or wrong as you play, and a summary appears when you finish. If you have no instrument, playing a recording of the piece from another device works. Hum: tap the record button on the Hum screen and hum for a few seconds; a song is made from it. The microphone is used only while recording. Privacy policy: https://hu-accompany-u4wd4ohuga-uc.a.run.app/privacy
2. The server must be up and the database reachable when Review tests, and for the weeks after. The service runs one always-on instance for this reason; Neon's free plan still sleeps the database after 5 idle minutes (see legal-and-shipping.md, Step 5).

## 5. Before you press submit

- [ ] Backend deployed; `/healthz`, `/privacy`, `/terms`, `/support` open in a browser on your phone.
- [ ] Built with `SERVER_URL` and `APP_KEY` above.
- [ ] Open the pages and read them once, as a user would. They state what the app really does today; if you add a feature that sends data somewhere new, update `backend/legal/privacy.html`, `PrivacyInfo.xcprivacy` and section 2, and bump `EFFECTIVE_DATE` in `backend/server/legal.py`.
- [ ] In Xcode: Product > Archive > Distribute > Generate Privacy Report. Confirm it lists the manifest.
- [ ] On a real iPhone: practise a piece, hum a song, open Privacy Policy and Terms from Settings, and check no local-network prompt appears.
- [ ] Age Rating questionnaire. The app has no user-to-user content, but answer the AI-feature questions honestly (Talk mode uses third-party AI to interpret requests).
- [ ] If you distribute in the EU, set your Digital Services Act trader status in App Store Connect (needs your address and phone if you are a trader).
- [ ] Screenshots, description and keywords (yours).

## What I could not verify

- **Apple's current rules.** Checked against the App Review Guidelines page as updated June 8, 2026, including 5.1.1, 5.1.2(i), 5.2.1, 2.1(a) and 4.8. Apple changes them often; re-read 5.1.1 and 5.1.2 just before you submit. See `legal-and-shipping.md` for four problems the checks turned up (age 18+, ElevenLabs, login, and one missing policy sentence).
- **The legal text.** The Privacy Policy and Terms were written from how the code actually behaves and use standard clauses, but I am not a lawyer. Have someone qualified read them if you can, especially the liability limit and the governing-law paragraph.
- **Signing, archive and upload.** The app now builds on this Mac (simulator, and a release device build without code signing), and I confirmed in the built app that the manifest and every plugin's manifest are bundled, `MinimumOSVersion` is 15.0, and the export-compliance and microphone keys are present. I could not sign, archive or validate with App Store Connect, because that needs your Apple Developer account. Run Product > Archive > Validate before submitting.
- **Minimum iOS is now 15.0** in the project file (Flutter's automatic change, which I kept). Apple's submit page says apps must target iOS 15 or later from April 2027, so this is needed anyway. It drops iPhones still on iOS 13 and 14.
- **The App Privacy judgement calls** in section 2.
