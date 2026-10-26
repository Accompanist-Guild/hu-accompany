"""Writes licenses.html: what the site is built from, and under which licences.

The engine's Rust crates come from `cargo metadata` (run by build.sh), so the list follows the build.
"""
import html
import json
import sys

crates = json.load(sys.stdin)
ids = {n["id"] for n in crates["resolve"]["nodes"]}
rows = sorted(
    (p["name"], p["version"], p.get("license") or "see crate")
    for p in crates["packages"]
    if p["id"] in ids and p["name"] not in ("web_engine", "native_ffi")
)
crate_rows = "\n".join(
    f"<tr><td>{html.escape(n)}</td><td>{html.escape(v)}</td><td>{html.escape(l)}</td></tr>" for n, v, l in rows
)
osmd_licence = html.escape(open("viewer/LICENSE.txt").read())

page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Credits and licences · Accompanist</title>
  <link rel="icon" href="favicon.svg" type="image/svg+xml">
  <link rel="stylesheet" href="css/site.css">
  <style>
    .doc {{ max-width: 820px; margin: 0 auto; padding: 48px var(--gutter) 64px; }}
    .doc h1 {{ font-size: 40px; margin-bottom: 8px; }}
    .doc h2 {{ font-size: 24px; margin: 36px 0 8px; }}
    .doc p, .doc li {{ color: var(--muted); }}
    .doc table {{ width: 100%; border-collapse: collapse; font-size: 14px; margin-top: 8px; }}
    .doc td {{ padding: 5px 8px 5px 0; border-bottom: 1px solid color-mix(in srgb, var(--rule) 50%, transparent); }}
    .doc pre {{ white-space: pre-wrap; font-size: 13px; background: var(--paper); border: 1px solid var(--rule); padding: 14px; }}
  </style>
</head>
<body>
  <header class="top"><a class="wordmark" href="./">Accompanist</a></header>
  <main class="doc">
    <h1>Credits and licences</h1>
    <p>Accompanist stands on other people’s generous work. Thank you.</p>

    <h2>The music</h2>
    <p><b>Für Elise</b> (Bagatelle No. 25 in A minor, WoO 59) by Ludwig van Beethoven (1770–1827), in a
      transcription shared on MuseScore and collected in the PDMX dataset, marked public domain by its uploader.
      The app’s library holds only pieces whose uploader marked them public domain or CC0, by composers who died
      in or before 1925.</p>

    <h2>The listening engine</h2>
    <p>Pitch detection uses the <b>Basic Pitch</b> model by Spotify (Apache License 2.0), run by
      <b>tract</b> by Sonos (MIT or Apache License 2.0). The engine is built from these Rust crates:</p>
    <table>{crate_rows}</table>

    <h2>The sheet music</h2>
    <p>Scores are drawn by <b>OpenSheetMusicDisplay</b> 2.2.0:</p>
    <pre>{osmd_licence}</pre>

    <h2>Fonts</h2>
    <p>Fraunces, IBM Plex Sans and Nanum Pen Script, from Google Fonts, under the SIL Open Font License 1.1.</p>
  </main>
</body>
</html>
"""
open("licenses.html", "w").write(page)
print(f"licenses.html: {len(rows)} crates")
