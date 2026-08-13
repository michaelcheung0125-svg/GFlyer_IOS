#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/GFlyerIOS/Vendor/idevice"
SOURCE_DIR="${1:-$PROJECT_DIR/.build/idevice}"
IDEVICE_REVISION="37ee77cf713f483551f3cf33ea8b2087a40058ca"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo is required. Install Rust with rustup first." >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  mkdir -p "$(dirname "$SOURCE_DIR")"
  git clone https://github.com/jkcoxson/idevice.git "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --depth 1 origin "$IDEVICE_REVISION"
git -C "$SOURCE_DIR" checkout --detach "$IDEVICE_REVISION"

rustup target add aarch64-apple-ios

pushd "$SOURCE_DIR" >/dev/null
build_environment=()
if command -v xcrun >/dev/null 2>&1; then
  build_environment+=(
    "BINDGEN_EXTRA_CLANG_ARGS=--sysroot=$(xcrun --sdk iphoneos --show-sdk-path)"
    "IPHONEOS_DEPLOYMENT_TARGET=17.4"
  )
fi

env "${build_environment[@]}" cargo build \
  --release \
  --package idevice-ffi \
  --target aarch64-apple-ios \
  --no-default-features \
  --features "ring dvt location_simulation mobile_image_mounter tss tunnel_tcp_stack"
popd >/dev/null

mkdir -p "$VENDOR_DIR/include" "$VENDOR_DIR/lib"
cp "$SOURCE_DIR/ffi/idevice.h" "$VENDOR_DIR/include/idevice.h"
cp "$SOURCE_DIR/target/aarch64-apple-ios/release/libidevice_ffi.a" "$VENDOR_DIR/lib/libidevice_ffi.a"
printf '%s\n' \
  'module idevice [system] {' \
  '  header "idevice.h"' \
  '  export *' \
  '}' > "$VENDOR_DIR/include/module.modulemap"

echo "idevice artifacts installed under $VENDOR_DIR"
