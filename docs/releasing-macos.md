# Releasing the macOS app

Pushing a version tag builds the Mac app on GitHub and publishes it as a downloadable `.dmg`.

```bash
git tag v0.1.0
git push origin v0.1.0
```

The tag must look like `v1.2.3` (or `v1.2.3-beta.1`). Then watch the **Release macOS** run under the repo's Actions tab. When it finishes, the file is under **Releases** (the release page is where people download it).

To try the pipeline without publishing anything, open Actions > Release macOS > **Run workflow**. It builds and tests everything and leaves the `.dmg` as a download on the run page, but creates no release.

## What the workflow does

1. `ci.yml` runs `flutter analyze` and `flutter test`. If either fails, nothing is built.
2. Builds the app with Flutter 3.47.2 (pinned, see below) as a universal binary: Intel and Apple silicon. This also compiles the Rust audio engine.
3. Packs it into `HuAccomponist-<version>-macos.dmg` with a `.sha256` checksum (`scripts/package_macos_dmg.sh`).
4. Checks the packaged app: signature intact, both CPU types present, microphone permission present, and the app is still running 10 seconds after starting.
5. Creates the release with install instructions (`.github/release-notes-macos.md`) and the commit list.

Re-running a tag's workflow replaces the files on the existing release.

## Settings the release reads

Set these once at **Settings > Secrets and variables > Actions**. The workflow passes whichever are set to the build; anything left unset keeps the app's default.

| Name | Kind | What it does |
|---|---|---|
| `SERVER_URL` | Variable | The deployed backend, like `https://my-service-abc.a.run.app`. Must start with `https://` or the release fails. Unset, the app only looks for a server on the local network, which is no use to someone who downloads it. |
| `APP_KEY` | **Secret** | The key the server expects (its `APP_API_KEY`; `setup.sh` prints how to read it). The app sends it with every request. **It ends up inside the downloadable app, so anyone can extract it**: it keeps casual traffic out, and the server's rate limits are the real protection. |
| `PRIVACY_POLICY_URL`, `TERMS_OF_SERVICE_URL`, `SUPPORT_EMAIL` | Variables | The links in the app. Unset, they are placeholder `.example` addresses that don't open. The server serves `/privacy`, `/terms` and `/support`. |
| `TALK_MODE` | Variable | Set to `true` to include Talk mode (changing a song by typing or speaking). Unset leaves it out, which is right for a first launch: it runs on Gemini and ElevenLabs, which cost money per use. The release notes (`.github/release-notes-macos.md`) say Talk mode is not included, so edit that line if you turn it on. |

## What this build is, and is not

- **Not signed by Apple.** macOS shows a warning the first time; the release notes tell people how to allow it. Removing the warning needs an Apple Developer account (US$99/year) and a signing and notarizing step added to `release-macos.yml`.
- **The Rust audio engine is built into the app.** `frontend/rust_builder` compiles `native_ffi` for both kinds of Mac during `flutter build macos`, which is why the release job installs the two Rust targets and why the build takes several minutes. The workflow's check step requires the app to log `rust: bridge initialized`, so a build that loses the engine fails instead of shipping. **Not tested by a person:** that the engine hears a real instrument. That needs a person to allow the microphone and play.
- **Needs a server.** Hum mode, the library and the quiz talk to the Hu Accompany backend. With `SERVER_URL` set (see above) they use the deployed one. Without it, the app looks for a server on the local network, so a downloader sees "could not find the server". Deploying the backend is in `backend/deploy/README.md`.
- **Bundle ID is `app.accompanist`** (changed from Flutter's `com.example.huAccomponist` on 2026-10-27, before any public release). Don't change it again: macOS would treat the app as a different one and leave its saved data behind, and the App Store fixes it forever once the app is created there.

## Why Flutter is pinned

`flutter pub get` and `flutter build` on a different Flutter version re-resolve some packages and can raise the macOS minimum version by themselves. That happened here (10.15 to 12.0). Both workflows use 3.47.2 so the build matches what was tested. To upgrade, change the version in both workflow files together, then build locally and commit whatever Flutter changes.

## Checked, and not checked

Checked on a Mac, from a fresh `git clone` plus these changes: `flutter pub get`, `analyze`, all 232 tests, `flutter build macos --release`, the packaging script, and the workflow's own check step (including a failing case). **Not checked: the workflow on GitHub itself**, because it hasn't been pushed. Run it once with **Run workflow** before relying on it.
