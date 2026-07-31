#!/usr/bin/env bash
# Pins Offsend/ai-hygiene to a newly released offsend-cli version:
# versions.json checksums, action.yml / README defaults, then retags v1.
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <cli-zip-path> <linux-x86_64-tarball> <linux-aarch64-tarball>}"
CLI_ZIP_PATH="${2:?Usage: $0 <version> <cli-zip-path> <linux-x86_64-tarball> <linux-aarch64-tarball>}"
LINUX_X86_64_TARBALL="${3:?Usage: $0 <version> <cli-zip-path> <linux-x86_64-tarball> <linux-aarch64-tarball>}"
LINUX_AARCH64_TARBALL="${4:?Usage: $0 <version> <cli-zip-path> <linux-x86_64-tarball> <linux-aarch64-tarball>}"

ACTION_REPO="${ACTION_REPO:-Offsend/ai-hygiene}"
ACTION_BRANCH="${ACTION_BRANCH:-main}"
TOKEN="${AI_HYGIENE_TOKEN:-${HOMEBREW_TAP_TOKEN:-}}"

test -n "$TOKEN" || {
  echo "Missing AI_HYGIENE_TOKEN (or HOMEBREW_TAP_TOKEN) with contents:write on ${ACTION_REPO}" >&2
  exit 1
}
test -f "$CLI_ZIP_PATH" || {
  echo "CLI zip not found at $CLI_ZIP_PATH" >&2
  exit 1
}
test -f "$LINUX_X86_64_TARBALL" || {
  echo "Linux x86_64 tarball not found at $LINUX_X86_64_TARBALL" >&2
  exit 1
}
test -f "$LINUX_AARCH64_TARBALL" || {
  echo "Linux aarch64 tarball not found at $LINUX_AARCH64_TARBALL" >&2
  exit 1
}

DARWIN_SHA256="$(shasum -a 256 "$CLI_ZIP_PATH" | awk '{print $1}')"
LINUX_X86_64_SHA256="$(shasum -a 256 "$LINUX_X86_64_TARBALL" | awk '{print $1}')"
LINUX_AARCH64_SHA256="$(shasum -a 256 "$LINUX_AARCH64_TARBALL" | awk '{print $1}')"

ACTION_DIR="${ACTION_DIR:-${RUNNER_TEMP:-/tmp}/ai-hygiene}"
rm -rf "$ACTION_DIR"
git clone --depth 1 \
  "https://x-access-token:${TOKEN}@github.com/${ACTION_REPO}.git" \
  "$ACTION_DIR"

git -C "$ACTION_DIR" config user.name "github-actions[bot]"
git -C "$ACTION_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"

VERSION="$VERSION" \
DARWIN_SHA256="$DARWIN_SHA256" \
LINUX_X86_64_SHA256="$LINUX_X86_64_SHA256" \
LINUX_AARCH64_SHA256="$LINUX_AARCH64_SHA256" \
ACTION_DIR="$ACTION_DIR" \
python3 - <<'PY'
import json
import os
import re
from pathlib import Path

version = os.environ["VERSION"]
action_dir = Path(os.environ["ACTION_DIR"])

versions_path = action_dir / "scripts" / "versions.json"
versions = json.loads(versions_path.read_text(encoding="utf-8"))
versions[version] = {
    "darwin": {"sha256": os.environ["DARWIN_SHA256"]},
    "linux-x86_64": {"sha256": os.environ["LINUX_X86_64_SHA256"]},
    "linux-aarch64": {"sha256": os.environ["LINUX_AARCH64_SHA256"]},
}
versions_path.write_text(json.dumps(versions, indent=2) + "\n", encoding="utf-8")

action_yml = action_dir / "action.yml"
action_text = action_yml.read_text(encoding="utf-8")
action_text, action_n = re.subn(
    r'(version:\n(?:[ \t]+.+\n)*?[ \t]+default:\s*")[^"]*(")',
    rf"\g<1>{version}\2",
    action_text,
    count=1,
)
if action_n != 1:
    raise SystemExit("Could not update inputs.version.default in action.yml")
action_yml.write_text(action_text, encoding="utf-8")

readme = action_dir / "README.md"
readme_text = readme.read_text(encoding="utf-8")
readme_text, n1 = re.subn(
    r"(\|\s*`version`\s*\|\s`)[^`]+(`\s*\|\s*`offsend-cli` release to install\s*\|)",
    rf"\g<1>{version}\2",
    readme_text,
    count=1,
)
readme_text, n2 = re.subn(
    r"(OFFSEND_VERSION=)[0-9]+(?:\.[0-9]+)*( ./scripts/install\.sh)",
    rf"\g<1>{version}\2",
    readme_text,
    count=1,
)
if n1 != 1 or n2 != 1:
    raise SystemExit(
        f"Could not update README version pins (table={n1}, install={n2})"
    )
readme.write_text(readme_text, encoding="utf-8")
PY

git -C "$ACTION_DIR" add scripts/versions.json action.yml README.md

if git -C "$ACTION_DIR" diff --cached --quiet; then
  echo "ai-hygiene already pinned to offsend-cli ${VERSION}"
  exit 0
fi

git -C "$ACTION_DIR" commit -m "Pin offsend-cli to ${VERSION}"
git -C "$ACTION_DIR" push origin "HEAD:${ACTION_BRANCH}"

LATEST_TAG="$(
  git ls-remote --tags --refs "https://x-access-token:${TOKEN}@github.com/${ACTION_REPO}.git" \
    | awk '{print $2}' \
    | sed 's|refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1 || true
)"

if [[ -z "$LATEST_TAG" ]]; then
  NEW_TAG="v1.0.0"
else
  IFS=. read -r major minor patch <<<"${LATEST_TAG#v}"
  NEW_TAG="v${major}.${minor}.$((patch + 1))"
fi

git -C "$ACTION_DIR" tag -a "$NEW_TAG" -m "Pin offsend-cli ${VERSION}"
git -C "$ACTION_DIR" tag -f v1 "$NEW_TAG"
git -C "$ACTION_DIR" push origin "refs/tags/${NEW_TAG}"
git -C "$ACTION_DIR" push -f origin refs/tags/v1

echo "Updated ${ACTION_REPO}: pinned offsend-cli ${VERSION}"
echo "  action tag: ${NEW_TAG} (floating v1 moved)"
echo "  darwin sha256: ${DARWIN_SHA256}"
echo "  linux-x86_64 sha256: ${LINUX_X86_64_SHA256}"
echo "  linux-aarch64 sha256: ${LINUX_AARCH64_SHA256}"
