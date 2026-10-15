# App Store submission checklist

The full ordered list of what you do yourself, including the legal questions and the copyright screen of the score library, is in [`legal-and-shipping.md`](legal-and-shipping.md). This file is the App Store Connect reference.

What to enter in App Store Connect, what to answer, and what App Review will look for. The pages and the privacy manifest are built; this lists the rest. It assumes the backend is deployed (see `backend/deploy/README.md`) and that the Apple Developer account exists.

## 1. The addresses Apple asks for

Once the backend is deployed at `https://<service-url>`:

| App Store Connect field | Value |
|---|---|
| App Information > Privacy Policy URL | `https://<service-url>/privacy` |
| Version page > Support URL | `https://<service-url>/support` |
| Version page > Marketing URL | optional; leave empty |
| App Information > License Agreement | Apple's standard agreement is fine. `https://<service-url>/terms` is the app's own Terms of Service, and already includes Apple's required clauses if you choose a custom agreement. |

Build the app so its in-app links and support address point at the same places:

```bash
flutter build ipa \
  --dart-define=PRIVACY_POLICY_URL=https://<service-url>/privacy \
  --dart-define=TERMS_OF_SERVICE_URL=https://<service-url>/terms \
  --dart-define=SUPPORT_EMAIL=<your support address>
```

The defaults in `frontend/lib/config/app_constants.dart` end in `.example` and never resolve. **A build made without these three flags links to dead pages**, which is a rejection.

The server shows the support address on the pages, so it must match: set `SUPPORT_EMAIL` on the service (production refuses to start without a real one). To change the publisher name, set `LEGAL_PUBLISHER` (default `AG`; it should match the name on your Developer account).

## 2. App Privacy answers ("nutrition label")

Declare these. They match `frontend/ios/Runner/PrivacyInfo.xcprivacy` and the public Privacy Policy; if one changes, change all three.

