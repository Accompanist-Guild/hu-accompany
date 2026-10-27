# App Store listing (draft)

What to paste into App Store Connect for the first release (no accounts, no Talk mode). Written in the website's voice; edit freely. The limits are Apple's, and `python3 docs/app-store/check_listing.py` checks the lengths.

## App Information

| Field | Value |
|---|---|
| Name (max 30) | Accompanist |
| Subtitle (max 30) | Sheet music that listens |
| Bundle ID | app.accompanist |
| Primary category | Music |
| Secondary category | Education |
| Content Rights | Contains third-party content (public-domain scores from PDMX, CC BY 4.0); you have the rights. Keep `backend/scores/clearance/clearance_report.json` as evidence. |
| Copyright | © 2026 *(your legal name, the same as `LEGAL_PUBLISHER`)* |
| Price | Free |

## Promotional text (max 170)

Play any piece and watch the score answer: every note marked as you go, green when it's right, a pencilled word when it isn't.

## Description (max 4000)

Play. It listens. Your sheet music answers.

Accompanist hears your instrument and marks every note on the score as you play it: green when it's right, a pencilled word when it isn't. It follows your tempo, so you never have to keep up with a metronome.

HOW IT READS YOU
• Right, on time: the note fills green.
• A little off: the right key, a touch early or late, in yellow.
• Early, late or missed: the note stays as written, with a small word under it saying what happened.
• Wrong key: it names the key you pressed and the one written.
• Repeats: the bars go back to black and fill in again, and your summary keeps every time through.
• What's next: the notes to play now keep jumping until you play them.

PLAY YOUR WAY
Pick from 1,369 public-domain pieces, from Bach to Debussy. Play with both hands, or one at a time. Tap once to pause and write on the music, twice to finish.

SEE WHAT TO FIX
When you finish, a summary lists every mistake by section, with each time through a repeat. Tap one to find it on the score.

HUM A SONG
Hum a tune and Accompanist turns it into a song with a band behind it.

PRIVATE BY DESIGN
Your playing is analysed on your device. Only the notes it hears are sent to make your feedback, never the recording. No account, no ads, no tracking.

## Keywords (max 100, comma separated, no spaces needed)

piano,practice,sheet music,score,music teacher,sight reading,classical,metronome,tempo,lesson,notes

## Age rating

Answer "None" to every content question. The first release has no user-to-user content, no web browsing, no AI chat (Talk mode is off) and no ads, so it should rate 4+. Answer again when Talk mode comes back.

## Screenshots

Needed: iPhone 6.9" (1320 × 2868 portrait, or 2868 × 1320 landscape). Also iPad 13" (2064 × 2752) if the app runs on iPad, which it does unless you limit it to iPhone. Suggested shots, in order:

1. A score mid-run, with green notes and a pencilled "late" and a "C, not D".
2. The summary after a run, mistakes by section.
3. The library, showing composers.
4. A paused score with handwriting on it.
5. The Hum screen with a finished song.

These need the iOS platform for Xcode 26.5 (`xcodebuild -downloadPlatform iOS`, about 8 GB) to run the simulator.
