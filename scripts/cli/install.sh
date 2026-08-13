#!/usr/bin/env bash
# Installs the Offsend CLI from GitHub Releases on macOS and Linux.
#
# Usage:
#   curl -fsSL https://install.offsend.io/cli | bash
#   curl -fsSL https://raw.githubusercontent.com/Offsend/Offsend/main/scripts/cli/install.sh | bash
#
# Deploy: serve this file verbatim at https://install.offsend.io/cli
# (Content-Type: text/plain; charset=utf-8).
#
# Environment:
#   OFFSEND_VERSION      Release version (default: latest), e.g. 0.0.6
#   OFFSEND_REPO         GitHub repo (default: Offsend/Offsend)
#   OFFSEND_INSTALL_DIR  Directory for the `offsend` command (default: /usr/local/bin)
#   OFFSEND_PREFIX       macOS install root for binary + Frameworks (default: /opt/offsend/cli)
#   GITHUB_TOKEN         Optional token, raises the GitHub API rate limit
set -euo pipefail

REPO="${OFFSEND_REPO:-Offsend/Offsend}"
VERSION="${OFFSEND_VERSION:-latest}"
INSTALL_DIR="${OFFSEND_INSTALL_DIR:-/usr/local/bin}"
PREFIX="${OFFSEND_PREFIX:-/opt/offsend/cli}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

using_default_install_paths() {
  [[ "$INSTALL_DIR" == "/usr/local/bin" && "$PREFIX" == "/opt/offsend/cli" ]]
}

using_default_linux_install_path() {
  [[ "$INSTALL_DIR" == "/usr/local/bin" ]]
}

brew_command() {
  command -v brew >/dev/null 2>&1
}

