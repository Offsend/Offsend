#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <dmg-path> <cli-zip-path> [linux-x86_64-tarball] [linux-aarch64-tarball]}"
DMG_PATH="${2:?Usage: $0 <version> <dmg-path> <cli-zip-path> [linux-x86_64-tarball] [linux-aarch64-tarball]}"
CLI_ZIP_PATH="${3:?Usage: $0 <version> <dmg-path> <cli-zip-path> [linux-x86_64-tarball] [linux-aarch64-tarball]}"
LINUX_X86_64_TARBALL="${4:-}"
LINUX_AARCH64_TARBALL="${5:-}"
TAP_REPO="${TAP_REPO:-Offsend/homebrew-tap}"
TAP_BRANCH="${TAP_BRANCH:-main}"

test -n "${HOMEBREW_TAP_TOKEN:-}" || {
  echo "Missing HOMEBREW_TAP_TOKEN (PAT with contents:write on ${TAP_REPO})" >&2
  exit 1
}
test -f "$DMG_PATH" || {
  echo "DMG not found at $DMG_PATH" >&2
  exit 1
}
test -f "$CLI_ZIP_PATH" || {
  echo "CLI zip not found at $CLI_ZIP_PATH" >&2
  exit 1
}

DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
CLI_SHA256="$(shasum -a 256 "$CLI_ZIP_PATH" | awk '{print $1}')"
LINUX_X86_64_SHA256=""
LINUX_AARCH64_SHA256=""

if [[ -n "$LINUX_X86_64_TARBALL" ]]; then
  test -f "$LINUX_X86_64_TARBALL" || {
    echo "Linux x86_64 tarball not found at $LINUX_X86_64_TARBALL" >&2
    exit 1
  }
  LINUX_X86_64_SHA256="$(shasum -a 256 "$LINUX_X86_64_TARBALL" | awk '{print $1}')"
fi

if [[ -n "$LINUX_AARCH64_TARBALL" ]]; then
  test -f "$LINUX_AARCH64_TARBALL" || {
    echo "Linux aarch64 tarball not found at $LINUX_AARCH64_TARBALL" >&2
    exit 1
  }
  LINUX_AARCH64_SHA256="$(shasum -a 256 "$LINUX_AARCH64_TARBALL" | awk '{print $1}')"
fi

TAP_DIR="${TAP_DIR:-${RUNNER_TEMP:-/tmp}/homebrew-tap}"

rm -rf "$TAP_DIR"
if ! git clone --depth 1 \
  "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git" \
  "$TAP_DIR" 2>/dev/null; then
  rm -rf "$TAP_DIR"
  mkdir -p "$TAP_DIR"
  git -C "$TAP_DIR" init -b "$TAP_BRANCH"
  git -C "$TAP_DIR" remote add origin "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git"
fi

mkdir -p "$TAP_DIR/Casks"

cat > "$TAP_DIR/Casks/offsend.rb" <<'RUBY'
cask "offsend" do
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"

  url "https://github.com/Offsend/Offsend/releases/download/v#{version}/Offsend-#{version}.dmg"
  name "Offsend"
  desc "Prepare projects, files, and clipboard text before sharing with AI tools"
  homepage "https://offsend.io"

  livecheck do
    url "https://github.com/Offsend/Offsend/releases/latest"
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Offsend.app"

  zap trash: [
    "~/Library/Application Support/Offsend",
    "~/Library/Preferences/io.offsend.plist",
    "~/Library/Caches/io.offsend",
  ]
end
RUBY

sed -i '' \
  -e "s/VERSION_PLACEHOLDER/${VERSION}/g" \
  -e "s/SHA256_PLACEHOLDER/${DMG_SHA256}/g" \
  "$TAP_DIR/Casks/offsend.rb"

