// Finds the newest release on GitHub and points the download button at its .dmg. Everything is written with
// textContent and href, never as HTML, so nothing from GitHub can run as script on this page.

// The .dmg and .sha256 files of a release, or null if it has no .dmg. Pure, so it can be tested without a browser.
function pickDownload(release) {
  const assets = Array.isArray(release && release.assets) ? release.assets : [];
  const dmg = assets.find((a) => /\.dmg$/.test(a.name));
  if (!dmg) return null;
  const sum = assets.find((a) => a.name === dmg.name + ".sha256");
  return {
    version: String(release.tag_name || "").replace(/^v/, ""),
    name: dmg.name,
    url: dmg.browser_download_url,
    sizeMB: Math.round((dmg.size / 1048576) * 10) / 10,
    checksumUrl: sum ? sum.browser_download_url : null,
    page: release.html_url,
  };
}

// Only https links to github.com are ever put into the page.
function isGithubUrl(u) {
  try {
    const p = new URL(u);
    return p.protocol === "https:" && (p.hostname === "github.com" || p.hostname.endsWith(".githubusercontent.com"));
  } catch (e) {
    return false;
  }
}

async function showDownload() {
  const site = window.SITE || {};
  const button = document.getElementById("download");
  if (!button) return; // only the home page has a download button
  const status = document.getElementById("download-status");
  const all = document.getElementById("all-releases");
  all.href = "https://github.com/" + site.repo + "/releases";
  try {
    const res = await fetch("https://api.github.com/repos/" + site.repo + "/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (res.status === 404) {
      status.textContent = "The first release is not published yet. Check back soon.";
      return;
    }
    if (!res.ok) throw new Error("GitHub answered " + res.status);
    const d = pickDownload(await res.json());
    if (!d || !isGithubUrl(d.url)) {
      status.textContent = "The newest release has no Mac download yet.";
      return;
    }
    button.href = d.url;
    button.removeAttribute("aria-disabled");
    button.textContent = "Download for Mac (" + d.version + ")";
    status.textContent = d.name + ", " + d.sizeMB + " MB";
    if (d.checksumUrl && isGithubUrl(d.checksumUrl)) {
      const sum = document.getElementById("checksum");
      sum.href = d.checksumUrl;
      sum.hidden = false;
    }
  } catch (e) {
    status.textContent = "Could not check for the latest version. Use the releases page below.";
  }
}

function showLegalLinks() {
  const base = ((window.SITE || {}).serverUrl || "").replace(/\/+$/, "");
  if (!/^https:\/\/[^/\s]+/.test(base)) return;
  for (const page of ["privacy", "terms", "support"]) {
    const a = document.getElementById("link-" + page);
    if (!a) continue;
    a.href = base + "/" + page;
    a.hidden = false;
  }
}

if (typeof document !== "undefined") {
  showDownload();
  showLegalLinks();
}
if (typeof module !== "undefined") module.exports = { pickDownload, isGithubUrl };
