#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <dmg-path>}"
DMG_PATH="${2:?Usage: $0 <version> <dmg-path>}"
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

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
TAP_DIR="${TAP_DIR:-$RUNNER_TEMP/homebrew-tap}"

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

  depends_on macos: ">= :ventura"

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
  -e "s/SHA256_PLACEHOLDER/${SHA256}/g" \
  "$TAP_DIR/Casks/offsend.rb"

git -C "$TAP_DIR" config user.name "github-actions[bot]"
git -C "$TAP_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$TAP_DIR" add Casks/offsend.rb

if git -C "$TAP_DIR" diff --cached --quiet; then
  echo "Homebrew cask already up to date for ${VERSION}"
  exit 0
fi

git -C "$TAP_DIR" commit -m "Update Offsend cask to ${VERSION}"
git -C "$TAP_DIR" push -u origin "HEAD:${TAP_BRANCH}"

echo "Updated ${TAP_REPO} to Offsend ${VERSION} (sha256: ${SHA256})"
