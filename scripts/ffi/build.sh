#!/usr/bin/env bash
# Build offsend-ffi static library and stage it for the macOS app and/or server.
#
# On Darwin, the macOS app archive links OffsendRustBridge for both arm64 and
# x86_64, so STAGE_MACOS stages a universal (lipo) liboffsend_ffi.a.
set -euo pipefail

# shellcheck source=../lib/repo-paths.sh
source "$(cd "$(dirname "$0")" && pwd)/../lib/repo-paths.sh"

STAGE_MACOS="${STAGE_MACOS:-1}"
STAGE_SERVER="${STAGE_SERVER:-1}"

cd "$REPO_ROOT"
if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found (PATH=$PATH)." >&2
  echo "Install Rust from https://rustup.rs and ensure ~/.cargo/bin is on PATH," >&2
  echo "or run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
  exit 1
fi

HEADER_SRC="${REPO_ROOT}/crates/offsend-ffi/include/offsend_ffi.h"
test -f "$HEADER_SRC"

ensure_rust_target() {
  local triple="$1"
  if ! command -v rustup >/dev/null 2>&1; then
    return 0
  fi
  if ! rustup target list --installed 2>/dev/null | grep -qx "$triple"; then
    rustup target add "$triple"
  fi
}

if [[ "$(uname -s)" == "Darwin" && "$STAGE_MACOS" == "1" ]]; then
  ensure_rust_target aarch64-apple-darwin
  ensure_rust_target x86_64-apple-darwin
  cargo build -p offsend-ffi --release --target aarch64-apple-darwin
  cargo build -p offsend-ffi --release --target x86_64-apple-darwin

  LIB_ARM64="${REPO_ROOT}/target/aarch64-apple-darwin/release/liboffsend_ffi.a"
  LIB_X64="${REPO_ROOT}/target/x86_64-apple-darwin/release/liboffsend_ffi.a"
  test -f "$LIB_ARM64"
  test -f "$LIB_X64"

  UNIVERSAL_DIR="${REPO_ROOT}/target/universal-apple-darwin/release"
  mkdir -p "$UNIVERSAL_DIR"
  LIB_SRC="${UNIVERSAL_DIR}/liboffsend_ffi.a"
  # Atomic replace so parallel per-arch Xcode script phases do not corrupt the .a.
  LIB_TMP="$(mktemp "${UNIVERSAL_DIR}/liboffsend_ffi.XXXXXX.a")"
  lipo -create "$LIB_ARM64" "$LIB_X64" -output "$LIB_TMP"
  mv -f "$LIB_TMP" "$LIB_SRC"
  echo "Built universal Offsend FFI: $(lipo -archs "$LIB_SRC")"
else
  cargo build -p offsend-ffi --release
  LIB_SRC="${REPO_ROOT}/target/release/liboffsend_ffi.a"
  test -f "$LIB_SRC"
fi

stage_vendor() {
  local vendor_dir="$1"
  mkdir -p "$vendor_dir"
  cp -f "$LIB_SRC" "${vendor_dir}/liboffsend_ffi.a"
  cp -f "$HEADER_SRC" "${vendor_dir}/OffsendFFI.h"
  cp -f "$HEADER_SRC" "${vendor_dir}/offsend_ffi.h"
  cat > "${vendor_dir}/module.modulemap" <<'EOF'
module OffsendFFI {
    header "OffsendFFI.h"
    export *
}
EOF
  # Keep an empty .gitkeep-friendly README for consumers.
  cat > "${vendor_dir}/README.md" <<'EOF'
# OffsendFFI (generated)

Staged by `scripts/ffi/build.sh`. Do not edit by hand.
EOF
  echo "Staged Offsend FFI at ${vendor_dir}"
}

if [[ "$STAGE_MACOS" == "1" ]]; then
  stage_vendor "${MACOS_APP_ROOT}/Vendor/OffsendFFI"
fi
if [[ "$STAGE_SERVER" == "1" ]]; then
  stage_vendor "${SERVER_ROOT}/Vendor/OffsendFFI"
fi
