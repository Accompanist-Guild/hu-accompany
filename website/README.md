# Website

The public website for Hu Accomponist: a home page where people discover the app and download it, plus a set of user guides. It is plain HTML, CSS and one small script, with no build step and nothing loaded from other sites.

**Read next**

| File | What it covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the site works: the Download button, config, security choices, failure modes |
| [DEPLOYING.md](DEPLOYING.md) | Publishing to GitHub Pages: one-time setup, variables, custom domain, rollback, fixing a failed publish |
| [CONTENT.md](CONTENT.md) | Editing and adding pages, and what to update when the app changes |
| [DESIGN.md](DESIGN.md) | Colours, type, components, dark mode, accessibility numbers |

## Layout

```
website/
  index.html     home page: what the app is, the Download button, install steps, links to the guides
  docs/          user guides, one HTML file each, and their hub (docs/index.html)
  site.css       every style, shared by all pages
  app.js         the only script: the Download button and the legal links
  config.js      repository and server address (rewritten when the site is published)
  *.md           these developer docs (not published; see DEPLOYING.md)
scripts/check_website.py       link and HTML checker, run before every publish
scripts/test_website_js.js     tests for the download-picking logic in app.js
.github/workflows/pages.yml    publishes the site to GitHub Pages
```

## Quick start

```bash
cd website
python3 -m http.server 8000                     # preview at http://localhost:8000
python3 ../scripts/check_website.py .           # links, anchors, one <h1> per page, balanced HTML
node ../scripts/test_website_js.js              # the Download button's logic
```

Until the repository has a published release, the Download button says so and stays disabled. That is the correct preview state.
