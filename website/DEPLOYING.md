# Deploying the website

The site is published to GitHub Pages by `.github/workflows/pages.yml`. There is no server to run.

## One-time setup

1. In the repository, open **Settings > Pages > Build and deployment** and set **Source** to **GitHub Actions**. (From a terminal, `gh api -X POST repos/<owner>/<repo>/pages -f build_type=workflow` should do the same; that call is from memory, so use the Settings page if it errors.)
2. Optional but recommended, once the backend is deployed: set the repository variable **`SERVER_URL`** (Settings > Secrets and variables > Actions > Variables), for example `https://hu-accompany-abc123-uc.a.run.app`. It must start with `https://`, with no path and no trailing slash. With it set, every page's footer shows the Privacy Policy, Terms of Service and Support links. The Mac release build reads the same variable.
3. Push to `main`, or run **Actions > Publish website > Run workflow**.

The address will be `https://<owner>.github.io/<repo>/`. Publishing takes about a minute.

## What the workflow does

It runs on every push to `main` that changes `website/`, `scripts/check_website.py`, `scripts/test_website_js.js` or the workflow itself, and by hand. In order:

1. **Fill in the site settings.** Writes `website/config.js` in the runner's checkout (never committed) with the repository name and `SERVER_URL`. It fails the run if `SERVER_URL` is set but is not a plain `https://host` address, and warns if it is unset.
2. **Check the pages.** `python3 scripts/check_website.py website`: unbalanced HTML, a page without exactly one `<h1>`, a repeated `id`, or a broken link or `#anchor` stops the publish.
3. **Test the download script.** `node scripts/test_website_js.js`.
4. **Assemble the site.** Copies `website/` to `_site/` without the `*.md` files, so these developer docs are not published.
5. **Publish** the `_site` folder with the official Pages actions.

The `github-pages` environment normally allows deploys only from `main`. If you add branch protection rules to that environment, the workflow must still be allowed to deploy from `main`.

## Verifying a publish

- Open the address from the run's summary.
- With no release yet, the button says "The first release is not published yet." That is correct.
- After a release exists (see `docs/releasing-macos.md`), reload: the button should read `Download for Mac (<version>)` and the file name and size should appear. Click it and confirm the `.dmg` downloads.
- If `SERVER_URL` is set, the footer should show the three legal links, and each should open a page.

## Custom domain

1. Settings > Pages > **Custom domain**, enter it, save.
2. At your DNS provider, add a `CNAME` record from the name you chose (for example `www`) to `<owner>.github.io`. For a bare domain, GitHub documents the `A`/`AAAA` records to use.
3. Tick **Enforce HTTPS** once GitHub has issued the certificate.

All links on the site are relative, so nothing in the pages needs to change when the address changes.

## Rolling back

Revert the offending commit on `main`; the workflow publishes the previous content. Or open an earlier successful run of **Publish website** and use **Re-run all jobs**. Neither affects releases or the Mac app.

## When a publish fails

| Where it fails | Likely cause | Fix |
|---|---|---|
| Fill in the site settings | `SERVER_URL` is not `https://host` (a path, a trailing slash, or `http://`) | Fix the repository variable |
| Check the pages | A link, anchor, `<h1>` or tag problem in a page | Run `python3 scripts/check_website.py website` locally; the message names the file |
| Test the download script | `app.js` logic changed | Run `node scripts/test_website_js.js` |
| `configure-pages` ("Get Pages site failed") | Pages is not enabled for the repository | Do step 1 of the one-time setup |
| Deploy ("not allowed to deploy") | Environment protection rules | Allow `main` in the `github-pages` environment |
| The site loads but looks stale | Browser cache | Hard refresh; `site.css` is cached by the browser |

If the repository is private, GitHub Pages availability depends on your plan. This project is public.
