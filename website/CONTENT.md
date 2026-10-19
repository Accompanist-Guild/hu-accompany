# Writing and maintaining the content

## House rules

- **Plain language, short sentences.** The readers are people who want to play music, not developers.
- **British spelling** (practise, favourites), to match the pages that exist. Match the app's own labels exactly when quoting them.
- **Say what is true, not what is hoped.** If something has not been tested on a real Mac, or depends on a setting, say so or leave it out. The guides link to the Privacy Policy rather than restating legal terms.
- **No new colours, fonts or images** without reading [DESIGN.md](DESIGN.md). Nothing may be loaded from another site: the Content Security Policy blocks it.

## Editing an existing page

The pages are plain HTML. Edit the text between `<article>` and `</article>` (guides) or inside `<main>` (home page). Then:

```bash
python3 scripts/check_website.py website
```

If you change the header or footer, they are repeated in every file under `docs/`, so search and replace across `docs/*.html` and check `index.html`.

## Adding a guide

1. Copy an existing page in `docs/` that is close to what you need.
2. Change the `<title>`, `<meta name="description">`, the breadcrumb, `<h1>`, the `.intro` paragraph and the body.
3. Add a card for it in `docs/index.html` (a `.guide` link in the `.guides` list).
4. Add it to the previous and next links (`.pager`) of the guides on either side of it.
5. If a section should be linkable, give its `<h2>` an `id` and link to `page.html#id`.
6. Run the checker.

Building blocks already in `site.css`: `.callout` (a highlighted note), `table.pages` (a two-column list), `.guides` and `.guide` (the card grid), `details.qa` (a collapsible question), `.pager` (previous and next), `.cta` (a download button), `code` and `.note`.

## What to update when the app changes

The guides describe real screens and messages, and some numbers repeat. When one of these changes, update the page named:

| If this changes | Update |
|---|---|
| A page, button or message in the app (`frontend/lib/features/`) | Every guide that quotes it, for example "Hold to hum", "Stop sharing", "Contact support or send feedback", "Open Anyway" |
| The hum recording limit (`maxHum` in `hum_controller.dart`), the minimum length (`intake/checks.py`), or the song makers | `docs/hum.html` |
| Practice exercises, tempos, hands, or feedback wording | `docs/practice.html` |
| What Talk mode sends, who receives it, or the consent box (`talk_consent.dart`) | `docs/talk-mode.html`, the FAQ, and the Privacy Policy templates in `backend/legal/` |
| How long hum recordings are kept (`HUM_TTL_HOURS`) | The "about three hours" sentences in `docs/hum.html`, `docs/troubleshooting.html` and `docs/faq.html` |
| The library's screening rule (`backend/scores/clearance.py`) or its size | `docs/library.html` and `docs/faq.html` ("more than a thousand scores") |
| The supported macOS version, or the install steps | `index.html` (install steps), `docs/getting-started.html`, `docs/troubleshooting.html`, `.github/release-notes-macos.md`, `docs/releasing-macos.md` |
| Which instruments were tested | `docs/faq.html` ("Which instruments does it work with?") |
| A new platform (for example iPhone) | Add its install steps; do not replace the Mac ones |

The install steps appear in three places that must agree: `index.html`, `docs/getting-started.html`, and `.github/release-notes-macos.md` (which becomes the text of every GitHub release).

## Before you merge

- Run `python3 scripts/check_website.py website` and `node scripts/test_website_js.js`.
- Preview at phone and desktop widths, in light and dark mode (see [DESIGN.md](DESIGN.md) for forcing dark mode).
- Read every changed sentence against the app. The checker cannot tell you a guide is wrong.

## History

The guides in `docs/` were first produced by a one-off script and are now maintained by hand; there is no generator to re-run.
