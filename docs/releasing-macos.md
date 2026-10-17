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

## Setting the privacy and support addresses

The app links to a Privacy Policy, Terms and a support address. Until you set real ones, it keeps its placeholder `.example` addresses, which don't open. Set them once at **Settings > Secrets and variables > Actions > Variables**: `PRIVACY_POLICY_URL`, `TERMS_OF_SERVICE_URL`, `SUPPORT_EMAIL`. The workflow passes whichever are set.

## What this build is, and is not

- **Not signed by Apple.** macOS shows a warning the first time; the release notes tell people how to allow it. Removing the warning needs an Apple Developer account (US$99/year) and a signing and notarizing step added to `release-macos.yml`.
- **The Rust audio engine is built into the app.** `frontend/rust_builder` compiles `native_ffi` for both kinds of Mac during `flutter build macos`, which is why the release job installs the two Rust targets and why the build takes several minutes. The workflow's check step requires the app to log `rust: bridge initialized`, so a build that loses the engine fails instead of shipping. **Not tested by a person:** that the engine hears a real instrument. That needs a person to allow the microphone and play.
- **Needs a server.** Hum mode and the library talk to the Hu Accompany backend, which finds it over the local network. Until the backend is deployed at a fixed address, downloaders without it running see "could not find the server".
- **Bundle ID is still `com.example.huAccomponist`.** Changing it later makes macOS treat the app as a different one, and its saved data stays behind.

## Why Flutter is pinned

`flutter pub get` and `flutter build` on a different Flutter version re-resolve some packages and can raise the macOS minimum version by themselves. That happened here (10.15 to 12.0). Both workflows use 3.47.2 so the build matches what was tested. To upgrade, change the version in both workflow files together, then build locally and commit whatever Flutter changes.

## Checked, and not checked

Checked on a Mac, from a fresh `git clone` plus these changes: `flutter pub get`, `analyze`, all 232 tests, `flutter build macos --release`, the packaging script, and the workflow's own check step (including a failing case). **Not checked: the workflow on GitHub itself**, because it hasn't been pushed. Run it once with **Run workflow** before relying on it.
