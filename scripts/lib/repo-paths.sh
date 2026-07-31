#!/usr/bin/env bash
# Shared path constants for scripts/**. Source from a script under scripts/<domain>/:
#   # shellcheck source=../lib/repo-paths.sh
#   source "$(cd "$(dirname "$0")" && pwd)/../lib/repo-paths.sh"
#
# Override with env when needed:
#   MACOS_APP_ROOT=/custom/path ./scripts/app/bootstrap.sh

# Resolve this file's directory (bash when sourced; zsh fallback).
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _OFFSEND_THIS="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  # shellcheck disable=SC2296
  _OFFSEND_THIS="${(%):-%x}"
else
  _OFFSEND_THIS="$0"
fi

_OFFSEND_SCRIPTS_DIR="$(cd "$(dirname "${_OFFSEND_THIS}")/.." && pwd)"
REPO_ROOT="$(cd "${_OFFSEND_SCRIPTS_DIR}/.." && pwd)"
MACOS_APP_ROOT="${MACOS_APP_ROOT:-${REPO_ROOT}/apps/macos}"
SERVER_ROOT="${SERVER_ROOT:-${REPO_ROOT}/server}"

# Xcode Run Script phases inherit a minimal PATH (no ~/.cargo/bin). Prepend
# common Rust / Homebrew locations so `cargo` works from Tuist build phases.
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

export REPO_ROOT MACOS_APP_ROOT SERVER_ROOT