print_existing_macos_install_help() {
  local found=0
  local offsend_path

  if brew_command && brew list --cask --versions offsend >/dev/null 2>&1; then
    found=1
  fi
  if brew_command && brew list --cask --versions offsend-cli >/dev/null 2>&1; then
    found=1
  fi
  if [[ -d /Applications/Offsend.app ]]; then
    found=1
  fi
  if command -v offsend >/dev/null 2>&1; then
    offsend_path="$(command -v offsend)"
    case "$offsend_path" in
      */homebrew/*|*/Cellar/*|*/Caskroom/*|/opt/offsend/cli/*|/Applications/Offsend.app/*)
        found=1
        ;;
    esac
  fi
  if [[ -d "$PREFIX" ]] && using_default_install_paths; then
    found=1
  fi

  if [[ "$found" -eq 0 ]]; then
    return 1
  fi

  echo "Offsend is already installed on this Mac:" >&2
  if brew_command && brew list --cask --versions offsend >/dev/null 2>&1; then
    echo "  - Offsend app (Homebrew cask offsend/tap/offsend)" >&2
  fi
  if brew_command && brew list --cask --versions offsend-cli >/dev/null 2>&1; then
    echo "  - Offsend CLI (Homebrew cask offsend/tap/offsend-cli)" >&2
  fi
  if [[ -d /Applications/Offsend.app ]]; then
    echo "  - Offsend.app in /Applications" >&2
  fi
  if command -v offsend >/dev/null 2>&1; then
    offsend_path="$(command -v offsend)"
    case "$offsend_path" in
      */homebrew/*|*/Cellar/*|*/Caskroom/*|/opt/offsend/cli/*|/Applications/Offsend.app/*)
        echo "  - offsend command at ${offsend_path}" >&2
        ;;
    esac
  fi
  if [[ -d "$PREFIX" ]] && using_default_install_paths; then
    echo "  - previous CLI install at ${PREFIX}" >&2
  fi
  echo "" >&2
  echo "This install script is for a fresh system-wide install. To update what you already have:" >&2
  echo "  brew upgrade --cask offsend/tap/offsend-cli   # standalone CLI" >&2
  echo "  brew upgrade --cask offsend/tap/offsend         # macOS app" >&2
  echo "" >&2
  echo "To reinstall with this script instead, remove the existing install first:" >&2
  echo "  brew uninstall --cask offsend-cli" >&2
  echo "  brew uninstall --cask offsend" >&2
  echo "  sudo rm -rf /opt/offsend/cli /usr/local/bin/offsend" >&2
  echo "" >&2
  echo "Or install to your home directory without sudo:" >&2
  echo "  OFFSEND_INSTALL_DIR=\$HOME/.local/bin OFFSEND_PREFIX=\$HOME/.local/lib/offsend/cli \\" >&2
  echo "    curl -fsSL https://install.offsend.io/cli | bash" >&2
  return 0
}

print_existing_linux_install_help() {
  if ! brew_command || ! brew list --formula --versions offsend-cli >/dev/null 2>&1; then
    return 1
  fi

  echo "Offsend is already installed on this system:" >&2
  echo "  - Offsend CLI (Homebrew formula offsend/tap/offsend-cli)" >&2
  if command -v offsend >/dev/null 2>&1; then
    echo "  - offsend command at $(command -v offsend)" >&2
  fi
  echo "" >&2
  echo "This install script is for a fresh system-wide install. To update what you already have:" >&2
  echo "  brew upgrade offsend/tap/offsend-cli" >&2
  echo "" >&2
  echo "To reinstall with this script instead, remove the existing install first:" >&2
  echo "  brew uninstall offsend-cli" >&2
  echo "  sudo rm -f /usr/local/bin/offsend" >&2
  echo "" >&2
  echo "Or install to your home directory without sudo:" >&2
  echo "  OFFSEND_INSTALL_DIR=\$HOME/.local/bin \\" >&2
  echo "    curl -fsSL https://install.offsend.io/cli | bash" >&2
  return 0
}

ensure_directory() {
  local dir="$1"
  if mkdir -p "$dir" 2>/dev/null; then
    return 0
  fi
  echo "Cannot create or write to ${dir}." >&2
  if [[ "$(uname -s)" == "Darwin" ]] && using_default_install_paths && print_existing_macos_install_help; then
    exit 1
  fi
  if [[ "$(uname -s)" == "Linux" ]] && using_default_linux_install_path && print_existing_linux_install_help; then
    exit 1
  fi
  echo "Set OFFSEND_INSTALL_DIR / OFFSEND_PREFIX to a writable location, or re-run with sufficient permissions." >&2
  exit 1
}

# Queries the GitHub API and turns every failure mode into an actionable
# message. Plain `curl -f` would abort the script with no output at all, which
# is what an anonymous caller hits after 60 requests per hour from one IP.
github_api() {
  local url="$1"
  local response status body
  local -a auth=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  response="$(curl -sSL -w '\n%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    ${auth[@]+"${auth[@]}"} "$url" 2>/dev/null || true)"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  case "$status" in
    200)
      printf '%s' "$body"
      ;;
    401|403|429)
      if printf '%s' "$body" | grep -qi 'rate limit'; then
        echo "GitHub API rate limit reached for this network." >&2
        echo "Wait a few minutes, or re-run with a token:" >&2
        echo "  GITHUB_TOKEN=<token> bash -c \"\$(curl -fsSL https://install.offsend.io/cli)\"" >&2
      else
        echo "GitHub API refused the request (HTTP ${status}): ${url}" >&2
        echo "If GITHUB_TOKEN is set, check that it is valid and not expired." >&2
      fi
      exit 1
      ;;
    404)
      echo "Not found: ${url}" >&2
      echo "Check OFFSEND_VERSION (${VERSION}) and OFFSEND_REPO (${REPO})." >&2
      exit 1
      ;;
    000|"")
      echo "Could not reach the GitHub API. Check your network or proxy settings." >&2
      exit 1
      ;;
    *)
      echo "GitHub API request failed (HTTP ${status}): ${url}" >&2
      exit 1
      ;;
  esac
}

resolve_latest_version() {
  local response tag
  response="$(github_api "https://api.github.com/repos/${REPO}/releases/latest")"
  tag="$(printf '%s' "$response" | tr -d '\n' | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  tag="${tag#v}"
  if [[ -z "$tag" ]]; then
    echo "Could not resolve latest release for ${REPO}" >&2
    exit 1
  fi
  printf '%s' "$tag"
}

release_base_url() {
  printf 'https://github.com/%s/releases/download/v%s' "$REPO" "$1"
}

file_sha256() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    echo "Missing required command: shasum or sha256sum" >&2
    exit 1
  fi
}

fetch_asset_sha256() {
  local version="$1"
  local filename="$2"
  local response assets remainder name_pattern digest

  response="$(github_api "https://api.github.com/repos/${REPO}/releases/tags/v${version}")"

  # Read the digest without a JSON parser: an install script cannot assume
  # python3 or jq exists. Narrow to the assets array, cut to the named asset,
  # then take the first digest that follows it -- GitHub emits `digest` after
  # `name` inside the same asset object. The API pretty-prints, so every pattern
  # has to tolerate whitespace around the colons.
  assets="$(printf '%s' "$response" | tr -d '\n' \
    | sed -n 's/.*"assets"[[:space:]]*:[[:space:]]*\[//p')"
  if [[ -z "$assets" ]]; then
    echo "Unexpected GitHub API response for ${REPO} v${version}: no assets array." >&2
    exit 1
  fi

  name_pattern="\"name\"[[:space:]]*:[[:space:]]*\"${filename//./\\.}\""
  if ! printf '%s' "$assets" | grep -q "$name_pattern"; then
    echo "Release ${REPO} v${version} has no asset named ${filename}" >&2
    exit 1
  fi
  remainder="$(printf '%s' "$assets" | sed -e "s/.*${name_pattern}//")"
  digest="$(printf '%s' "$remainder" \
    | grep -o '"digest"[[:space:]]*:[[:space:]]*"sha256:[0-9a-f]\{64\}"' \
    | head -1 \
    | sed -e 's/.*sha256://' -e 's/"$//' || true)"

  if [[ -z "$digest" ]]; then
    echo "Could not find SHA-256 digest for ${filename} in ${REPO} v${version}" >&2
    echo "This release may predate GitHub asset digests; install a newer version." >&2
    exit 1
  fi
  printf '%s' "$digest"
}

verify_download() {
  local path="$1"
  local expected="$2"
  local actual

  actual="$(file_sha256 "$path")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum mismatch for $(basename "$path")" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
  echo "Checksum OK (${actual:0:12}...)"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64' ;;
    arm64|aarch64) printf 'aarch64' ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

install_linux() {
  local arch="$1"
  local tarball url workdir expected_sha

  if using_default_linux_install_path && print_existing_linux_install_help; then
    exit 1
  fi

  if command -v offsend >/dev/null 2>&1 && using_default_linux_install_path; then
    echo "Updating existing offsend install at $(command -v offsend)..."
  fi

  tarball="offsend-cli-${VERSION}-linux-${arch}.tar.gz"
  url="$(release_base_url "$VERSION")/${tarball}"
  expected_sha="$(fetch_asset_sha256 "$VERSION" "$tarball")"

  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  echo "Downloading ${tarball}..."
  curl -fsSL "$url" -o "$workdir/$tarball"
  verify_download "$workdir/$tarball" "$expected_sha"
  tar -xzf "$workdir/$tarball" -C "$workdir"
  test -x "$workdir/offsend"

  ensure_directory "$INSTALL_DIR"
  install -m 0755 "$workdir/offsend" "$INSTALL_DIR/offsend"

  echo "Installed offsend ${VERSION} to ${INSTALL_DIR}/offsend"
  "$INSTALL_DIR/offsend" --version
}

install_macos() {
  local archive url workdir install_root expected_sha

  if using_default_install_paths && print_existing_macos_install_help; then
    exit 1
  fi

  require_command unzip

  archive="offsend-cli-${VERSION}.zip"
  url="$(release_base_url "$VERSION")/${archive}"
  expected_sha="$(fetch_asset_sha256 "$VERSION" "$archive")"
  install_root="${PREFIX}/${VERSION}"

  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  echo "Downloading ${archive}..."
  curl -fsSL "$url" -o "$workdir/$archive"
  verify_download "$workdir/$archive" "$expected_sha"
  unzip -q "$workdir/$archive" -d "$workdir/extracted"
  test -x "$workdir/extracted/offsend"
  test -d "$workdir/extracted/Frameworks"

  ensure_directory "$install_root"
  ensure_directory "$INSTALL_DIR"

  rm -rf "$install_root"
  mkdir -p "$install_root"
  cp -R "$workdir/extracted/offsend" "$workdir/extracted/Frameworks" "$install_root/"
  chmod +x "$install_root/offsend"
  ln -sf "$install_root/offsend" "$INSTALL_DIR/offsend"

  echo "Installed offsend ${VERSION} to ${INSTALL_DIR}/offsend"
  echo "Runtime files: ${install_root}"
  "$INSTALL_DIR/offsend" --version
}

main() {
  require_command curl

  if [[ "$VERSION" == "latest" ]]; then
    VERSION="$(resolve_latest_version)"
  fi

  case "$(uname -s)" in
    Linux)
      install_linux "$(detect_arch)"
      ;;
    Darwin)
      install_macos
      ;;
    *)
      echo "Unsupported operating system: $(uname -s)" >&2
      echo "Offsend CLI installs on macOS and Linux. On Windows, use WSL or Docker." >&2
      exit 1
      ;;
  esac

  if [[ -x "${INSTALL_DIR}/offsend" ]]; then
    echo "Configuring machine defaults (seal key + user-level editor hooks)..."
    "${INSTALL_DIR}/offsend" setup || {
      echo "warning: offsend setup failed; run: offsend setup" >&2
    }
  fi
}

main "$@"
