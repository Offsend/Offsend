#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <dmg-path> <cli-zip-path>}"
DMG_PATH="${2:?Usage: $0 <version> <dmg-path> <cli-zip-path>}"
CLI_ZIP_PATH="${3:?Usage: $0 <version> <dmg-path> <cli-zip-path>}"
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

mkdir -p "$TAP_DIR/Casks" "$TAP_DIR/Formula"

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

cat > "$TAP_DIR/Formula/offsend-cli.rb" <<'RUBY'
class OffsendCli < Formula
  desc "Local sensitive data checks for developers (Offsend CLI)"
  homepage "https://offsend.io"
  url "https://github.com/Offsend/Offsend/releases/download/vVERSION_PLACEHOLDER/offsend-cli-VERSION_PLACEHOLDER.zip"
  sha256 "CLI_SHA256_PLACEHOLDER"
  version "VERSION_PLACEHOLDER"

  def install
    libexec.install Dir["*"]
    (bin/"offsend").write <<~EOS
      #!/bin/bash
      exec "#{libexec}/offsend" "$@"
    EOS
    chmod 0755, bin/"offsend"
  end

  test do
    assert_match "offsend", shell_output("#{bin}/offsend --version")
  end
end
RUBY

sed -i '' \
  -e "s/VERSION_PLACEHOLDER/${VERSION}/g" \
  -e "s/CLI_SHA256_PLACEHOLDER/${CLI_SHA256}/g" \
  "$TAP_DIR/Formula/offsend-cli.rb"

git -C "$TAP_DIR" config user.name "github-actions[bot]"
git -C "$TAP_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$TAP_DIR" add Casks/offsend.rb Formula/offsend-cli.rb

if git -C "$TAP_DIR" diff --cached --quiet; then
  echo "Homebrew tap already up to date for ${VERSION}"
  exit 0
fi

git -C "$TAP_DIR" commit -m "Update Offsend cask and offsend-cli formula to ${VERSION}"
git -C "$TAP_DIR" push -u origin "HEAD:${TAP_BRANCH}"

echo "Updated ${TAP_REPO} to Offsend ${VERSION}"
echo "  cask sha256: ${DMG_SHA256}"
echo "  offsend-cli sha256: ${CLI_SHA256}"
