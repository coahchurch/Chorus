#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
MAC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$MAC_DIR/../.." && pwd)"
BACKUP="${CHORUS_LIBRARY_BACKUP:-$HOME/Desktop/Library 2026-11-03.mxubackup}"
IDENTITY="${DEVELOPER_ID_IDENTITY:?set DEVELOPER_ID_IDENTITY to your Developer ID Application identity}"
INSTALLER_IDENTITY="${DEVELOPER_ID_INSTALLER_IDENTITY:?set DEVELOPER_ID_INSTALLER_IDENTITY to your Developer ID Installer identity}"
PROFILE="${NOTARIZATION_PROFILE:-notarization-profile}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
DERIVED="$MAC_DIR/build/pkg-deriveddata"
DIST="$MAC_DIR/build/pkg-dist"
APP="$DERIVED/Build/Products/Release/COAH Chorus.app"
PKG="$DIST/COAH-Chorus.pkg"

[ -d "$BACKUP" ] || { echo "Library backup not found: $BACKUP" >&2; exit 1; }
[ -f "$BACKUP/manifest.json" ] || { echo "Backup has no manifest.json: $BACKUP" >&2; exit 1; }
[ -f "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib" ] || {
  echo "NDI SDK runtime missing at /Library/NDI SDK for Apple/lib/macOS/libndi.dylib" >&2
  exit 1
}

rm -rf "$DIST" "$DERIVED"
mkdir -p "$DIST/stage/Applications" "$DIST/stage/Library/Application Support/COAH Chorus"

echo "==> Generating the Xcode project"
xcodegen generate --spec "$MAC_DIR/project.yml" --project "$MAC_DIR" | tail -1

echo "==> Building and signing COAH Chorus"
xcodebuild -project "$MAC_DIR/Chorus.xcodeproj" \
  -scheme Chorus -configuration Release -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

echo "==> Staging the bundled library ($(du -sh "$BACKUP" | awk '{print $1}'))"
ditto "$APP" "$DIST/stage/Applications/COAH Chorus.app"
ditto "$BACKUP" "$DIST/stage/Library/Application Support/COAH Chorus/Bundled Library.mxubackup"

NDI_DYLIB="$DIST/stage/Applications/COAH Chorus.app/Contents/XPCServices/NDIHelper.xpc/Contents/Frameworks/libndi.dylib"
cp "/Library/NDI SDK for Apple/lib/macOS/libndi_licenses.txt" \
  "$DIST/stage/Applications/COAH Chorus.app/Contents/Resources/"
codesign --force --timestamp --sign "$IDENTITY" "$NDI_DYLIB"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$DIST/stage/Applications/COAH Chorus.app"
codesign --verify --strict --deep "$DIST/stage/Applications/COAH Chorus.app"

echo "==> Building and signing package"
pkgbuild --root "$DIST/stage" \
  --identifier com.example.mxuslides \
  --version "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" \
  --sign "$INSTALLER_IDENTITY" "$PKG"

echo "==> Notarizing package"
xcrun notarytool submit "$PKG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
echo "Done: $PKG"
