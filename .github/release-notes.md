## Install on a Mac (macOS 12 or later, Apple silicon or Intel)

1. Download **Accompanist-macos.dmg** below, open it, and drag **Accompanist** onto **Applications**.
2. The first time you open it, macOS will refuse, because this build is not signed with an Apple Developer ID. To allow it:
   - Open **System Settings > Privacy & Security**, scroll to the message about *Accompanist*, and click **Open Anyway**; or
   - in Terminal, run `xattr -dr com.apple.quarantine /Applications/Accompanist.app` and open it again.
3. Allow the microphone when asked. Hum mode and practice need it.

Updating: drag the new version onto **Applications** and choose **Replace**. Your scores and settings stay.

## Install on Windows (Windows 10 or 11, 64-bit)

1. Download **Accompanist-windows-setup.exe** below and run it. It installs for your account only, so it doesn't ask for an administrator.
2. Windows may say it *protected your PC*, because this build is not signed with a code-signing certificate. Click **More info**, then **Run anyway**.
3. If Windows asks whether Accompanist may use the microphone, allow it. If practice hears nothing, check **Settings > Privacy & security > Microphone** and turn on **Let desktop apps access your microphone**.

Updating: run the new installer. It closes Accompanist if it is open and replaces it; your scores and settings stay.

## Updates

When a newer version is out, Accompanist says so at the top of the window when it starts, with a **Download** button.

To check your download wasn't damaged, compare it with **SHA256SUMS.txt**: `shasum -a 256 Accompanist-macos.dmg` on a Mac, `certutil -hashfile Accompanist-windows-setup.exe SHA256` on Windows.

## What works in this build

- Hum mode, the shelf, the library and the quiz.
- Practice feedback from a real instrument. It listens through the microphone.
- Hum mode, the library and the quiz need an internet connection: they use the Accompanist server.
- Talk mode (changing a song by typing or speaking to it) is not part of this version.

---
