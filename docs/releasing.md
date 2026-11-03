# Releasing Accompanist (Mac and Windows) and publishing updates

Pushing a version tag builds the Mac and Windows apps on GitHub and publishes them as one GitHub Release:

```bash
git tag v0.2.0
git push origin v0.2.0
```

That is the whole release. People get it three ways, with nothing else to do:

- **New people**: the website's download buttons go to `accompanist.app/download/mac` and `/download/windows`, which Cloudflare forwards (`website/_redirects`) to the newest release's file. The browser just downloads it; visitors never see GitHub, and the website does not need redeploying for a new version.
- **People who have the app**: it checks for a newer release each time it starts and shows "Accompanist 0.2.0 is out" with a **Download** button. On a Mac they drag the new app over the old one; on Windows they run the new installer, which closes and replaces the old one. Scores and settings stay.
- **The release page** (`github.com/Accompanist-Guild/hu-accompany/releases`) lists every version with install instructions (`.github/release-notes.md`).

## Before the first release (once)

At **Settings > Secrets and variables > Actions** on GitHub, set:

| Name | Kind | Value |
|---|---|---|
| `SERVER_URL` | Variable | `https://hu-accompany-u4wd4ohuga-uc.a.run.app` (the deployed backend; must start with `https://`). Unset, the app only looks for a server on the local network, which is no use to someone who downloads it. |
| `APP_KEY` | **Secret** | The server's `APP_API_KEY` (`backend/deploy/setup.sh` prints how to read it). It ends up inside the downloadable apps, so anyone can extract it: it keeps casual traffic out, and the server's rate limits are the real protection. |
| `PRIVACY_POLICY_URL`, `TERMS_OF_SERVICE_URL`, `SUPPORT_EMAIL` | Variables | Optional. Unset, the app uses the server's own `/privacy` and `/terms` pages and support@accompanist.app. |
| `TALK_MODE` | Variable | Leave unset for now. `true` includes Talk mode, which runs on Gemini and ElevenLabs and costs money per use; the release notes say it is not included, so edit them if you turn it on. |

Then try the whole pipeline without publishing anything: **Actions > Release > Run workflow**. It builds and checks both apps and leaves them as downloads on the run page. Install each one on a real computer and play a few notes before pushing the first tag.

## Publishing an update

1. Make the changes, and check them: `cd frontend && flutter analyze && flutter test`.
2. Raise `version:` in `frontend/pubspec.yaml` (for example `0.1.0+1` to `0.2.0+2`). The tag decides the released version; this keeps manual runs and local builds numbered sensibly.
3. Commit, push, then tag that commit with the new version and push the tag (above).
4. Watch the **Release** run under Actions (about 30 to 45 minutes; the jobs run side by side). When it is green, the release is live.

Rules for the version number:

- It must go up. The apps only offer a version higher than their own, compared like `1.2.3`.
- `v1.2.3-beta.1` is published as a **pre-release**: it is on the releases page for testers, but the website and the apps' update check ignore it.
- A broken release is fixed by releasing a higher version. Re-running a tag's workflow replaces its files, but people who already downloaded it keep what they have.

If the change also touched the server (`backend/`), deploy it first, so the new apps never meet an old server: `backend/deploy/update.sh` (new code only; the server's settings stay as they are). If it touched the website (`website/`), deploy that with `website/deploy.sh`.

## What the workflow does (`.github/workflows/release.yml`)

1. `ci.yml` runs `flutter analyze` and `flutter test`. If either fails, nothing is built.
2. **macOS** (on a Mac runner): builds a universal app (Intel and Apple silicon, with the Rust audio engine compiled in), packs `Accompanist-macos.dmg` (`scripts/package_macos_dmg.sh`), and checks it: signature intact, both CPU types present, microphone permission present, the version number right, and the app still running 10 seconds after starting with its Rust engine found.
3. **Windows** (on a Windows runner): runs `integration_test/simple_test.dart` on Windows (the app starts and its Rust engine loads), builds the app, adds the Visual C++ runtime beside it, checks the engine, score viewer and audio libraries are all there, makes `Accompanist-windows-setup.exe` with Inno Setup (`scripts/windows_installer.iss`), then installs it silently and checks the installed app starts and stays running.
4. **Publish** (tags only): creates the release with both files and `SHA256SUMS.txt`.

Every build gets `UPDATE_FEED` (GitHub's "latest release" address), which is what turns the update check on. Builds made any other way, including the App Store build, never check: Apple delivers App Store updates and does not allow pointing people elsewhere.

## What these builds are, and are not

- **Not signed.** macOS shows a warning the first time, and Windows SmartScreen says it "protected your PC"; the release notes and the website say how to get past both. Removing the Mac warning needs an Apple Developer account (US$99/year) and a signing and notarizing step in the macOS job. Removing the Windows one needs a code-signing certificate (or Azure Trusted Signing) and a signing step before the installer is made; SmartScreen also relaxes as a signed app gets downloaded more.
- **Updates are offered, not installed.** The app says a new version is out and downloads it; the person installs it. Installing silently in the background (Sparkle on the Mac, for example) needs the apps to be signed first.
- **Windows needs WebView2** to show scores. Windows 11 has it, and Windows 10 gets it with Microsoft Edge; without it the score view says to install it.
- **Needs a server.** Hum mode, the library and the quiz talk to the backend (`SERVER_URL`). The website's demo reads the same library through the server's public score routes.
- **Bundle ID is `app.accompanist`** on the Mac, and the Windows installer's `AppId` is fixed in `scripts/windows_installer.iss`. Never change either: the system would treat the new app as a different one, so updates would install beside the old app and leave its data behind.

## Why Flutter is pinned

`flutter pub get` and `flutter build` on a different Flutter version re-resolve some packages and can raise the macOS minimum version by themselves. That happened here (10.15 to 12.0). Both workflows use 3.47.2 so the build matches what was tested. To upgrade, change the version in both workflow files together, then build locally and commit whatever Flutter changes.
