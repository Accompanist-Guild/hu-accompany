#!/usr/bin/env bash
# Builds the site and uploads it to Cloudflare Pages (project "accompanist", served at accompanist.app).
# Needs wrangler, logged in (wrangler login). Pass --engine to rebuild the WebAssembly engine first.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh "$@"
node --test js/judge.test.mjs

# Only what visitors need: no build tools or tests.
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
cp -R index.html licenses.html favicon.svg _headers css scores viewer engine "$out/"
mkdir "$out/js"
cp js/demo.js js/judge.js js/engine-worker.js js/capture-worklet.js "$out/js/"

wrangler pages deploy "$out" --project-name accompanist --branch main --commit-dirty=true
