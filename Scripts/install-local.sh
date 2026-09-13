#!/bin/bash
# Install a locally signed build at one stable per-user path. Never installs the privileged service.
set -euo pipefail
LORE_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LORE_BUILD_CONFIG="${1:-Release}"
LORE_INSTALL_ROOT="$HOME/Applications"
LORE_APP_SOURCE="$LORE_PROJECT_ROOT/build/Build/Products/$LORE_BUILD_CONFIG/Lore.app"
LORE_APP_DESTINATION="$LORE_INSTALL_ROOT/Lore.app"
if [[ ! -d "$LORE_APP_SOURCE" ]]; then
  echo "Build Lore in $LORE_BUILD_CONFIG first." >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$LORE_APP_SOURCE"
LORE_HELPER_RELATIVE="Contents/Library/HelperTools/LorePowerHelper"
if [[ -e "$LORE_APP_DESTINATION/$LORE_HELPER_RELATIVE" ]] && ! /usr/bin/cmp -s "$LORE_APP_DESTINATION/$LORE_HELPER_RELATIVE" "$LORE_APP_SOURCE/$LORE_HELPER_RELATIVE" && /bin/launchctl print system/app.lore.power-helper >/dev/null 2>&1; then
  echo "The power helper changed. Stop its session and remove its registration in Lore Settings before installing. Set it up again afterwards; macOS retains the existing developer approval." >&2
  exit 1
fi
mkdir -p "$LORE_INSTALL_ROOT"
LORE_STAGING="$(/usr/bin/mktemp -d "$LORE_INSTALL_ROOT/.lore-install.XXXXXX")"
trap 'rmdir "$LORE_STAGING" 2>/dev/null || true' EXIT
/usr/bin/ditto "$LORE_APP_SOURCE" "$LORE_STAGING/Lore.app"
if [[ -e "$LORE_APP_DESTINATION" ]]; then
  LORE_BACKUP="$LORE_PROJECT_ROOT/build/Lore.previous.$(/bin/date +%s).app"
  /usr/bin/ditto "$LORE_APP_DESTINATION" "$LORE_BACKUP"
  if /usr/bin/cmp -s "$LORE_APP_DESTINATION/$LORE_HELPER_RELATIVE" "$LORE_STAGING/Lore.app/$LORE_HELPER_RELATIVE"; then
    # Keep the running helper's executable vnode/signature valid for UI-only updates.
    /bin/ln "$LORE_APP_DESTINATION/$LORE_HELPER_RELATIVE" "$LORE_STAGING/RunningPowerHelper"
  fi
  # Preserve the bundle directory identity used by macOS background-item registration.
  /bin/mv "$LORE_APP_DESTINATION/Contents" "$LORE_STAGING/PreviousContents"
  /bin/mv "$LORE_STAGING/Lore.app/Contents" "$LORE_APP_DESTINATION/Contents"
  if [[ -e "$LORE_STAGING/RunningPowerHelper" ]]; then
    /bin/mv -f "$LORE_STAGING/RunningPowerHelper" "$LORE_APP_DESTINATION/$LORE_HELPER_RELATIVE"
  fi
  if /usr/bin/codesign --verify --deep --strict "$LORE_APP_DESTINATION"; then
    /bin/rm -rf "$LORE_STAGING/PreviousContents"
    /bin/rmdir "$LORE_STAGING/Lore.app"
  else
    /bin/rm -rf "$LORE_APP_DESTINATION/Contents"
    /bin/mv "$LORE_STAGING/PreviousContents" "$LORE_APP_DESTINATION/Contents"
    echo "Installation failed; the previous bundle was restored." >&2
    exit 1
  fi
else
  /bin/mv "$LORE_STAGING/Lore.app" "$LORE_APP_DESTINATION"
fi
echo "$LORE_APP_DESTINATION"
