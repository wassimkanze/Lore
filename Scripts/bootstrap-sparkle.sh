#!/bin/bash
# Pin and verify the official Sparkle 2.10.0 binary release; no private key in the repository.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/build/deps"
[[ -d "$DEST/Sparkle.framework" && -x "$DEST/bin/sign_update" ]] && exit 0
ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/lore-sparkle.XXXXXX")"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lore-sparkle-stage.XXXXXX")"
trap 'rm -f "$ARCHIVE"; rm -rf "$STAGE"' EXIT
/usr/bin/curl --fail --location --silent --show-error --retry 2 \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$ARCHIVE"
printf '%s  %s\n' c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c "$ARCHIVE" | /usr/bin/shasum -a 256 -c - >/dev/null
/usr/bin/tar -xf "$ARCHIVE" -C "$STAGE" ./Sparkle.framework ./bin ./LICENSE
mkdir -p "$DEST"
/bin/mv "$STAGE/Sparkle.framework" "$DEST/Sparkle.framework"
/bin/mv "$STAGE/bin" "$DEST/bin"
/bin/mv "$STAGE/LICENSE" "$DEST/Sparkle-LICENSE"
echo "Verified Sparkle 2.10.0 in $DEST"
