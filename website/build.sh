#!/usr/bin/env bash
# Assembles the website in website/ from the app's own parts, so nothing is copied by hand:
#   viewer/  the app's score page (frontend/assets/osmd), talking to this page instead of Flutter
#   engine/  the app's note detector built for the browser (web_engine/build.sh); slow, so only
#            rebuilt when missing or with --engine
# Then deploy.sh puts it online.
set -euo pipefail
cd "$(dirname "$0")"
OSMD=../frontend/assets/osmd

mkdir -p viewer
cp "$OSMD/opensheetmusicdisplay.min.js" "$OSMD/score_timeline.js" "$OSMD/LICENSE.txt" viewer/
# The page posts every message to window.FlutterBridge; here that is the parent page.
python3 - "$OSMD/osmd_viewer.html" viewer/index.html <<'PY'
import sys
page = open(sys.argv[1]).read()
anchor = '<script src="opensheetmusicdisplay.min.js"></script>'
assert anchor in page, "osmd_viewer.html changed: update website/build.sh"
shim = ('<script>window.FlutterBridge = { postMessage: function (m) {'
        ' parent.postMessage({ accompanist: JSON.parse(m) }, location.origin); } };</script>\n  ')
open(sys.argv[2], 'w').write(page.replace(anchor, shim + anchor, 1))
PY

if [ ! -f engine/engine_bg.wasm ] || [ "${1:-}" = --engine ]; then
  ../web_engine/build.sh
fi
# Credits: the engine's crates, read from the build.
(cd ../web_engine && cargo metadata --format-version 1 --filter-platform wasm32-unknown-unknown) | python3 tools/licenses.py

echo "website assembled in $(pwd)"
