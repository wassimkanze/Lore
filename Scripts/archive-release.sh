#!/bin/bash
# Build a distribution archive. Arguments are public signing identifiers, never credentials.
set -euo pipefail
LORE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 DEVELOPER_ID_IDENTITY_SHA1 TEAM_ID" >&2
  exit 2
fi
LORE_IDENTITY="$1"
LORE_TEAM="$2"
[[ "$LORE_IDENTITY" =~ ^[A-Fa-f0-9]{40}$ && "$LORE_TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid signing identifiers" >&2; exit 2; }
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F "$LORE_IDENTITY" | /usr/bin/grep 'Developer ID Application:' >/dev/null; then
  echo "The selected Developer ID Application identity must be available in the keychain." >&2
  exit 1
fi
mkdir -p "$LORE_ROOT/build/distribution"
LORE_RUN="$(/usr/bin/mktemp -d "$LORE_ROOT/build/distribution/release.XXXXXX")"
/usr/bin/xcodebuild -project "$LORE_ROOT/Lore.xcodeproj" -scheme Lore -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$LORE_ROOT/build/distribution-derived" \
  -archivePath "$LORE_RUN/Lore.xcarchive" \
  LORE_CODE_SIGN_IDENTITY="$LORE_IDENTITY" LORE_DEVELOPMENT_TEAM="$LORE_TEAM" \
  OTHER_CODE_SIGN_FLAGS='--timestamp' CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO archive
LORE_APP="$LORE_RUN/Lore.xcarchive/Products/Applications/Lore.app"
/usr/bin/codesign --verify --deep --strict "$LORE_APP"
for LORE_BINARY in "$LORE_APP" "$LORE_APP/Contents/Library/HelperTools/LorePowerHelper"; do
  /usr/bin/codesign --display --verbose=4 "$LORE_BINARY" 2>&1 | /usr/bin/grep 'Authority=Developer ID Application:' >/dev/null
  /usr/bin/codesign --display --verbose=4 "$LORE_BINARY" 2>&1 | /usr/bin/grep 'Timestamp=' >/dev/null
  /usr/bin/codesign --display --verbose=4 "$LORE_BINARY" 2>&1 | /usr/bin/grep 'runtime' >/dev/null
  if /usr/bin/codesign -d --entitlements :- "$LORE_BINARY" 2>/dev/null | /usr/bin/grep 'get-task-allow' >/dev/null; then
    echo "Distribution must not contain the debug entitlement." >&2; exit 1
  fi
done
/usr/bin/lipo -archs "$LORE_APP/Contents/MacOS/Lore" | /usr/bin/grep -x arm64 >/dev/null
/usr/bin/ditto -c -k --keepParent "$LORE_APP" "$LORE_RUN/Lore-notarization.zip"
echo "Distribution archive ready: $LORE_RUN"
