#!/usr/bin/env bash
# Builds the site and uploads it to Cloudflare (Workers static assets, wrangler.jsonc), served at accompanist.app.
# Needs wrangler, logged in (wrangler login). Pass --engine to rebuild the WebAssembly engine first.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh "$@"
node --test js/judge.test.mjs

# Only what visitors need, staged in dist/: no build tools or tests.
rm -rf dist && mkdir -p dist/js
cp -R index.html licenses.html favicon.svg _headers css scores viewer engine dist/
cp js/demo.js js/judge.js js/engine-worker.js js/capture-worklet.js dist/js/

# Cloudflare Workers serves dist/ (see wrangler.jsonc), at accompanist.app.
wrangler deploy
