#!/usr/bin/env bash
# Publishes Scripts/install.sh to the Offsend/install GitHub Pages repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SCRIPT="${ROOT}/Scripts/install.sh"
SITE_TEMPLATE="${ROOT}/Scripts/install-site/index.html"
INSTALL_REPO="${INSTALL_REPO:-Offsend/install}"
INSTALL_BRANCH="${INSTALL_BRANCH:-main}"
SOURCE_SHA="${SOURCE_SHA:-local}"
SOURCE_REF="${SOURCE_REF:-local}"

test -f "$SOURCE_SCRIPT" || {
  echo "Missing source script at $SOURCE_SCRIPT" >&2
  exit 1
}
test -f "$SITE_TEMPLATE" || {
  echo "Missing site template at $SITE_TEMPLATE" >&2
  exit 1
}
test -n "${INSTALL_REPO_TOKEN:-}" || {
  echo "Missing INSTALL_REPO_TOKEN (PAT with contents:write on ${INSTALL_REPO})" >&2
  exit 1
}

bash -n "$SOURCE_SCRIPT"

SYNC_SOURCE="Offsend/Offsend@${SOURCE_SHA}"
if [[ "$SOURCE_REF" != "local" ]]; then
  SYNC_SOURCE="${SYNC_SOURCE} (${SOURCE_REF})"
fi

INSTALL_DIR="${INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/offsend-install}"
rm -rf "$INSTALL_DIR"

if ! git clone --depth 1 --branch "$INSTALL_BRANCH" \
  "https://x-access-token:${INSTALL_REPO_TOKEN}@github.com/${INSTALL_REPO}.git" \
  "$INSTALL_DIR" 2>/dev/null; then
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  git -C "$INSTALL_DIR" init -b "$INSTALL_BRANCH"
  git -C "$INSTALL_DIR" remote add origin "https://x-access-token:${INSTALL_REPO_TOKEN}@github.com/${INSTALL_REPO}.git"
fi

install -m 0755 "$SOURCE_SCRIPT" "$INSTALL_DIR/cli"
sed "s|SYNC_SOURCE|${SYNC_SOURCE}|g" "$SITE_TEMPLATE" > "$INSTALL_DIR/index.html"
printf '%s\n' 'install.offsend.io' > "$INSTALL_DIR/CNAME"
: > "$INSTALL_DIR/.nojekyll"

git -C "$INSTALL_DIR" config user.name "github-actions[bot]"
git -C "$INSTALL_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$INSTALL_DIR" add cli index.html CNAME .nojekyll

if git -C "$INSTALL_DIR" diff --cached --quiet; then
  echo "Install site already up to date (${SYNC_SOURCE})"
  exit 0
fi

git -C "$INSTALL_DIR" commit -m "Update install.offsend.io from ${SYNC_SOURCE}"
git -C "$INSTALL_DIR" push -u origin "HEAD:${INSTALL_BRANCH}"

echo "Updated ${INSTALL_REPO} (${SYNC_SOURCE})"
echo "  cli script: ${SOURCE_SCRIPT}"
echo "  site: https://install.offsend.io/"