| Data type | Collected | Linked to the person | Used to track | Purpose |
|---|---|---|---|---|
| Contact Info > Email Address | Yes | Yes | No | App Functionality |
| Contact Info > Name (optional at sign-up) | Yes | Yes | No | App Functionality |
| Identifiers > User ID | Yes | Yes | No | App Functionality |
| User Content > Audio Data (hum recordings; Talk mode voice) | Yes | No | No | App Functionality |
| User Content > Other User Content (Talk mode requests; notes detected while practising) | Yes | No | No | App Functionality |
| Diagnostics > Other Diagnostic Data (IP address in the hosting provider's request log) | Yes | No | No | App Functionality |

Everything else: not collected. **Tracking: No.** The app has no analytics, advertising or tracking code.

Judgement calls to confirm yourself, because Apple's wording is not always clear:

- **IP addresses (changed after checking Apple's text).** Apple says data sent to a server and "not retained" need not be declared, but "if you collect and store IP address" you declare it by how you use it, such as diagnostics. Cloud Run's request log keeps the client IP, so it is declared as Other Diagnostic Data (not linked, not tracking). The manifest has the same entry and `frontend/test/privacy_manifest_test.dart` pins the list. Confirm the log retention in your Google Cloud project's Logging settings.
- **Search text and quiz topics** go to the server but are not kept, so they are not declared.
- **Third parties.** Audio goes to ElevenLabs and Talk mode text to Google Gemini. That is already covered by the Audio Data and Other User Content rows above; Apple counts partners' collection too.

## 3. Things Apple checks, and where each stands

| Requirement | Status |
|---|---|
| Privacy Policy link inside the app | Done: Settings > Privacy Policy, and on the sign-in screen |
| Privacy Policy and Terms pages exist and open without signing in | Done: `/privacy`, `/terms`, `/support` on the backend, no key needed |
| In-app account deletion (5.1.1(v)) | Done: Settings > Delete account, which deletes the server account |
| Data export | Done: Settings > Export my data |
| Sign in with Apple | Not required: the app has its own email and password sign-in and no Google/Facebook-style login |
| Clear permission to share data with third-party AI (5.1.2(i)) | Done: Talk mode asks first (names Google Gemini and ElevenLabs), nothing is sent and the microphone does not start until the person agrees, and Settings > Talk mode and AI services withdraws it |
| Microphone purpose string | Done: says it hears playing, humming and voice |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | Added and registered in the Runner target. It declares the data in section 2 and one required-reason API (file timestamps, reason `C617.1`, from the Rust engine's `stat`/`lstat`); I checked the linked library by name and found no boot-time, uptime, disk-space or user-defaults calls. Plugins and Flutter carry their own manifests. Confirm with Generate Privacy Report (section 5). |
| Export compliance | Done: `ITSAppUsesNonExemptEncryption` is false (standard HTTPS and the Keychain only) |
| **Local network permission** | **Still to do.** The app still has `NSLocalNetworkUsageDescription`, `NSBonjourServices` and `NSAllowsLocalNetworking` in `Info.plist` because it finds the server by mDNS. Once the app uses the fixed `https://` address, delete those three, or iPhones show a "find devices on your local network" prompt Review will ask about. |
| App talks to the server with its key | **Still to do.** The app does not send `X-App-Key` yet and still discovers the server by mDNS. |

## 4. What to give App Review

The app needs an account, so Review needs one too (App Store Connect > App Review Information > Sign-in required).

1. Create a real account on the production server for Review (an email you control and a strong password) and enter it there.
2. Notes to paste, adjusted as needed:
   > Sign in with the demo account. Practice mode listens to an instrument through the microphone. Hum mode: tap the record button and hum for a few seconds; a song is generated. Talk mode (on the Hum screen) asks permission first because it sends the request to Google Gemini and, for voice, ElevenLabs. To delete the account: Settings > Delete account. Privacy policy: https://<service-url>/privacy
3. The server must be up and the database reachable when Review tests, and for the weeks after. The service runs one always-on instance for this reason.

## 5. Before you press submit

- [ ] Backend deployed; `/healthz`, `/privacy`, `/terms`, `/support` open in a browser on your phone.
- [ ] Built with the three `--dart-define`s above.
- [ ] Open the pages and read them once, as a user would. They state what the app really does today; if you add a feature that sends data somewhere new, update `backend/legal/privacy.html`, `PrivacyInfo.xcprivacy` and section 2, and bump `EFFECTIVE_DATE` in `backend/server/legal.py`.
- [ ] In Xcode: Product > Archive > Distribute > Generate Privacy Report. Confirm it lists the manifest.
- [ ] Local network entries removed (section 3).
- [ ] On a real iPhone: sign up, practise, hum, use Talk mode (see the permission box), then log out and delete the account.
- [ ] Age Rating questionnaire. The app has no user-to-user content, but answer the AI-feature questions honestly (Talk mode uses third-party AI to interpret requests).
- [ ] If you distribute in the EU, set your Digital Services Act trader status in App Store Connect (needs your address and phone if you are a trader).
- [ ] Screenshots, description and keywords (yours).

## What I could not verify

- **Apple's current rules.** Checked against the App Review Guidelines page as updated June 8, 2026, including 5.1.1, 5.1.2(i), 5.2.1, 2.1(a) and 4.8. Apple changes them often; re-read 5.1.1 and 5.1.2 just before you submit. See `legal-and-shipping.md` for four problems the checks turned up (age 18+, ElevenLabs, login, and one missing policy sentence).
- **The legal text.** The Privacy Policy and Terms were written from how the code actually behaves and use standard clauses, but I am not a lawyer. Have someone qualified read them if you can, especially the liability limit and the governing-law paragraph.
- **Signing, archive and upload.** The app now builds on this Mac (simulator, and a release device build without code signing), and I confirmed in the built app that the manifest and every plugin's manifest are bundled, `MinimumOSVersion` is 15.0, and the export-compliance and microphone keys are present. I could not sign, archive or validate with App Store Connect, because that needs your Apple Developer account. Run Product > Archive > Validate before submitting.
- **Minimum iOS is now 15.0** in the project file (Flutter's automatic change, which I kept). Apple's submit page says apps must target iOS 15 or later from April 2027, so this is needed anyway. It drops iPhones still on iOS 13 and 14.
- **The App Privacy judgement calls** in section 2.
