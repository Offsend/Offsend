#!/usr/bin/env bash
# Installs Swift on Linux GitHub Actions runners (x86_64 and aarch64).
# setup-swift@v2 does not support ubuntu-*-arm runners yet.
set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.0.3}"

case "$(uname -m)" in
  x86_64) SWIFT_ARCH="x86_64" ;;
  aarch64) SWIFT_ARCH="aarch64" ;;
  *)
    echo "Unsupported Linux architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
fi

case "${VERSION_ID:-}" in
  22.04) UBUNTU_VERSION="22.04" ;;
  24.04) UBUNTU_VERSION="24.04" ;;
  *)
    echo "Unsupported Ubuntu version: ${VERSION_ID:-unknown}" >&2
    exit 1
    ;;
esac

SWIFT_BRANCH="swift-${SWIFT_VERSION}-release"
SWIFT_RELEASE="swift-${SWIFT_VERSION}-RELEASE"
SWIFT_PLATFORM="ubuntu${UBUNTU_VERSION}"

if [[ "$SWIFT_ARCH" == "aarch64" ]]; then
  PLATFORM_DIR="$(echo "$SWIFT_PLATFORM" | tr -d '.')-aarch64"
  ARCH_SUFFIX="-aarch64"
else
  PLATFORM_DIR="$(echo "$SWIFT_PLATFORM" | tr -d '.')"
  ARCH_SUFFIX=""
fi

TARBALL="${SWIFT_RELEASE}-${SWIFT_PLATFORM}${ARCH_SUFFIX}.tar.gz"
URL="https://download.swift.org/${SWIFT_BRANCH}/${PLATFORM_DIR}/${SWIFT_RELEASE}/${TARBALL}"
TOOL_ROOT="${RUNNER_TOOL_CACHE:-/opt/hostedtoolcache}/swift/${SWIFT_VERSION}/${PLATFORM_DIR}"
SWIFT_BIN="${TOOL_ROOT}/usr/bin/swift"

if [[ ! -x "$SWIFT_BIN" ]]; then
  echo "Installing Swift ${SWIFT_VERSION} from ${URL}"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fsSL "$URL" -o "${tmpdir}/swift.tar.gz"
  mkdir -p "$TOOL_ROOT"
  tar xzf "${tmpdir}/swift.tar.gz" -C "$TOOL_ROOT" --strip-components=1
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${TOOL_ROOT}/usr/bin" >> "$GITHUB_PATH"
fi
export PATH="${TOOL_ROOT}/usr/bin:${PATH}"

swift --version
