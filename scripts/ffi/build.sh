#!/usr/bin/env bash
# Build offsend-ffi static library and stage it for the macOS app and/or server.
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
cargo build -p offsend-ffi --release

LIB_SRC="${REPO_ROOT}/target/release/liboffsend_ffi.a"
HEADER_SRC="${REPO_ROOT}/crates/offsend-ffi/include/offsend_ffi.h"
test -f "$LIB_SRC"
test -f "$HEADER_SRC"

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
