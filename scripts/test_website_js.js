// Tests for the download-picking logic in website/app.js. Run: node scripts/test_website_js.js
const assert = require("assert");
const path = require("path");
const { pickDownload, isGithubUrl } = require(path.join(__dirname, "..", "website", "app.js"));

const release = {
  tag_name: "v0.1.0",
  html_url: "https://github.com/o/r/releases/tag/v0.1.0",
  assets: [
    { name: "HuAccomponist-0.1.0-macos.dmg.sha256", browser_download_url: "https://github.com/o/r/x.sha256", size: 90 },
    { name: "HuAccomponist-0.1.0-macos.dmg", browser_download_url: "https://github.com/o/r/x.dmg", size: 52428800 },
  ],
};

const tests = {
  "finds the .dmg, its version, size and checksum even when the checksum is listed first"() {
    const d = pickDownload(release);
    assert.equal(d.version, "0.1.0");
    assert.equal(d.name, "HuAccomponist-0.1.0-macos.dmg");
    assert.equal(d.sizeMB, 50);
    assert.equal(d.url, "https://github.com/o/r/x.dmg");
    assert.equal(d.checksumUrl, "https://github.com/o/r/x.sha256");
  },
  "has no checksum link when the checksum asset is missing"() {
    const d = pickDownload({ ...release, assets: [release.assets[1]] });
    assert.equal(d.checksumUrl, null);
  },
  "returns null for a release with no assets, no .dmg, or only a checksum"() {
    assert.equal(pickDownload({ tag_name: "v1", assets: [] }), null);
    assert.equal(pickDownload({ tag_name: "v1", assets: [{ name: "notes.txt" }] }), null);
    assert.equal(pickDownload({ assets: [{ name: "a.dmg.sha256" }] }), null);
  },
  "does not crash on missing or malformed input"() {
    assert.equal(pickDownload(null), null);
    assert.equal(pickDownload(undefined), null);
    assert.equal(pickDownload({}), null);
    assert.equal(pickDownload({ assets: "nope" }), null);
  },
  "accepts only https links on github.com and its content hosts"() {
    assert.ok(isGithubUrl("https://github.com/o/r/releases/download/v1/a.dmg"));
    assert.ok(isGithubUrl("https://objects.githubusercontent.com/x"));
  },
  "rejects look-alike hosts, other schemes and junk"() {
    for (const bad of ["http://github.com/x", "https://evilgithub.com/x", "https://github.com.evil.io/x",
      "https://notgithubusercontent.com/x", "javascript:alert(1)", "data:text/html,x", "//github.com/x", "", "not a url", null, undefined]) {
      assert.ok(!isGithubUrl(bad), `should reject ${bad}`);
    }
  },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
  try { fn(); console.log("ok   " + name); } catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message); }
}
console.log(`${Object.keys(tests).length - failed}/${Object.keys(tests).length} passed`);
process.exit(failed ? 1 : 0);
