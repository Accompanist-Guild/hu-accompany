#!/bin/bash
# Packs the built macOS app into a .dmg (the app next to an Applications shortcut, so installing is a drag),
# and writes a .sha256 file beside it so people can check their download.
#
#   scripts/package_macos_dmg.sh <path/to/App.app> <output.dmg>
#
# Used by .github/workflows/release-macos.yml; run it by hand to test a release locally.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <App.app> <output.dmg>" >&2
  exit 2
fi

app="$1"
dmg="$2"

[ -d "$app" ] || { echo "error: $app is not a built .app folder" >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# `ditto`, not `cp -R`: it keeps the app's symlinks and code signature intact, and a copy that loses either
# produces an app macOS reports as damaged.
ditto "$app" "$staging/$(basename "$app")"
ln -s /Applications "$staging/Applications"

rm -f "$dmg"
hdiutil create -quiet -volname "Accompanist" -srcfolder "$staging" -format UDZO -ov "$dmg"

# Run from the dmg's own folder so the checksum file holds a bare file name and `shasum -c` works wherever
# the two files are downloaded to.
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")

echo "wrote $dmg"
