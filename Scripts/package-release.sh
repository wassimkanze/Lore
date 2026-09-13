#!/bin/bash
# Package the stapled app exported by Xcode. Never uploads credentials or local activity data.
set -euo pipefail
LORE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 PATH_TO_NOTARIZED_LORE_APP OUTPUT_ZIP" >&2
  exit 2
fi
LORE_APP="$1"
LORE_ZIP="$2"
[[ ! -e "$LORE_ZIP" ]] || { echo "Output already exists" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LORE_APP/Contents/Info.plist")" == "app.lore.mac" ]] || { echo "Expected the Lore app bundle" >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$LORE_APP"
/usr/bin/xcrun stapler validate "$LORE_APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$LORE_APP"
for LORE_BINARY in "$LORE_APP" "$LORE_APP/Contents/Library/HelperTools/LorePowerHelper"; do
  /usr/bin/codesign --display --verbose=4 "$LORE_BINARY" 2>&1 | /usr/bin/grep 'Authority=Developer ID Application:' >/dev/null
  if /usr/bin/codesign -d --entitlements :- "$LORE_BINARY" 2>/dev/null | /usr/bin/grep 'get-task-allow' >/dev/null; then
    echo "The distribution must not include the debug entitlement." >&2; exit 1
  fi
done
/usr/bin/lipo -archs "$LORE_APP/Contents/MacOS/Lore" | /usr/bin/grep -x arm64 >/dev/null
LORE_STAGE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lore-release.XXXXXX")"
trap '/bin/rm -rf "$LORE_STAGE"' EXIT
/usr/bin/ditto "$LORE_APP" "$LORE_STAGE/Lore.app"
/bin/cp "$LORE_ROOT/LICENSE" "$LORE_STAGE/LICENSE.txt"
cat > "$LORE_STAGE/Install Lore.txt" <<'INSTRUCTIONS'
Lore — Remember what you built.

Requires an Apple Silicon Mac running macOS 15 or newer.

1. Drag Lore.app into your Applications folder.
2. Open Lore and choose your development folders for read-only Git access.
3. To use Pulse with the lid closed, open the Pulse page and enable system access.
   macOS handles the one-time approval. Keep the Mac on a ventilated surface.

Before uninstalling, stop Pulse and remove its system access from the Pulse page.

Lore is free and MIT licensed. No account is needed to use it.
Source and support: https://github.com/wassimkanze/Lore
INSTRUCTIONS
/usr/bin/ditto -c -k --sequesterRsrc "$LORE_STAGE" "$LORE_ZIP"
echo "Release package ready: $LORE_ZIP"
