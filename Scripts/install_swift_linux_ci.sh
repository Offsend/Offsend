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
  22.04)
    UBUNTU_RELEASE="2204"
    UBUNTU_VERSION="22.04"
    ;;
  24.04)
    UBUNTU_RELEASE="2404"
    UBUNTU_VERSION="24.04"
    ;;
  *)
    echo "Unsupported Ubuntu version: ${VERSION_ID:-unknown}" >&2
    exit 1
    ;;
esac

if [[ "$SWIFT_ARCH" == "x86_64" ]]; then
  TARBALL="swift-${SWIFT_VERSION}-RELEASE-ubuntu${UBUNTU_VERSION}.tar.gz"
else
  TARBALL="swift-${SWIFT_VERSION}-RELEASE-ubuntu${UBUNTU_VERSION}-${SWIFT_ARCH}.tar.gz"
fi

URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu${UBUNTU_RELEASE}/${SWIFT_ARCH}/${TARBALL}"
TOOL_ROOT="${RUNNER_TOOL_CACHE:-/opt/hostedtoolcache}/swift/${SWIFT_VERSION}/ubuntu${UBUNTU_RELEASE}/${SWIFT_ARCH}"
SWIFT_BIN="${TOOL_ROOT}/usr/bin/swift"

if [[ ! -x "$SWIFT_BIN" ]]; then
  echo "Installing Swift ${SWIFT_VERSION} from ${URL}"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fsSL "$URL" -o "${tmpdir}/swift.tar.gz"
  mkdir -p "$TOOL_ROOT"
  tar xzf "${tmpdir}/swift.tar.gz" -C "$tmpdir"
  shopt -s dotglob nullglob
  mv "${tmpdir}"/swift-*/* "$TOOL_ROOT/"
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${TOOL_ROOT}/usr/bin" >> "$GITHUB_PATH"
fi
export PATH="${TOOL_ROOT}/usr/bin:${PATH}"

swift --version
