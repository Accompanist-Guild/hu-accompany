#!/usr/bin/env bash
# Builds the engine for the browser into website/engine/ (engine.js + engine_bg.wasm).
# Needs: rustup target add wasm32-unknown-unknown; cargo install wasm-bindgen-cli --version 0.2.129
set -euo pipefail
cd "$(dirname "$0")"
# SIMD: the pitch network runs about 2.3x faster with it (every current browser has it).
RUSTFLAGS='--cfg getrandom_backend="wasm_js" -C target-feature=+simd128' \
  cargo build --release --target wasm32-unknown-unknown
wasm-bindgen --target web --no-typescript --out-dir ../website/engine --out-name engine \
  target/wasm32-unknown-unknown/release/web_engine.wasm
ls -lh ../website/engine
