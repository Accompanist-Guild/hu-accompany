# The website

A small static site for people to discover, download and learn the Mac app. No build step, no framework, nothing loaded from other sites.

```
website/
  index.html         the home page: what the app is, the Download button, install steps
  docs/              the guides (user-facing, one HTML file each) and their hub, docs/index.html
  site.css           all styles, shared by every page (the app's own palette: dark turntable room, paper pages)
  app.js             the Download button and the legal links (the only script)
  config.js          the repository and server address; rewritten when the site is published
```

## How the Download button works

`app.js` asks GitHub for the newest release (`/repos/<repo>/releases/latest`) when the page opens and points the button at its `.dmg`, with the `.sha256` checksum beside it. Before any release exists, or when GitHub can't be reached, the page says so and the button stays disabled with a link to the releases page. Pre-releases (a tag like `v0.1.0-beta.1`) are skipped by GitHub's "latest", so they will not appear here. Only `github.com` links are ever put into the page, and values from GitHub are written as text, never as HTML.

## Publishing

`.github/workflows/pages.yml` publishes the site to GitHub Pages whenever anything under `website/` changes on `main`, or from **Actions > Publish website > Run workflow**.

One-time setup: **Settings > Pages > Build and deployment > Source: GitHub Actions**. The address is `https://<owner>.github.io/<repo>/`.

The workflow:

1. Runs `python3 scripts/check_website.py website`, which fails the publish on unbalanced HTML, a page without exactly one `<h1>`, a repeated `id`, or a link or `#anchor` that points nowhere.
2. Rewrites `config.js` in its own copy (not in the repository) with this repository's name and the `SERVER_URL` repository variable. The Privacy Policy, Terms of Service and Support links in the footer of every page appear only when `SERVER_URL` is set, because the server hosts those pages.

## Previewing

```bash
cd website
python3 -m http.server 8000      # then open http://localhost:8000
python3 ../scripts/check_website.py .
```

With `config.js` as committed, the download button says the first release is not published yet until the repository has one, and the legal links are hidden.

## Editing the guides

The guides are plain HTML. Each page repeats the same header and footer, so to change those, search and replace across `docs/*.html`. To add a guide:

1. Copy an existing page in `docs/` and change the title, `<meta name="description">`, `<h1>`, intro and body.
2. Add it to the hub, `docs/index.html`, and to the previous and next links of its neighbours.
3. Run `scripts/check_website.py`.

Keep the content true to the app. When these change, update the guide that describes them:

| If this changes | Update |
|---|---|
| Names of pages, buttons or messages in the app (`frontend/lib/features/`) | the guides quote them, for example "Hold to hum", "Stop sharing", "Contact support or send feedback" |
| Hum limits (`maxHum` in `hum_controller.dart`, `intake/checks.py`) or the song makers | `docs/hum.html` |
| Practice tempos, exercises or feedback wording | `docs/practice.html` |
| What Talk mode sends, who receives it, or the consent box (`talk_consent.dart`) | `docs/talk-mode.html`, the FAQ, and the Privacy Policy (`backend/legal/`) |
| How long hum recordings are kept (`HUM_TTL_HOURS`) | the "about three hours" sentences in `docs/hum.html`, `docs/troubleshooting.html` and `docs/faq.html` |
| The library's screening rule (`backend/scores/clearance.py`) | `docs/library.html` and `docs/faq.html` |
| Supported macOS version or install steps (`docs/releasing-macos.md`, `.github/release-notes-macos.md`) | `docs/getting-started.html`, `docs/troubleshooting.html`, the install steps on `index.html` |

Platform note: the guides describe the Mac app. If an iPhone version is released, add its install steps rather than replacing these.

## Style

The look is the app's: the dark "turntable room" (`#1b1b1f`) opening onto warm paper (`#f7f2e7`), gold accents, and the shelf's four card gradients, taken from `frontend/lib/shared/theme/`. The font is the system font, as in the app. Colours and sizes are variables at the top of `site.css`; dark mode follows the visitor's system setting.
