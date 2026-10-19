# Architecture

## Goals and the shape that follows

People should find the app, download the right file, and get it running. Nothing else on the site needs a server, a database or a build, so it is static files served by GitHub Pages. That keeps it free, fast, and unable to leak anything: the site has no accounts, no cookies, no analytics, and makes one request to a third party (GitHub, for the latest release).

## The pieces

| Piece | Job |
|---|---|
| `index.html` | The home page. The Download button is a link that starts disabled. |
| `docs/*.html` | Guides. Static text only. They load `app.js`, which does nothing on them except reveal the legal links. |
| `site.css` | All styling. One file, so every page looks the same and the browser caches it. |
| `config.js` | Sets `window.SITE = { repo, serverUrl }`. The only per-deployment values. |
| `app.js` | Looks up the newest release and fills in the Download button; reveals the Privacy, Terms and Support links. |

## How the Download button works

1. The page loads with the button disabled (`aria-disabled="true"`) and pointing at the repository's releases page, so it is never a dead end.
2. `app.js` fetches `https://api.github.com/repos/<repo>/releases/latest`.
3. The result decides what the visitor sees:

| GitHub answers | The page shows |
|---|---|
| A release with a `.dmg` asset | The button is enabled and points at the `.dmg`, labelled `Download for Mac (<version>)`, with the file name and size. A "Checksum" link appears if a `<name>.dmg.sha256` asset sits beside it. |
| 404 | "The first release is not published yet." (no releases exist) |
| A release with no `.dmg` | "The newest release has no Mac download yet." |
| Anything else (rate limit, network error, GitHub down) | "Could not check for the latest version. Use the releases page below." The "All versions" link still works. |

Details worth knowing:

- **"Latest" skips pre-releases and drafts.** A tag like `v0.1.0-beta.1` published as a pre-release will not appear on the page. The release workflow does not yet mark such tags as pre-releases, so today a beta tag would show up. See `docs/releasing-macos.md`.
- **Rate limit.** Unauthenticated GitHub API calls are limited per IP address (60 an hour, from GitHub's documentation). A visitor who hits it sees the fallback message and the working releases link.
- **Coupling to the release workflow.** The page finds the download by the `.dmg` file extension and its checksum by the name `<dmg name>.sha256`. Both come from `scripts/package_macos_dmg.sh` and `.github/workflows/release-macos.yml`. If you change how release files are named, check `pickDownload` in `app.js`.
- **No version is hard-coded** anywhere on the site, so publishing a release updates the page by itself.

## Legal links

The Privacy Policy, Terms of Service and Support pages are served by the backend (`backend/server/legal.py`), not by this site. Every page's footer has three hidden links (`#link-privacy`, `#link-terms`, `#link-support`). `app.js` points them at `<serverUrl>/privacy`, `/terms` and `/support` and shows them, but only when `serverUrl` is an `https://` address. With no server address they stay hidden rather than linking nowhere.

## Configuration

`config.js` is committed with the repository name and an empty `serverUrl`, which is a working preview state. When the site is published, the workflow rewrites it in its own copy using the repository's name and the `SERVER_URL` repository variable (the same variable the Mac release build uses). The committed file is never modified by a publish. See [DEPLOYING.md](DEPLOYING.md).

## Security choices

- **Content Security Policy** in a `<meta>` tag on every page. The home page: `default-src 'none'; script-src 'self'; style-src 'self'; connect-src https://api.github.com; base-uri 'none'; form-action 'none'`. The guides are the same without `connect-src`, because they make no requests. There are no inline scripts or styles and no images or fonts from elsewhere, so the policy can stay this strict. A `<meta>` policy cannot set `frame-ancestors`, and GitHub Pages does not let you set response headers, so framing the site cannot be blocked from here.
- **Values from GitHub are never treated as HTML.** They are written with `textContent` and `href`. A link is used only if it is `https` and on `github.com` or `*.githubusercontent.com` (`isGithubUrl`), which rejects look-alike hosts such as `github.com.evil.io` and `javascript:` links.
- **The server address is validated** before being used in a link (`^https://[^/\s]+`), and the publish workflow refuses to publish an invalid `SERVER_URL`.
- **No third parties besides GitHub**: no fonts, analytics, trackers or CDNs.

## What is tested

- `scripts/test_website_js.js` tests `pickDownload` and `isGithubUrl`, including a release with no `.dmg`, a checksum with no `.dmg`, and hostile look-alike URLs. `app.js` exports both for Node; in a browser the export is skipped.
- `scripts/check_website.py` checks HTML structure, one `<h1>` per page, unique `id`s, and that every relative link and `#anchor` resolves.
- Not automated: how the pages look, and the live GitHub lookup. Check those by previewing, in light and dark mode, at phone and desktop widths.

## Why no build step or framework

There are about ten pages and one script. A build step would add tooling to maintain, and the cost is some repetition: each guide repeats the header and footer, so changing those means a search and replace across `docs/*.html` (see [CONTENT.md](CONTENT.md)). If the guides grow past a couple of dozen pages, move to a static site generator rather than adding scripting here.