# The CLI ships as a Cask (not a Formula): it is a pre-built, Developer ID-signed
# binary plus signed frameworks. A Formula install triggers Homebrew's Mach-O
# relocation + ad-hoc re-signing, which breaks the Developer ID signature and fails
# on framework bundles ("bundle format is ambiguous", "load commands do not fit").
# Casks install the artifact verbatim, leaving the signature intact.
cat > "$TAP_DIR/Casks/offsend-cli.rb" <<'RUBY'
cask "offsend-cli" do
  version "VERSION_PLACEHOLDER"
  sha256 "CLI_SHA256_PLACEHOLDER"

  url "https://github.com/Offsend/Offsend/releases/download/v#{version}/offsend-cli-#{version}.zip"
  name "Offsend CLI"
  desc "Local sensitive data checks for developers (Offsend CLI)"
  homepage "https://offsend.io"

  livecheck do
    url "https://github.com/Offsend/Offsend/releases/latest"
    strategy :github_latest
  end

  depends_on macos: :ventura

  binary "offsend"

  zap trash: [
    "~/Library/Application Support/Offsend",
    "~/Library/Preferences/io.offsend.plist",
    "~/Library/Caches/io.offsend",
  ]
end
RUBY

sed -i '' \
  -e "s/VERSION_PLACEHOLDER/${VERSION}/g" \
  -e "s/CLI_SHA256_PLACEHOLDER/${CLI_SHA256}/g" \
  "$TAP_DIR/Casks/offsend-cli.rb"

if [[ -n "$LINUX_X86_64_SHA256" && -n "$LINUX_AARCH64_SHA256" ]]; then
  mkdir -p "$TAP_DIR/Formula"

  cat > "$TAP_DIR/Formula/offsend-cli.rb" <<'RUBY'
class OffsendCli < Formula
  desc "Local sensitive data checks for developers (Offsend CLI)"
  homepage "https://offsend.io"
  version "VERSION_PLACEHOLDER"
  license "Apache-2.0"

  on_linux do
    on_intel do
      url "https://github.com/Offsend/Offsend/releases/download/v#{version}/offsend-cli-#{version}-linux-x86_64.tar.gz"
      sha256 "LINUX_X86_64_SHA256_PLACEHOLDER"
    end
    on_arm do
      url "https://github.com/Offsend/Offsend/releases/download/v#{version}/offsend-cli-#{version}-linux-aarch64.tar.gz"
      sha256 "LINUX_AARCH64_SHA256_PLACEHOLDER"
    end
  end

  def install
    # Keep odie out of a top-level on_macos block: that runs on formula load
    # (brew tap / brew info on macOS), not only during install.
    odie "Install the macOS CLI with: brew install --cask offsend/tap/offsend-cli" if OS.mac?

    bin.install "offsend"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/offsend --version")
  end
end
RUBY

  sed -i '' \
    -e "s/VERSION_PLACEHOLDER/${VERSION}/g" \
    -e "s/LINUX_X86_64_SHA256_PLACEHOLDER/${LINUX_X86_64_SHA256}/g" \
    -e "s/LINUX_AARCH64_SHA256_PLACEHOLDER/${LINUX_AARCH64_SHA256}/g" \
    "$TAP_DIR/Formula/offsend-cli.rb"
fi

git -C "$TAP_DIR" config user.name "github-actions[bot]"
git -C "$TAP_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git -C "$TAP_DIR" add Casks/offsend.rb Casks/offsend-cli.rb
if [[ -f "$TAP_DIR/Formula/offsend-cli.rb" ]]; then
  git -C "$TAP_DIR" add Formula/offsend-cli.rb
fi

if git -C "$TAP_DIR" diff --cached --quiet; then
  echo "Homebrew tap already up to date for ${VERSION}"
  exit 0
fi

git -C "$TAP_DIR" commit -m "Update Offsend cask and offsend-cli to ${VERSION}"
git -C "$TAP_DIR" push -u origin "HEAD:${TAP_BRANCH}"

echo "Updated ${TAP_REPO} to Offsend ${VERSION}"
echo "  cask sha256: ${DMG_SHA256}"
echo "  offsend-cli cask sha256: ${CLI_SHA256}"
if [[ -n "$LINUX_X86_64_SHA256" ]]; then
  echo "  offsend-cli linux x86_64 sha256: ${LINUX_X86_64_SHA256}"
  echo "  offsend-cli linux aarch64 sha256: ${LINUX_AARCH64_SHA256}"
fi
