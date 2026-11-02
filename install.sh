#!/bin/zsh
# Appshot installer.
#   curl -fsSL https://raw.githubusercontent.com/anoojpatel/appshot/main/install.sh | zsh
set -euo pipefail

REPO="anoojpatel/appshot"
DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "→ Downloading Appshot…"
if curl -fsSL "https://github.com/$REPO/releases/latest/download/Appshot.zip" -o "$TMP/Appshot.zip"; then
  ditto -x -k "$TMP/Appshot.zip" "$TMP"
else
  # No release yet: build from source (needs Xcode Command Line Tools).
  if ! command -v swiftc >/dev/null; then
    echo "✗ Couldn't download a release, and Swift isn't installed to build one."
    echo "  Run: xcode-select --install   then try again."
    exit 1
  fi
  echo "→ No release found, building from source…"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP"
  zsh "$TMP/appshot-main/build.sh" >/dev/null
  mv "$TMP/appshot-main/Appshot.app" "$TMP/Appshot.app"
fi

pkill -x Appshot 2>/dev/null || true
rm -rf "$DEST/Appshot.app"
mv "$TMP/Appshot.app" "$DEST/Appshot.app"
# The app isn't notarized, so clear the "downloaded from the internet" flag.
xattr -dr com.apple.quarantine "$DEST/Appshot.app" 2>/dev/null || true

open "$DEST/Appshot.app"
echo "✓ Appshot is installed in $DEST and running. Look for the crosshair icon in your menu bar."
echo "  Press ⌃⌥L (Control + Option + L) to take your first shot."
