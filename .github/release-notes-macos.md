## Install (macOS 12 or later, Apple silicon or Intel)

1. Download the `.dmg` below, open it, and drag **hu_accomponist** onto **Applications**.
2. The first time you open it, macOS will refuse, because this build is not signed with an Apple Developer ID. To allow it:
   - Open **System Settings > Privacy & Security**, scroll to the message about *hu_accomponist*, and click **Open Anyway**; or
   - in Terminal, run `xattr -dr com.apple.quarantine /Applications/hu_accomponist.app` and open it again.
3. Allow the microphone when asked. Hum mode and practice need it.

To check your download wasn't damaged, put the `.sha256` file beside the `.dmg` and run `shasum -a 256 -c <name>.dmg.sha256`.

## What works in this build

- Hum mode, the shelf, the library and the quiz.
- Practice feedback from a real instrument. It listens through the microphone, so allow the microphone when macOS asks.
- Hum mode, the library and the quiz need an internet connection: they use the Hu Accompany server.
- Talk mode (changing a song by typing or speaking to it) is not part of this version.

---
